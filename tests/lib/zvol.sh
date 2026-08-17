#!/usr/bin/env bash
# ZFS zvol helpers for niagara QEMU tests.
#
# Dataset layout:
#   datapool/niagara/vms/primary            — daily driver zvol
#   datapool/niagara/vms/primary@clean      — pristine 512MB original image
#   datapool/niagara/vms/primary@clean-2gb  — 1.9GB grown UFS, 1.6GB free  <-- DEFAULT
#   datapool/niagara/vms/test-<n>-<pid>     — ephemeral test clone
#
# NIAGARA_SNAP selects the clone source. It defaults to @clean-2gb because
# that is the working baseline; @clean is the 512MB original and is kept only
# as a last-resort fallback.
#
# NOTE ON volsize: `zfs rollback` reverts volsize to whatever it was when the
# snapshot was taken, so a rollback to @clean-2gb yields a 2G volume even if
# primary was grown to 3G. `zfs clone` has the same behaviour, which is what
# we want for tests — a clone of @clean-2gb is a 2G volume with a 1.9GB UFS.
#
# Usage:
#   source tests/lib/zvol.sh
#   zvol_path  vms/primary          # -> /dev/zvol/datapool/niagara/vms/primary
#   zvol_clone vms/test-boot-$$     # clone $CLEAN_SNAP -> test zvol
#   zvol_destroy vms/test-boot-1234
#   zvol_prune_pre_exit             # reap accumulated @pre-exit-<pid> snapshots

set -euo pipefail

POOL="${NIAGARA_POOL:-datapool}"
DATASET="${NIAGARA_DATASET:-niagara}"
CLEAN_SNAP="${NIAGARA_SNAP:-vms/primary@clean-2gb}"

_zvol_full() {
    echo "$POOL/$DATASET/$1"
}

# zvol_path <name>
zvol_path() {
    echo "/dev/zvol/$POOL/$DATASET/$1"
}

# zvol_exists <name>
zvol_exists() {
    zfs list -t volume "$(_zvol_full "$1")" &>/dev/null
}

# zvol_snap_exists <name@snap>
zvol_snap_exists() {
    zfs list -t snapshot "$(_zvol_full "$1")" &>/dev/null
}

# zvol_clone <name>
# Clones $CLEAN_SNAP to the given name, waits for the udev block device.
zvol_clone() {
    local name="$1" full src dev i=0
    full=$(_zvol_full "$name")
    src=$(_zvol_full "$CLEAN_SNAP")

    if ! zvol_snap_exists "$CLEAN_SNAP"; then
        echo "ERROR: clone source $src does not exist." >&2
        echo "       Set NIAGARA_SNAP, or run: sudo bash tests/zfs-setup.sh" >&2
        return 1
    fi
    if zvol_exists "$name"; then
        echo "ERROR: zvol $full already exists" >&2
        return 1
    fi

    zfs clone "$src" "$full"

    dev=$(zvol_path "$name")
    while [[ ! -b "$dev" ]] && (( i < 30 )); do
        sleep 0.2
        (( i++ )) || true
    done
    if [[ ! -b "$dev" ]]; then
        echo "ERROR: block device $dev did not appear after clone" >&2
        return 1
    fi
}

# zvol_destroy <name>
# Destroys a test zvol and any snapshots under it. Refuses to touch primary.
#
# -r is REQUIRED: QEMU's atexit writeback takes a @pre-exit-<pid> snapshot on
# whatever zvol it opened, which for a test is the clone itself. A plain
# `zfs destroy` then fails with "volume has children", forever. That was the
# real leak mechanism — 15 orphans at ~220MB each were found on disk, and a
# retry loop could never have helped because the failure is permanent.
#
# Retries anyway: the device can also be transiently busy while QEMU tears
# down or udev releases it. If it still fails, say so LOUDLY rather than
# letting callers swallow it with 2>/dev/null.
zvol_destroy() {
    local name="$1" full i
    case "$name" in
        vms/primary|primary|*@*)
            echo "ERROR: refusing to destroy '$name'" >&2
            return 1
            ;;
        vms/test-*) ;;   # only test clones may be destroyed
        *)
            echo "ERROR: refusing to destroy non-test dataset '$name'" >&2
            return 1
            ;;
    esac

    full=$(_zvol_full "$name")
    zvol_exists "$name" || return 0   # idempotent

    for i in 1 2 3 4 5 6 7 8 9 10; do
        if zfs destroy -r "$full" 2>/dev/null; then
            return 0
        fi
        sleep 0.5
    done

    echo "" >&2
    echo "!!! LEAKED ZVOL: $full" >&2
    echo "!!! zfs destroy -r failed after 10 attempts" >&2
    echo "!!! Reclaim with: sudo zfs destroy -r $full" >&2
    echo "" >&2
    return 1
}

# zvol_prune_pre_exit [keep]
# QEMU's atexit writeback takes a @pre-exit-<pid> snapshot on `primary` before
# every write-back, as a rollback safety net. Left alone they accumulate
# forever and make a plain `zfs rollback` fail ("more recent snapshots
# exist"). Keep the newest `keep` (default 2), destroy the rest.
zvol_prune_pre_exit() {
    local keep="${1:-2}" primary snaps n
    primary=$(_zvol_full vms/primary)
    mapfile -t snaps < <(zfs list -H -t snapshot -o name -s creation -r "$primary" 2>/dev/null \
                         | grep -- '@pre-exit-' || true)
    n=${#snaps[@]}
    (( n > keep )) || return 0
    for ((i = 0; i < n - keep; i++)); do
        echo "pruning stale snapshot: ${snaps[i]}" >&2
        zfs destroy "${snaps[i]}" 2>/dev/null || true
    done
}
