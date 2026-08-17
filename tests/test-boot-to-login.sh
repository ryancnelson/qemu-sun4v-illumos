#!/usr/bin/env bash
# TEST: Machine boots to a login prompt.
#
# Gilfoyle standard: PASS only when the observed output contains the
# exact login prompt string. No inference.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TESTS_DIR/lib/lock.sh"
source "$TESTS_DIR/lib/zvol.sh"
source "$TESTS_DIR/lib/vm.sh"

ZVOL="vms/test-boot-$$"

cleanup() {
    lock_release "$ZVOL" 2>/dev/null || true
    zvol_destroy "$ZVOL" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

zvol_clone "$ZVOL"
lock_acquire "$ZVOL"

output=$(vm_run "$ZVOL" "$(vm_boot_to_login_script '
    puts "OBSERVED: login prompt reached"
    '"$vm_quit_fragment"'
')")

echo "$output"

if echo "$output" | grep -q "OBSERVED: login prompt reached"; then
    echo "PASS: test-boot-to-login"
    exit 0
else
    reason=$(echo "$output" | grep "OBSERVED:" | tail -1)
    echo "FAIL: test-boot-to-login — $reason"
    exit 1
fi
