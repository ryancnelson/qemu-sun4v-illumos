#!/usr/bin/env bash
# Fail-closed host admission gate for an OpenIndiana Niagara trial.
# This script NEVER creates the run directory and NEVER launches QEMU.
set -euo pipefail

required=(RUN_ID RUN_DESIGNATION QEMU QEMU_MANIFEST FIRMWARE_DIR NVRAM
          INSTALLER INSTALLER_MANIFEST TARGET25 TARGET_MANIFEST CHANNEL101
          CHANNEL_MANIFEST RUN_DIR QEMU_SURVIVOR_ALLOWLIST)
for name in "${required[@]}"; do
    [[ -n ${!name:-} ]] || { echo "PRECHECK FAIL: set $name" >&2; exit 1; }
done

die() { printf 'PRECHECK FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }
require_line() {
    grep -Fqx "$2" "$1" || die "$1 lacks: $2"
}
path_is_open() {
    local wanted=$1 fd target
    if command -v lsof >/dev/null 2>&1; then
        lsof "$wanted" 2>/dev/null | grep -q .
        return
    fi
    for fd in /proc/[0-9]*/fd/*; do
        [[ -e $fd ]] || continue
        target=$(readlink -f "$fd" 2>/dev/null || true)
        [[ $target == "$wanted" ]] && return 0
    done
    return 1
}

[[ $(hostname) == niagara-ci-ubuntu ]] || die "wrong host: $(hostname)"
[[ $RUN_ID == oi-bounded-* ]] || die "RUN_ID must start oi-bounded-"
[[ $RUN_DESIGNATION == OI-BOUNDED-* ]] || die "unexpected run designation"
[[ ! -e $RUN_DIR ]] || die "run directory already exists: $RUN_DIR"
tmux has-session -t "$RUN_ID" 2>/dev/null && die "tmux session already exists"

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
pass "every live QEMU is reviewed; concluded failures are gone"

[[ -x $QEMU ]] || die "QEMU is not executable"
[[ -f $QEMU_MANIFEST ]] || die "missing QEMU manifest"
require_line "$QEMU_MANIFEST" 'range_flush_static_gate:PASS'
require_line "$QEMU_MANIFEST" 'multiunit_vdisk_static_gate:PASS'
require_line "$QEMU_MANIFEST" 'one_vcpu_policy:PASS'
[[ -f $FIRMWARE_DIR/openboot.bin && -f $FIRMWARE_DIR/q.bin ]] ||
    die "firmware is incomplete"
[[ -f $NVRAM && $(stat -c %s "$NVRAM") -eq 8192 ]] ||
    die "NVRAM is not an 8,192-byte run-specific file"
cmp -s "$NVRAM" "$FIRMWARE_DIR/nvram1" ||
    die "NVRAM path differs from firmware nvram1 actually loaded by QEMU"

[[ -f $INSTALLER && -f $INSTALLER_MANIFEST ]] || die "installer evidence missing"
[[ -f $TARGET25 && -f $TARGET_MANIFEST ]] || die "target evidence missing"
[[ -f $CHANNEL101 && -f $CHANNEL_MANIFEST ]] || die "channel evidence missing"
[[ $(stat -c %s "$TARGET25") -eq 26843545600 ]] || die "target is not 25 GiB"
[[ $(stat -c %s "$CHANNEL101") -eq 33554432 ]] || die "channel is not 32 MiB"

require_line "$INSTALLER_MANIFEST" 'etc_system:zfs_vdev_aggregation_limit=0x20000:PASS'
require_line "$INSTALLER_MANIFEST" 'hsimd:current:PASS'
require_line "$INSTALLER_MANIFEST" 'ramroot_required_mounts_rw:PASS'
require_line "$INSTALLER_MANIFEST" 'media_root:unit103-slice0-before-media-fs-root:PASS'
require_line "$INSTALLER_MANIFEST" 'media_lofi:usr-and-misc-mounted:PASS'
require_line "$INSTALLER_MANIFEST" 'guest_channel_payload:unit101-block640:PASS'
require_line "$TARGET_MANIFEST" 'size_bytes=26843545600'
require_line "$TARGET_MANIFEST" 'oi_probe_all_features_disabled:PASS'
require_line "$TARGET_MANIFEST" 'oi_probe_clean_export:PASS'
require_line "$CHANNEL_MANIFEST" 'size_bytes=33554432'
require_line "$CHANNEL_MANIFEST" 'mailbox_offsets:verified:PASS'

for path in "$NVRAM" "$TARGET25" "$CHANNEL101"; do
    path_is_open "$path" && die "artifact already open: $path"
done
pass "NVRAM, target, and channel artifacts are exclusively owned"

free_bytes=$(df --output=avail -B1 "$(dirname "$RUN_DIR")" | tail -1)
[[ $free_bytes -ge 32212254720 ]] || die "less than 30 GiB free"
qemu_version=$($QEMU --version | head -1)

cat <<EOF

================ RYAN LAUNCH SIGNOFF ================
RUN DESIGNATION:   $RUN_DESIGNATION
TMUX SESSION:      $RUN_ID
HOST:              $(hostname)
QEMU:              $QEMU
QEMU VERSION:      $qemu_version
FIRMWARE:          $FIRMWARE_DIR
NVRAM:             $NVRAM (8,192 bytes, run-specific)
UNIT 100 / disk0:  $TARGET25 (25 GiB, writable, oi_probe)
UNIT 101 / disk1:  $CHANNEL101 (32 MiB, writable, DO NOT FORMAT)
UNIT 103 / disk3:  $INSTALLER (OpenIndiana installer, read-only)
KERNEL FLAGS:      -k -v
EXPECTED BOOT:     boot /virtual-devices@100/disk@3:d -k -v
QEMU OWNERSHIP:    detached owner plus Unix serial/monitor sockets
RUN DIRECTORY:     $RUN_DIR (absent until GO)

PRE-INSTALL GATES:
  NVRAM readback -> writable RAM root -> unit103 /.cdrom plus lofi mounts ->
  exact hSIMD unit map ->
  oi_probe import/canary/export -> channel echo -> PPP -> NFS -> installer

TYPE NOTHING HERE. Show this block to Ryan and ask for GO or NO-GO.
======================================================
EOF
