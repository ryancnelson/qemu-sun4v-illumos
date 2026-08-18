#!/usr/bin/env bash
# TEST: Machine boots to a login prompt.
#
# Gilfoyle standard: PASS only when the observed output contains the
# exact login prompt string. No inference.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$TESTS_DIR/lib/lock.sh"
source "$TESTS_DIR/lib/disk.sh"
source "$TESTS_DIR/lib/vm.sh"

DISK="test-boot-$$"

cleanup() {
    lock_release "$DISK" 2>/dev/null || true
    disk_destroy "$DISK" || true      # NOT 2>/dev/null: let leak warnings through
}
trap cleanup EXIT INT TERM

disk_clone "$DISK"
lock_acquire "$DISK"

output=$(vm_run "$DISK" "$(vm_boot_to_login_script '
    puts "OBSERVED: login prompt reached"
    send "root\r"
    expect "# "
    puts "OBSERVED: root shell reached"
    '"$vm_clean_shutdown_fragment"'
')") || true

echo "$output"

if echo "$output" | grep -q "OBSERVED: login prompt reached"; then
    echo "PASS: test-boot-to-login"
    exit 0
else
    reason=$(echo "$output" | grep "OBSERVED:" | tail -1)
    echo "FAIL: test-boot-to-login — $reason"
    exit 1
fi
