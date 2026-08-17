#!/usr/bin/env bash
# Run all tests and report results.
#
# Usage:
#   sudo bash tests/run-all.sh
#   sudo QEMU_BIN=./qemu/build/qemu-system-sparc64 bash tests/run-all.sh
#   sudo NIAGARA_SNAP=vms/primary@clean bash tests/run-all.sh   # 512MB original
#
# Requires root: zfs clone/destroy and zvol block device access.
#
# Each VM test clones its own throwaway zvol from $CLEAN_SNAP and destroys it
# on exit, so tests cannot corrupt each other or the daily-driver `primary`.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root (zfs clone/destroy requires it)" >&2
    exit 1
fi

export QEMU_BIN="${QEMU_BIN:-qemu-system-sparc64}"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$TESTS_DIR/lib/zvol.sh"

# Preflight: the clone source must exist. Default is @clean-2gb (1.9GB UFS);
# @clean is the 512MB original.
if ! zvol_snap_exists "$CLEAN_SNAP"; then
    echo "ERROR: clone source $POOL/$DATASET/$CLEAN_SNAP does not exist." >&2
    echo "       Available snapshots:" >&2
    zfs list -H -t snapshot -o name -r "$POOL/$DATASET/vms" 2>/dev/null | sed 's/^/         /' >&2
    echo "       Run: sudo bash tests/zfs-setup.sh   (or set NIAGARA_SNAP)" >&2
    exit 1
fi
echo "clone source: $POOL/$DATASET/$CLEAN_SNAP"

# The QEMU atexit writeback leaves a @pre-exit-<pid> snapshot behind on every
# run. Left alone they accumulate and make a plain `zfs rollback` fail.
zvol_prune_pre_exit 2

# Warn about leaked clones from previous runs rather than silently ignoring.
leaked=$(zfs list -H -o name -r "$POOL/$DATASET/vms" 2>/dev/null | grep -c '/test-' || true)
if (( leaked > 0 )); then
    echo "WARNING: $leaked leaked test clone(s) from previous runs:" >&2
    zfs list -H -o name,refer -r "$POOL/$DATASET/vms" | grep '/test-' | sed 's/^/         /' >&2
    echo "         Reclaim: sudo bash tests/reap-orphans.sh" >&2
fi

PASS=0
FAIL=0
RESULTS=()

run_test() {
    local script="$1" name
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

[[ $FAIL -eq 0 ]]
