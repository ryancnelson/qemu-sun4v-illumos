# OpenIndiana launch precheck — Ryan signoff required

This is the fail-closed launch contract for every new OpenIndiana Niagara
QEMU run.  It exists to prevent a stale command line, missing disk, wrong
archive, or unsafe console from consuming another boot cycle.

**The precheck does not launch QEMU.**  It prints the complete proposed run
manifest and ends at a Ryan `GO`/`NO-GO` gate.  A run may enter Kanban **In
progress** only after this document's checks pass and Ryan has seen the exact
manifest.

## Requested run

- Physical host: **Exabyte** (`niagara-ci-ubuntu`)
- Guest: OpenIndiana SPARC text installer
- CPU topology: one virtual CPU until the storage/install path is anchored
- Memory: 3 GiB
- Writable installation/probe disk: **25 GiB**, unit 100 / hSIMD `disk@0`
- Channel/mailbox disk: 32 MiB, unit 101 / hSIMD `disk@1`
- Installer medium: read-only, unit 103 / hSIMD `disk@3`
- Kernel diagnostics: mandatory KMDB, booted with `-k -v`
- Console: Unix socket viewed through a tmux window; QEMU never owns the
  interactive terminal
- Monitor: a separate Unix socket

The 25 GiB disk is initially a cleanly exported, featureless `oi_probe` pool.
The installer shell first imports it and performs the canary gate.  Before the
text installer is allowed to relabel it as `rpool`, `oi_probe` must be exported
cleanly.  The run log must make this intentional destruction explicit.

## Build-time requirements

These are properties of the artifacts, not actions to improvise at the
console:

1. The boot archive contains the current hSIMD driver and its matching
   `name_to_major`, `driver_aliases`, and `path_to_inst` entries.
2. Its `/etc/system` contains the temporary safety bound:

   ```text
   set zfs:zfs_vdev_aggregation_limit=0x20000
   ```

3. The archive was reopened after mutation and the literal setting above was
   read back.  The build emits a sidecar manifest containing that evidence;
   the launch precheck refuses an artifact without it.
4. The live RAM root provides writable `/`, `/etc`, `/etc/dev`, `/devices`,
   and `/dev` before `devfsadm`.  Read-only `/.cdrom`, `/usr`, and `/mnt/misc`
   are expected and are not failures.
5. The installer and target are isolated copies.  No running QEMU may have the
   25 GiB file open.
6. The 25 GiB pool was created with all feature flags disabled, `ashift=9`,
   `recordsize=8K`, `compression=off`, `atime=off`, `sync=always`, and was
   exported cleanly.
7. The channel image is a run-specific copy whose mailbox/slice offsets come
   from the current manifest.  It must never be formatted by the installer.

## Host-side precheck script

Run this on Exabyte after staging artifacts.  Supply paths explicitly; do not
let a launcher discover “the newest” file.

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${RUN_ID:?set a new descriptive RUN_ID}"
: "${QEMU:?set the exact qemu-system-sparc64 path}"
: "${FIRMWARE_DIR:?set the exact firmware directory}"
: "${INSTALLER:?set the exact patched OpenIndiana installer path}"
: "${INSTALLER_MANIFEST:?set its build-evidence sidecar path}"
: "${TARGET25:?set the run-specific 25 GiB target path}"
: "${CHANNEL101:?set the run-specific 32 MiB channel image path}"
: "${RUN_DIR:?set the new run directory}"

