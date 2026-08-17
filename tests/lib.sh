#!/usr/bin/env bash
# Shared test infrastructure.
# Gilfoyle rule: every PASS/FAIL traces to observed data, never assumption.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VMS_DIR="$HOME/vms/opensparc"
S10DIR="$VMS_DIR/S10image"
BASE_IMAGE="$S10DIR/disk.s10hw2"

# Each test gets its own throwaway raw image so tests don't interfere.
TEST_IMAGE_DIR="/tmp/niagara-tests"
mkdir -p "$TEST_IMAGE_DIR"

QEMU="${QEMU_BIN:-qemu-system-sparc64}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-90}"   # seconds to wait for login prompt
WRITE_TIMEOUT="${WRITE_TIMEOUT:-30}" # seconds to wait for shell ops

PASS=0
FAIL=1

log()  { echo "[$(date +%T)] $*" >&2; }
pass() { echo "PASS: $1"; exit $PASS; }
fail() { echo "FAIL: $1"; echo "  evidence: $2"; exit $FAIL; }

# Make a fresh throwaway raw copy of the base image for this test run.
# Stamped with the test name so concurrent runs don't collide.
make_test_image() {
    local name="$1"
    local img="$TEST_IMAGE_DIR/${name}.raw"
    if [[ ! -f "$img" ]]; then
        log "Cloning base image for test '$name' ..."
        cp "$BASE_IMAGE" "$img"
    fi
    echo "$img"
}

cleanup_test_image() {
    local name="$1"
    rm -f "$TEST_IMAGE_DIR/${name}.raw"
}

# Run a sequence of expect interactions against QEMU.
# Usage: run_expect <image> <expect_script_body>
# The expect script body has $QEMU, $S10DIR, $IMAGE already set.
run_expect() {
    local image="$1"
    local script="$2"
    IMAGE="$image" QEMU="$QEMU" S10DIR="$S10DIR" \
        expect -c "
set timeout $BOOT_TIMEOUT
$script
" 2>&1
}
