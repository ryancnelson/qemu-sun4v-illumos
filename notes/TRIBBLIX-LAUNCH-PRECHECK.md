# Tribblix launch precheck — Ryan signoff required

This is the fail-closed launch contract for every new Tribblix Niagara QEMU
run.  It prevents stale root-device defaults, read-only `devfsadm` failures,
missing disks, unsafe consoles, and untraceable artifact substitutions from
consuming another boot cycle.

**This precheck never launches QEMU.**  It prints the complete proposed run
manifest and stops at a Ryan `GO`/`NO-GO` gate.  A run may enter Kanban **In
progress** only after the applicable durable cards are linked, all host-side
checks pass, and Ryan has seen the exact manifest.

## Standard run topology

- Physical host: explicitly named before launch; Exabyte is preferred for the
  current fast-iteration run
- Guest: Tribblix SPARC installer/live environment
- CPU topology: one virtual CPU until storage, installation, and cold boot are
  anchored
- Memory: 3 GiB
- Writable installation/probe disk: 25 GiB, unit 100 / hSIMD `disk@0`
- Channel/mailbox disk: 32 MiB, unit 101 / hSIMD `disk@1`
- Installer medium: read-only, unit 103 / hSIMD `disk@3`
- Kernel diagnostics: mandatory KMDB, `-k -v`; first archive-validation boot
  also uses `-a`
- Console: Unix socket viewed through a tmux window; QEMU never owns the
  interactive terminal
- Monitor: separate Unix socket

If Ryan asks for an *additional* 25 GiB disk rather than a replacement unit-100
target, stop and assign it a new explicit hSIMD unit.  Never infer that choice.

## Tribblix boot-archive requirements

The build must produce a new isolated archive and a sidecar manifest proving
all of these after reopening the finished archive:

1. `/etc/system` contains:

   ```text
   set root_is_ramdisk=1
   rootdev:/ramdisk-root:a
   set zfs:zfs_vdev_aggregation_limit=0x20000
   ```

2. The prior verified `ramdisk_size` is preserved exactly.
3. No stale `disk@0:a`, `disk@3:d`, or other physical-disk root directive
   remains in `/etc/system` or the boot-archive startup configuration.
4. The current hSIMD module is present at
   `/platform/sun4v/kernel/drv/sparcv9/hsimd`, with matching `name_to_major`,
   `driver_aliases`, and `path_to_inst` entries.
5. The first startup action remounts the actual RAM root read-write before
   anything invokes `devfsadm`.
6. Startup requires this canary to succeed before `devfsadm`:

   ```sh
   touch /etc/dev/.devfsadm_write_test || exit 1
   rm /etc/dev/.devfsadm_write_test
   ```

7. `/`, `/etc`, `/etc/dev`, `/devices`, and `/dev` are writable where the live
   environment requires writes.  No read-only backing mount is hidden by an
   unverified overlay.
8. The guest channel utilities required for echo, PPP, and the safe secondary
   console are present.  Do not claim networking readiness from host daemons
   alone.

## NVRAM and OpenBoot gate

The NVRAM file is a run-specific 8,192-byte copy.  No other QEMU may have it
open.  Critical root selection does **not** depend on NVRAM because interactive
`setenv` persistence has not been proven in this QEMU build.

At the first fresh `ok` prompt, run and capture:

```text
printenv auto-boot?
printenv boot-device
printenv boot-file
printenv use-nvramrc?
printenv nvramrc
printenv diag-switch?
printenv input-device
printenv output-device
devalias
```

Required policy:

- `auto-boot? = false` for the diagnostic boot;
- `boot-file` is empty;
- `use-nvramrc? = false` and `nvramrc` is empty;
- no stale `/ramdisk-root:a` NVRAM experiment is present;
- `devalias` is recorded but never treated as the authoritative unit map.

## Host-side precheck script

Run this on the selected physical host after staging artifacts.  Every path is
explicit; “newest” or wildcard artifact selection is forbidden.

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${RUN_ID:?set a new descriptive RUN_ID}"
: "${EXPECTED_HOST:?set the exact physical hostname}"
: "${QEMU:?set the exact qemu-system-sparc64 path}"
: "${FIRMWARE_DIR:?set the exact firmware directory}"
: "${NVRAM:?set the run-specific nvram1 path}"
: "${INSTALLER:?set the exact Tribblix candidate path}"
: "${INSTALLER_MANIFEST:?set its build-evidence sidecar path}"
: "${TARGET25:?set the run-specific 25 GiB target path}"
: "${TARGET_MANIFEST:?set the target-pool evidence sidecar path}"
: "${CHANNEL101:?set the run-specific 32 MiB channel image path}"
: "${CHANNEL_MANIFEST:?set the channel-layout sidecar path}"
: "${RUN_DIR:?set the new run directory}"

