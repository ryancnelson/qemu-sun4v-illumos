#!/usr/bin/env bash
# TEST: a file written inside the guest survives a full QEMU restart.
#
# This is the storage trust test. It asserts the property we actually care
# about — not "a write was acknowledged" but "the data is still there, and
# the disk is still bootable, after a complete power cycle".
#
# Method:
#   Session 1: boot, log in, write canary to /etc (ROOT UFS), lockfs, clean exit
#   Host:      search the raw zvol for the canary  -> proves atexit writeback
#   Session 2: boot the SAME zvol, cat the file    -> proves it is really there
#                                                     and the image still boots
#
# PASS requires all three. FAIL on any.
#
# HISTORY — two bugs this test previously had, do not reintroduce them:
#   1. It wrote the canary to /tmp. /tmp is tmpfs (`swap - /tmp tmpfs` in the
#      guest's vfstab). It never touched the disk, so the test could only ever
#      fail no matter how well storage worked. Write to /etc.
#   2. It exited without `lockfs -f /`. The atexit writeback then persisted a
#      dirty LUFS journal, and the next boot panicked in ufs:fetchbuf. Use
#      $vm_clean_shutdown_fragment.
#   3. It matched an echo-able marker: `send "... && echo WROTE_OK"` then
#      `expect "WROTE_OK"`. The tty echoes the command as it is typed, so
#      expect matched the ECHO and continued before the shell ran anything —
#      QEMU was quit before the write happened. Match the prompt "# " instead.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TESTS_DIR/lib/lock.sh"
source "$TESTS_DIR/lib/zvol.sh"
source "$TESTS_DIR/lib/vm.sh"

ZVOL="vms/test-write-$$"
CANARY="NIAGARA_PERSIST_$$_$(date +%s)"

cleanup() {
    lock_release "$ZVOL" 2>/dev/null || true
    zvol_destroy "$ZVOL" || true      # NOT 2>/dev/null: let leak warnings through
}
trap cleanup EXIT INT TERM

fail() { echo "FAIL: test-disk-writes-persist — $1"; exit 1; }

echo "Canary: $CANARY"
zvol_clone "$ZVOL"
lock_acquire "$ZVOL"

# ---- Session 1: write it ------------------------------------------------
# NOTE: match the prompt, not an echoed marker. See bug 3 above.
out1=$(vm_run "$ZVOL" "$(vm_boot_to_login_script "
    send \"root\r\"
    expect \"# \"
    set timeout 30
    send \"echo $CANARY > /etc/niagara_canary.txt\r\"
    expect {
        \"# \"   { puts \"OBSERVED: write command returned to prompt\" }
        timeout { puts \"OBSERVED: write command never returned\" ; exit 1 }
    }
    $vm_clean_shutdown_fragment
")")
echo "$out1"

echo "$out1" | grep -q "OBSERVED: write command returned to prompt" \
    || fail "guest never completed the write command"
echo "$out1" | grep -q "OBSERVED: lockfs+sync returned to prompt" \
    || fail "lockfs did not complete — journal left dirty"
# ---- Host: did the writeback reach the zvol? ----------------------------
lock_release "$ZVOL"
DEV=$(zvol_path "$ZVOL")

# Use `grep -a` directly on the device. Do NOT use `strings "$DEV" | grep -q`:
# grep -q exits on first match, strings then dies of SIGPIPE (141), and with
# `set -o pipefail` the pipeline reports FAILURE even though the match
# succeeded. That masked a working writeback as a failing test.
if grep -a -q -F "$CANARY" "$DEV"; then
    echo "OBSERVED: canary present in raw zvol $DEV"
else
    fail "canary absent from raw zvol — atexit writeback did not persist it"
fi

# ---- Session 2: is it still there, and does it still boot? -------------
lock_acquire "$ZVOL"
out2=$(vm_run "$ZVOL" "$(vm_boot_to_login_script "
    send \"root\r\"
    expect \"#\"
    set timeout 30
    send \"cat /etc/niagara_canary.txt\r\"
    expect {
        \"$CANARY\" { puts \"OBSERVED: canary read back after restart\" }
        timeout     { puts \"OBSERVED: canary NOT readable after restart\" ; exit 1 }
    }
    $vm_clean_shutdown_fragment
")")
echo "$out2"

echo "$out2" | grep -q "BAD TRAP" \
    && fail "second boot panicked — persisted image is not bootable"
echo "$out2" | grep -q "OBSERVED: canary read back after restart" \
    || fail "canary did not survive the restart"

echo "PASS: test-disk-writes-persist"
