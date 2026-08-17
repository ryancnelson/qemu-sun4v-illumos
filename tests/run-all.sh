#!/usr/bin/env bash
# Run all tests and report results.
#
# Usage:
#   sudo bash tests/run-all.sh
#   sudo QEMU_BIN=./qemu/build/qemu-system-sparc64 bash tests/run-all.sh
#
# Requires root for zfs clone/destroy and zvol block device access.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root (zfs clone/destroy requires it)" >&2
    exit 1
fi

export QEMU_BIN="${QEMU_BIN:-qemu-system-sparc64}"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"

# Verify ZFS setup exists before running anything
source "$TESTS_DIR/lib/zvol.sh"
if ! zfs list "${POOL}/${DATASET}/vms/primary@clean" &>/dev/null; then
    echo "ERROR: ZFS not provisioned. Run: sudo bash tests/zfs-setup.sh" >&2
    exit 1
fi

PASS=0
FAIL=0
RESULTS=()

run_test() {
    local script="$1"
    local name
    name=$(basename "$script" .sh)
    echo ""
    echo "━━━ $name ━━━"
    if bash "$script"; then
        RESULTS+=("PASS  $name")
        (( PASS++ )) || true
    else
        RESULTS+=("FAIL  $name")
        (( FAIL++ )) || true
    fi
}

for t in "$TESTS_DIR"/test-*.sh; do
    run_test "$t"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf '%s\n' "${RESULTS[@]}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "passed: $PASS   failed: $FAIL"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
