#!/usr/bin/env bash
# TEST: BIDIRECTIONAL host <-> guest file exchange via FAT32 on VTOC slice 3.
#
# The raw-slice channel (test-exchange-channel) is one-shot and one-way: a tar
# blasted at raw blocks, with the block count passed to the guest by hand. This
# proves the better channel — a real filesystem both sides mount:
#   host:  mkfs.vfat / mount -t vfat   (Linux vfat is fully read-write)
#   guest: mount -F pcfs /dev/dsk/c0t0d0s3:c   (":c" = whole logical drive)
#
# Method:
#   1. Clone, `exchange.sh setup` (grow volsize + write VTOC), `mkfs` slice 3.
#   2. Host puts a 256KB random BLOB.BIN on the FAT slice.
#   3. Guest mounts pcfs, cksums BLOB.BIN, and copies it to ECHO.BIN.
#   4. Guest shuts down with init 5 so the writeback persists its writes.
#   5. Host mounts the slice again and cksums ECHO.BIN.
#
# PASS requires TWO exact cksum matches on the same 256KB of random data:
#   host->guest  (guest's cksum of BLOB.BIN == host's)
#   guest->host  (host's cksum of ECHO.BIN  == host's original)
# Anything less would pass on an empty or truncated filesystem.
#
# Note this test NEEDS $vm_halt_writeback_fragment rather than
# $vm_clean_shutdown_fragment: guest writes only reach the zvol via the atexit
# writeback, which requires `init 5` plus a SIGTERM'd QEMU. The Ctrl-A monitor
# escape does not work from a scripted expect.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/lib/lock.sh"
source "$TESTS_DIR/lib/zvol.sh"
source "$TESTS_DIR/lib/vm.sh"

ZVOL="vms/test-fatx-$$"
WORK="$(mktemp -d)"
# Keep this test's host-side mount away from any interactive one.
export FAT_MNT="/mnt/niagara-fatx-$$"

cleanup() {
    mountpoint -q "$FAT_MNT" 2>/dev/null && umount "$FAT_MNT" 2>/dev/null || true
    bash "$PROJ/tools/exchange.sh" umount "$POOL/$DATASET/$ZVOL" >/dev/null 2>&1 || true
    rmdir "$FAT_MNT" 2>/dev/null || true
    lock_release "$ZVOL" 2>/dev/null || true
    zvol_destroy "$ZVOL" || true      # NOT 2>/dev/null: let leak warnings through
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

fail() { echo "FAIL: test-fat-exchange — $1"; exit 1; }

zvol_clone "$ZVOL"
DS="$POOL/$DATASET/$ZVOL"

# --- host: lay out and format the slice ---------------------------------
bash "$PROJ/tools/exchange.sh" setup "$DS" >/dev/null || fail "exchange.sh setup failed"
bash "$PROJ/tools/exchange.sh" mkfs  "$DS" >/dev/null || fail "exchange.sh mkfs failed"

# --- host -> slice ------------------------------------------------------
dd if=/dev/urandom of="$WORK/BLOB.BIN" bs=1K count=256 status=none
HOST_CKSUM=$(cksum "$WORK/BLOB.BIN" | awk '{print $1, $2}')
echo "OBSERVED: host BLOB.BIN cksum = $HOST_CKSUM"
bash "$PROJ/tools/exchange.sh" put "$DS" "$WORK/BLOB.BIN" >/dev/null \
    || fail "exchange.sh put failed"

# --- guest: mount, verify, write back -----------------------------------
lock_acquire "$ZVOL"
out=$(vm_run "$ZVOL" "$(vm_boot_to_login_script "
    send \"root\r\"
    expect \"# \"
    send \"mkdir -p /x\r\"
    expect \"# \"
    set timeout 60
    send \"mount -F pcfs /dev/dsk/c0t0d0s3:c /x 2>&1\r\"
    expect \"# \"
    send \"df -k /x 2>&1 | tail -1\r\"
    expect \"# \"
    send \"cksum /x/BLOB.BIN 2>&1\r\"
    expect {
        \"# \"   { puts \"OBSERVED: guest cksum returned\" }
        timeout { puts \"OBSERVED: guest cksum timed out\"; exit 1 }
    }
    send \"cp /x/BLOB.BIN /x/ECHO.BIN 2>&1\r\"
    expect \"# \"
    send \"ls -l /x 2>&1\r\"
    expect \"# \"
    send \"umount /x 2>&1\r\"
    expect \"# \"
    $vm_halt_writeback_fragment
")") || true
echo "$out"

echo "$out" | grep -q "BAD TRAP" && fail "guest panicked"
echo "$out" | tr -d '\r' | grep -q 'pcfs.*/x\|/dev/dsk/c0t0d0s3:c' \
    || fail "guest never mounted the FAT slice (pcfs)"

# Direction 1: host -> guest. cksum output is "<sum> <bytes> <name>".
GUEST_LINE=$(echo "$out" | tr -d '\r' \
             | grep -E "^[0-9]+[[:space:]]+[0-9]+[[:space:]]+/x/BLOB\.BIN" | head -1 || true)
[[ -n "$GUEST_LINE" ]] || fail "guest produced no cksum line for BLOB.BIN"
GUEST_CKSUM=$(echo "$GUEST_LINE" | awk '{print $1, $2}')
echo "OBSERVED: guest BLOB.BIN cksum = $GUEST_CKSUM"
[[ "$GUEST_CKSUM" == "$HOST_CKSUM" ]] \
    || fail "host->guest mismatch: host [$HOST_CKSUM] vs guest [$GUEST_CKSUM]"

# Direction 2: guest -> host. The writeback must have persisted ECHO.BIN.
echo "$out" | grep -q "vdisk writeback complete" \
    || fail "no writeback: guest writes cannot have reached the zvol"
bash "$PROJ/tools/exchange.sh" get "$DS" ECHO.BIN "$WORK/ECHO.BIN" >/dev/null \
    || fail "ECHO.BIN not retrievable from the slice (guest write did not persist)"
BACK_CKSUM=$(cksum "$WORK/ECHO.BIN" | awk '{print $1, $2}')
echo "OBSERVED: retrieved ECHO.BIN cksum = $BACK_CKSUM"
[[ "$BACK_CKSUM" == "$HOST_CKSUM" ]] \
    || fail "guest->host mismatch: expected [$HOST_CKSUM] got [$BACK_CKSUM]"

echo "PASS: test-fat-exchange"
