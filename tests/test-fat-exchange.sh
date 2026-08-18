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
source "$TESTS_DIR/lib/disk.sh"
source "$TESTS_DIR/lib/vm.sh"

ZVOL="vms/test-fatx-$$"
WORK="$(mktemp -d)"
# Keep this test's host-side mount away from any interactive one.
export FAT_MNT="/mnt/niagara-fatx-$$"

cleanup() {
    mountpoint -q "$FAT_MNT" 2>/dev/null && umount "$FAT_MNT" 2>/dev/null || true
    bash "$PROJ/tools/exchange.sh" umount "$POOL/$DATASET/$ZVOL" >/dev/null 2>&1 || true
    rmdir "$FAT_MNT" 2>/dev/null || true
    lock_release "$DISK" 2>/dev/null || true
    disk_destroy "$DISK" || true      # NOT 2>/dev/null: let leak warnings through
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

fail() { echo "FAIL: test-fat-exchange — $1"; exit 1; }

disk_clone "$DISK"
DS="$POOL/$DATASET/$ZVOL"

# --- host: lay out and format the slice ---------------------------------
bash "$PROJ/tools/exchange.sh" setup "$DS" >/dev/null || fail "exchange.sh setup failed"
bash "$PROJ/tools/exchange.sh" mkfs  "$DS" >/dev/null || fail "exchange.sh mkfs failed"

# --- P1-008: mkfs must NOT eat the scratch tail -------------------------
# `exchange.sh mkfs` used to format the whole 512MB slice, silently reclaiming
# the 16MB tail that lies outside any filesystem. Nothing errored; the region
# just stopped existing. Asserted here so the suite enforces it.
#
# The canary is REAL TEXT, deliberately not zeros: cksum of 512 zero bytes is
# 4135437457, and a zeros-vs-zeros comparison passes without proving anything.
# An earlier PoC in this project reported exactly that value as a success and was
# in fact reading an empty region.
eval "$(bash "$PROJ/tools/exchange.sh" scratch)" || fail "exchange.sh scratch failed"
SDEV=$(img_require "$DS") || fail "cannot resolve image for $DS"
CANARY="P1-008-CANARY-$$"
printf '%s' "$CANARY" | dd of="$SDEV" bs=512 seek="$SCRATCH_START_BLK" count=1 \
    conv=notrunc,sync status=none || fail "could not seed the scratch canary"
SEED_CK=$(dd if="$SDEV" bs=512 skip="$SCRATCH_START_BLK" count=1 status=none \
            | cksum | awk '{print $1}')
[[ "$SEED_CK" != 4135437457 ]] \
    || fail "scratch canary seed did not land (region still all zeros)"
echo "OBSERVED: scratch canary seeded, cksum = $SEED_CK"

bash "$PROJ/tools/exchange.sh" mkfs "$DS" >/dev/null || fail "second mkfs failed"

GOT=$(dd if="$SDEV" bs=512 skip="$SCRATCH_START_BLK" count=1 status=none | tr -d '\0')
echo "OBSERVED: scratch canary after mkfs = '$GOT'"
[[ "$GOT" == "$CANARY" ]] \
    || fail "mkfs destroyed the scratch region (expected '$CANARY', got '$GOT')"

# --- host -> slice ------------------------------------------------------
dd if=/dev/urandom of="$WORK/BLOB.BIN" bs=1K count=256 status=none
HOST_CKSUM=$(cksum "$WORK/BLOB.BIN" | awk '{print $1, $2}')
echo "OBSERVED: host BLOB.BIN cksum = $HOST_CKSUM"
bash "$PROJ/tools/exchange.sh" put "$DS" "$WORK/BLOB.BIN" >/dev/null \
    || fail "exchange.sh put failed"

# --- guest: mount, verify, write back -----------------------------------
lock_acquire "$DISK"
out=$(vm_run "$DISK" "$(vm_boot_to_login_script "
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
