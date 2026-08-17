#!/usr/bin/env bash
# TEST: OBP is functional after a guest-initiated reboot.
#
# Method:
#   1. Boot to Solaris, log in.
#   2. Run "reboot" inside the guest.
#   3. Wait for OBP "ok" prompt.
#   4. Send "devalias" — a benign OBP command.
#   5. PASS = output contains "disk" (always present on clean OBP).
#   6. FAIL = OBP traps, hangs, or devalias produces no useful output.
#
# Currently FAILS. After reboot, OBP traps with:
#   ERROR: Last Trap: Fast Data Access MMU Miss
# Root cause: no machine_reset handler in QEMU Niagara machine.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TESTS_DIR/lib/lock.sh"
source "$TESTS_DIR/lib/zvol.sh"
source "$TESTS_DIR/lib/vm.sh"

ZVOL="vms/test-reboot-$$"

cleanup() {
    lock_release "$ZVOL" 2>/dev/null || true
    zvol_destroy "$ZVOL" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

zvol_clone "$ZVOL"
lock_acquire "$ZVOL"

output=$(vm_run "$ZVOL" "$(vm_boot_to_login_script '
    send "root\r"
    expect "#"
    set timeout 15
    send "reboot\r"

    expect {
        "ok" {
            puts "OBSERVED: OBP ok prompt returned after reboot"
        }
        timeout {
            puts "OBSERVED: timed out waiting for OBP after reboot"
            exit 1
        }
    }

    set timeout 10
    send "devalias\r"
    expect {
        "disk" {
            puts "OBSERVED: devalias responded — OBP intact"
            exit 0
        }
        "Last Trap" {
            puts "OBSERVED: OBP trapped after reboot — MMU state corrupted"
            exit 1
        }
        timeout {
            puts "OBSERVED: devalias timed out — OBP unresponsive"
            exit 1
        }
    }
')")

echo "$output"

if echo "$output" | grep -q "OBP intact"; then
    echo "PASS: test-reboot-obp-intact"
    exit 0
else
    reason=$(echo "$output" | grep "OBSERVED:" | tail -1)
    echo "FAIL: test-reboot-obp-intact — $reason"
    exit 1
fi
