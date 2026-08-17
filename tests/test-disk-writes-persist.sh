#!/usr/bin/env bash
# TEST: A file written inside the guest survives QEMU exit.
#
# Method (Gilfoyle standard):
#   1. Boot, log in as root.
#   2. Write a unique canary string to a file.
#   3. sync twice.
#   4. Exit QEMU cleanly via monitor quit (ensures flush).
#   5. Search the raw zvol block device on the HOST for the canary.
#
# PASS = canary found in block device.
# FAIL = canary absent. Write was lost.
#
# Currently FAILS on stock QEMU 8.2.2 (vdisk is anonymous RAM).
# Should PASS after patches/0001-niagara-vdisk-ram-shared.patch.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TESTS_DIR/lib/lock.sh"
source "$TESTS_DIR/lib/zvol.sh"
source "$TESTS_DIR/lib/vm.sh"

ZVOL="vms/test-write-$$"
CANARY="NIAGARA_WRITE_TEST_$$_$(date +%s)"

cleanup() {
    lock_release "$ZVOL" 2>/dev/null || true
    zvol_destroy "$ZVOL" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "Canary: $CANARY"

zvol_clone "$ZVOL"
lock_acquire "$ZVOL"

vm_run "$ZVOL" "$(vm_boot_to_login_script "
    send \"root\r\"
    expect \"#\"
    set timeout 20
    send \"echo $CANARY > /tmp/canary.txt && sync && sync && echo WRITE_DONE\r\"
    expect {
        \"WRITE_DONE\" {
            puts \"OBSERVED: guest confirmed write and sync\"
        }
        timeout {
            puts \"OBSERVED: timed out waiting for write\"
            exit 1
        }
    }
    $vm_quit_fragment
")"

# Release lock before inspecting — QEMU is gone, no risk of corruption
lock_release "$ZVOL"

DEV=$(zvol_path "$ZVOL")
echo "Searching $DEV for canary ..."

if strings "$DEV" | grep -qF "$CANARY"; then
    echo "OBSERVED: canary found in block device"
    echo "PASS: test-disk-writes-persist"
    exit 0
else
    echo "OBSERVED: canary NOT found in block device — write was lost"
    echo "FAIL: test-disk-writes-persist"
    exit 1
fi
