#!/usr/bin/env bash
# Run all tests and report results.
# Usage: ./tests/run-all.sh [QEMU_BIN=/path/to/custom/qemu-system-sparc64]
#
# Override QEMU_BIN to test a patched build:
#   QEMU_BIN=./qemu/build/qemu-system-sparc64 ./tests/run-all.sh

set -euo pipefail

export QEMU_BIN="${QEMU_BIN:-qemu-system-sparc64}"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"

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
        ((PASS++)) || true
    else
        RESULTS+=("FAIL  $name")
        ((FAIL++)) || true
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