die() { printf 'PRECHECK FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }
require_line() {
  local file=$1 line=$2
  grep -Fqx "$line" "$file" || die "$file lacks: $line"
}

[[ $(hostname) == "$EXPECTED_HOST" ]] ||
  die "wrong physical host: expected $EXPECTED_HOST, got $(hostname)"
[[ $RUN_ID == tribblix-bounded-* ]] ||
  die "RUN_ID must start tribblix-bounded-"
[[ ! -e $RUN_DIR ]] || die "RUN_DIR already exists: $RUN_DIR"
tmux has-session -t "$RUN_ID" 2>/dev/null && die "tmux session already exists"

# Whole-host admission gate.  Every surviving QEMU must be named in an
# explicit, reviewed allowlist.  Failed, panicked, abandoned, and unidentified
# QEMUs must be stopped before this run can proceed.
: "${QEMU_SURVIVOR_ALLOWLIST:?set to a reviewed file; use an empty file when no QEMU should survive}"
[[ -f $QEMU_SURVIVOR_ALLOWLIST ]] || die "missing QEMU survivor allowlist"
live_qemus=$(mktemp)
trap 'rm -f "$live_qemus"' EXIT
ps -eo pid=,comm=,args= | awk '$2 ~ /^qemu-system-sp/ {print}' >"$live_qemus"
while IFS= read -r live; do
  [[ -z $live ]] && continue
  grep -Fqx "$live" "$QEMU_SURVIVOR_ALLOWLIST" ||
    die "unreviewed live QEMU: $live"
done <"$live_qemus"
while IFS= read -r allowed; do
  [[ -z $allowed ]] && continue
  grep -Fqx "$allowed" "$live_qemus" ||
    die "allowlisted QEMU is not running: $allowed"
done <"$QEMU_SURVIVOR_ALLOWLIST"
pass "every live QEMU is explicitly allowlisted; concluded failures are gone"

[[ -x $QEMU ]] || die "QEMU is not executable: $QEMU"
[[ -f $FIRMWARE_DIR/openboot.bin ]] || die "missing openboot.bin"
[[ -f $FIRMWARE_DIR/q.bin ]] || die "missing q.bin"
[[ -f $NVRAM ]] || die "missing run-specific NVRAM"
[[ $(stat -c %s "$NVRAM") -eq 8192 ]] || die "NVRAM is not 8,192 bytes"
[[ -f $INSTALLER ]] || die "missing installer"
[[ -f $INSTALLER_MANIFEST ]] || die "missing installer manifest"
[[ -f $TARGET25 ]] || die "missing 25 GiB target"
[[ -f $TARGET_MANIFEST ]] || die "missing target manifest"
[[ -f $CHANNEL101 ]] || die "missing channel image"
[[ -f $CHANNEL_MANIFEST ]] || die "missing channel manifest"

[[ $(stat -c %s "$TARGET25") -eq $((25 * 1024 * 1024 * 1024)) ]] ||
  die "target is not exactly 25 GiB"
[[ $(stat -c %s "$CHANNEL101") -eq $((32 * 1024 * 1024)) ]] ||
  die "channel image is not exactly 32 MiB"

require_line "$INSTALLER_MANIFEST" 'etc_system:root_is_ramdisk=1:PASS'
require_line "$INSTALLER_MANIFEST" 'etc_system:rootdev=/ramdisk-root:a:PASS'
require_line "$INSTALLER_MANIFEST" 'etc_system:no_stale_physical_root:PASS'
require_line "$INSTALLER_MANIFEST" 'etc_system:zfs_vdev_aggregation_limit=0x20000:PASS'
require_line "$INSTALLER_MANIFEST" 'ramdisk_size:preserved:PASS'
require_line "$INSTALLER_MANIFEST" 'hsimd:current:PASS'
require_line "$INSTALLER_MANIFEST" 'ramroot_rw_before_devfsadm:PASS'
require_line "$INSTALLER_MANIFEST" 'devfsadm_write_canary:present:PASS'
require_line "$INSTALLER_MANIFEST" 'guest_channel_payload:complete:PASS'

require_line "$TARGET_MANIFEST" 'size_bytes=26843545600'
require_line "$TARGET_MANIFEST" 'oi_probe_all_features_disabled:PASS'
require_line "$TARGET_MANIFEST" 'oi_probe_clean_export:PASS'
require_line "$CHANNEL_MANIFEST" 'size_bytes=33554432'
require_line "$CHANNEL_MANIFEST" 'mailbox_offsets:verified:PASS'

if command -v lsof >/dev/null; then
  lsof "$NVRAM" | grep -q . && die "NVRAM is already open"
  lsof "$TARGET25" | grep -q . && die "25 GiB target is already open"
  lsof "$CHANNEL101" | grep -q . && die "channel image is already open"
fi

QEMU_VERSION=$($QEMU --version | head -1)
FREE_BYTES=$(df --output=avail -B1 "$(dirname "$RUN_DIR")" | tail -1)
[[ $FREE_BYTES -ge $((30 * 1024 * 1024 * 1024)) ]] ||
  die "less than 30 GiB free for run/log/copy headroom"

pass "physical host and unique run identity"
pass "NVRAM size and exclusivity"
pass "RAM-root default, hSIMD, bounded-I/O, and writable-devfs archive gates"
pass "25 GiB target and 32 MiB channel manifests"
pass "target, channel, and NVRAM are not owned by another process"

cat <<EOF

================ RYAN LAUNCH SIGNOFF ================
RUN_ID:           $RUN_ID
HOST:             $(hostname)
QEMU:             $QEMU
QEMU_VERSION:     $QEMU_VERSION
FIRMWARE:         $FIRMWARE_DIR
NVRAM:            $NVRAM (8,192 bytes, run-specific)
UNIT 100 / disk0: $TARGET25 (25 GiB, writable, oi_probe)
UNIT 101 / disk1: $CHANNEL101 (32 MiB, writable, DO NOT FORMAT)
UNIT 103 / disk3: $INSTALLER (Tribblix installer, read-only)
DIAGNOSTIC BOOT:  boot /virtual-devices@100/disk@3:d -a -k -v
ACCEPTANCE BOOT:  boot /virtual-devices@100/disk@3:d -k -v
EXPECTED ROOT DEFAULT: /ramdisk-root:a
QEMU OWNER:       tools/openindiana/qemu-owner.sh
CONSOLE:          Unix socket in a separate tmux window
MONITOR:          separate Unix socket
RUN DIRECTORY:    $RUN_DIR (created only after GO)

TYPE NOTHING HERE. Show this block to Ryan and ask for GO or NO-GO.
======================================================
EOF
```

## Diagnostic Return-only acceptance boot

After `GO`, the first boot command is:

```text
boot /virtual-devices@100/disk@3:d -a -k -v
```

The console must display these literal defaults:

```text
Name of system file [/etc/system]:
Retire store [/etc/devices/retire_store]:
root filesystem type [ufs]:
Enter physical name of root device [/ramdisk-root:a]:
```

Pressing Return at every prompt must produce all of these before the run can
continue:

- `root on /ramdisk-root:a fstype ufs`;
- writable-mount evidence for `/`, `/etc`, `/etc/dev`, `/devices`, and `/dev`;
- successful `/etc/dev/.devfsadm_write_test` creation/removal;
- no read-only error from the first `devfsadm`;
- current hSIMD module loaded and the intended unit map observed;
- installer menu reached.

If any default differs, stop the run.  Do not manually enter the right value
and count the boot as a pass.

## Unattended archive acceptance boot

After the Return-only gate passes, use a fresh QEMU with isolated writable
images and boot:

```text
boot /virtual-devices@100/disk@3:d -k -v
```

It must reach the installer menu without a root-device question.  Only then
proceed to the shell gates, channel echo, PPP, NFS, installation, and cold-boot
acceptance.

## Shell, networking, and installation gates

1. Identify unit 100 by independent size, path, and pool-label evidence; do not
   trust broken `format`/ioctl output alone.
2. Import `oi_probe` without upgrading it.  Capture `zpool status`, feature
   state, and dataset properties.
3. Write, sync, and read back a named canary; export `oi_probe` cleanly.
4. Prove unit 101 channel echo before attempting PPP.
5. Bring up PPP and pass routed packets in both directions.
6. Mount NFS and read a predeclared canary.
7. Only then allow the installer to relabel unit 100 and install Tribblix.
8. Install/update the boot archive on the target, export cleanly, and cold boot
   it in a fresh QEMU.
9. The cold boot must reach multiuser login and re-pass channels, PPP, NFS,
   persistent canary, observability, and performance gates.

Serial-console commands must remain short; keep each line well below the known
approximately 256-character failure boundary.

## Launch construction after `GO`

The generated QEMU command must contain exactly these drive clauses:

```text
-drive id=target25,format=raw,if=none,bus=0,unit=100,readonly=off,cache=none,file=$TARGET25
-drive id=channel101,format=raw,if=none,bus=0,unit=101,readonly=off,cache=none,file=$CHANNEL101
-drive id=installer103,format=raw,if=none,bus=0,unit=103,readonly=on,cache=none,file=$INSTALLER
```

Save the expanded command as `$RUN_DIR/qemu.argv` and the signed-off manifest
as `$RUN_DIR/launch-manifest.txt`.  Create a persistent tmux session with
separate `shell`, `console`, and `monitor` windows.  Start QEMU through
`tools/openindiana/qemu-owner.sh`, with a Unix serial socket.  Closing or
interrupting the watch console must never terminate QEMU.

## Immediate abort conditions

- Any missing or substituted artifact after signoff
- Root-device default is not literally `/ramdisk-root:a`
- Any required live-root path remains read-only before `devfsadm`
- First `devfsadm` reports its lock path read-only
- Unit 101 is absent, mis-sized, or offered as an installation target
- Unit 103 is writable
- Boot lacks `-k -v`
- QEMU owns the interactive terminal or uses `-serial stdio`
- Target, channel image, or NVRAM is already open elsewhere
- Pool is imported on the host when QEMU is about to start
- hSIMD request exceeds `0x20000` during the bounded run
- Channel echo, PPP, or NFS is claimed from process presence rather than an
  end-to-end canary