die() { printf 'PRECHECK FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

[[ $(hostname) == niagara-ci-ubuntu ]] || die "wrong physical host: $(hostname)"
[[ $RUN_ID == oi-bounded-* ]] || die "RUN_ID must start oi-bounded-"
[[ ! -e $RUN_DIR ]] || die "RUN_DIR already exists: $RUN_DIR"
tmux has-session -t "$RUN_ID" 2>/dev/null && die "tmux session already exists"

[[ -x $QEMU ]] || die "QEMU is not executable: $QEMU"
[[ -f $FIRMWARE_DIR/openboot.bin ]] || die "missing openboot.bin"
[[ -f $FIRMWARE_DIR/q.bin ]] || die "missing q.bin"
[[ -f $INSTALLER ]] || die "missing installer"
[[ -f $INSTALLER_MANIFEST ]] || die "missing installer build evidence"
[[ -f $TARGET25 ]] || die "missing 25 GiB target"
[[ -f $CHANNEL101 ]] || die "missing channel image"

[[ $(stat -c %s "$TARGET25") -eq $((25 * 1024 * 1024 * 1024)) ]] || \
  die "target is not exactly 25 GiB"
[[ $(stat -c %s "$CHANNEL101") -eq $((32 * 1024 * 1024)) ]] || \
  die "channel image is not exactly 32 MiB"

grep -Fqx 'etc_system:zfs_vdev_aggregation_limit=0x20000:PASS' \
  "$INSTALLER_MANIFEST" || die "bounded-I/O /etc/system readback absent"
grep -Fqx 'hsimd:current:PASS' "$INSTALLER_MANIFEST" || \
  die "current hSIMD provenance absent"
grep -Fqx 'ramroot_required_mounts_rw:PASS' "$INSTALLER_MANIFEST" || \
  die "RAM-root writable-mount gate absent"
grep -Fqx 'oi_probe_all_features_disabled:PASS' "$INSTALLER_MANIFEST" || \
  die "featureless-pool evidence absent"
grep -Fqx 'oi_probe_clean_export:PASS' "$INSTALLER_MANIFEST" || \
  die "clean-export evidence absent"

if command -v lsof >/dev/null && lsof "$TARGET25" | grep -q .; then
  die "25 GiB target is already open"
fi

QEMU_VERSION=$($QEMU --version | head -1)
FREE_BYTES=$(df --output=avail -B1 "$(dirname "$RUN_DIR")" | tail -1)
[[ $FREE_BYTES -ge $((30 * 1024 * 1024 * 1024)) ]] || \
  die "less than 30 GiB free for run/log/copy headroom"

pass "physical host is Exabyte"
pass "new run identity is unused"
pass "25 GiB target and 32 MiB channel sizes are exact"
pass "bounded-I/O, hSIMD, writable-root, and pool-export evidence exists"
pass "target is not open by another process"

cat <<EOF

================ RYAN LAUNCH SIGNOFF ================
RUN_ID:           $RUN_ID
HOST:             $(hostname)
QEMU:             $QEMU
QEMU_VERSION:     $QEMU_VERSION
FIRMWARE:         $FIRMWARE_DIR
UNIT 100 / disk0: $TARGET25  (25 GiB, writable, oi_probe)
UNIT 101 / disk1: $CHANNEL101  (32 MiB, writable, DO NOT FORMAT)
UNIT 103 / disk3: $INSTALLER  (installer, read-only)
KERNEL FLAGS:     -k -v
RAM ROOT:         writable-mount gate required before devfsadm
ZFS I/O BOUND:    0x20000 proven in archive manifest
QEMU OWNER:       tools/openindiana/qemu-owner.sh
CONSOLE:          Unix socket in a separate tmux window
MONITOR:          separate Unix socket
RUN DIRECTORY:    $RUN_DIR (must be created only after GO)

EXPECTED BOOT COMMAND:
  boot /virtual-devices@100/disk@3:d -k -v

PRE-INSTALL SHELL GATES:
  1. Prove required RAM-root paths writable.
  2. Prove hSIMD unit mapping from multiple independent observations.
  3. Import oi_probe without upgrade; verify all features disabled.
  4. Write, sync, and read back a named canary.
  5. Export oi_probe cleanly.
  6. Only then allow the installer to relabel unit 100 as rpool.

TYPE NOTHING HERE. Show this block to Ryan and ask for GO or NO-GO.
======================================================
EOF
```

## Launch construction after `GO`

The launch command must be generated from the signed-off values above.  It
must contain exactly these drive clauses:

```text
-drive id=target25,format=raw,if=none,bus=0,unit=100,readonly=off,cache=none,file=$TARGET25
-drive id=channel101,format=raw,if=none,bus=0,unit=101,readonly=off,cache=none,file=$CHANNEL101
-drive id=installer103,format=raw,if=none,bus=0,unit=103,readonly=on,cache=none,file=$INSTALLER
```

Before QEMU starts, save the fully expanded command in `$RUN_DIR/qemu.argv`,
save the signoff manifest in `$RUN_DIR/launch-manifest.txt`, and create a
persistent tmux session with separate `shell`, `console`, and `monitor`
windows.  Start QEMU through `tools/openindiana/qemu-owner.sh`; connect the
console window to QEMU's Unix serial socket.  Closing the console window or
typing `Ctrl-C` there must not terminate QEMU.

## Immediate abort conditions

Do not “see what happens” after any of these:

- unit 100 is not exactly 25 GiB;
- unit 101 is absent or presented as an installation target;
- unit 103 is writable;
- the expected hSIMD driver or aggregation tunable lacks readback evidence;
- the boot command lacks `-k -v`;
- the run uses QEMU `-serial stdio` or puts QEMU directly in the watch pane;
- `oi_probe` is imported anywhere when QEMU is about to start;
- the first installer-shell canary or clean export fails;
- any hSIMD request exceeds `0x20000` during the bounded-I/O run.

