#!/usr/bin/env bash
# TEST: bulk host -> guest data transfer via a raw VTOC slice.
#
# Proves the data channel we use to get software (e.g. a compiler) into the
# guest, with no networking, no second serial, and no new emulated device.
#
# Method:
#   1. Clone a test zvol, grow it, add a 512MB exchange slice (s3) inside the
#      range q.bin serves (i.e. within slice 2).
#   2. Host: tar up a payload including a 256KB random binary; dd it into s3.
#   3. Guest: dd from /dev/rdsk/c0t0d0s3 | tar xvf -
#   4. Compare `cksum` of the binary in the guest against the host value.
#
# PASS requires an exact cksum match — byte-for-byte, not "looks plausible".

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(cd "$TESTS_DIR/.." && pwd)"
source "$TESTS_DIR/lib/lock.sh"
source "$TESTS_DIR/lib/disk.sh"
source "$TESTS_DIR/lib/vm.sh"

DISK="test-exch-$$"
WORK="$(mktemp -d)"

cleanup() {
    lock_release "$DISK" 2>/dev/null || true
    disk_destroy "$DISK" || true
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

fail() { echo "FAIL: test-exchange-channel — $1"; exit 1; }

disk_clone "$DISK"
DS="$POOL/$DATASET/$DISK"

# --- host: lay out the exchange slice -----------------------------------
bash "$PROJ/tools/exchange.sh" setup "$DS" >/dev/null \
    || fail "exchange.sh setup failed"

# --- host: build a payload with a binary we can checksum ----------------
mkdir -p "$WORK/payload"
echo "exchange channel test $$" > "$WORK/payload/greeting.txt"
dd if=/dev/urandom of="$WORK/payload/blob.bin" bs=1K count=256 status=none
tar cf "$WORK/payload.tar" -C "$WORK/payload" .
HOST_CKSUM=$(cksum "$WORK/payload/blob.bin" | awk '{print $1, $2}')
BLOCKS=$(( ( $(stat -c%s "$WORK/payload.tar") + 511 ) / 512 ))
echo "OBSERVED: host payload blob cksum = $HOST_CKSUM ($BLOCKS blocks)"

bash "$PROJ/tools/exchange.sh" push "$DS" "$WORK/payload.tar" >/dev/null \
    || fail "exchange.sh push failed"

# --- guest: extract and checksum ----------------------------------------
lock_acquire "$DISK"
out=$(vm_run "$DISK" "$(vm_boot_to_login_script "
    send \"root\r\"
    expect \"# \"
    set timeout 60
    send \"mkdir -p /tmp/x && cd /tmp/x && dd if=/dev/rdsk/c0t0d0s3 bs=512 count=$BLOCKS 2>/dev/null | tar xf - && cksum blob.bin\r\"
    expect {
        \"# \"   { puts \"OBSERVED: extract+cksum returned\" }
        timeout { puts \"OBSERVED: extract timed out\" ; exit 1 }
    }
    $vm_clean_shutdown_fragment
")") || true
echo "$out"

echo "$out" | grep -q "BAD TRAP" && fail "guest panicked"

# cksum output is "<sum> <bytes> <name>"; require an exact match on sum+size
GUEST_LINE=$(echo "$out" | tr -d '\r' | grep -E "^[0-9]+[[:space:]]+[0-9]+[[:space:]]+blob\.bin" | head -1 || true)
[[ -n "$GUEST_LINE" ]] || fail "guest never produced a cksum line for blob.bin"
GUEST_CKSUM=$(echo "$GUEST_LINE" | awk '{print $1, $2}')
echo "OBSERVED: guest blob cksum = $GUEST_CKSUM"

[[ "$GUEST_CKSUM" == "$HOST_CKSUM" ]] \
    || fail "cksum mismatch: host [$HOST_CKSUM] vs guest [$GUEST_CKSUM]"

echo "PASS: test-exchange-channel"
