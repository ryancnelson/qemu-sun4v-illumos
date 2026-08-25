#!/usr/bin/env bash
# Disk-image helpers for niagara QEMU tests.
#
# Replaces tests/lib/zvol.sh. Renamed rather than adapted because after P2-012
# the disk is a FILE inside a ZFS dataset, not a zvol, and leaving the functions
# called zvol_* would have been a standing lie about what they touch.
#
# LAYOUT
#   datapool/niagara/images                  — the dataset holding the disk
#   datapool/niagara/images/primary.img      — the disk itself
#   datapool/niagara/images@baseline         — test clone source   <-- DEFAULT
#   datapool/niagara/test-<n>-<pid>          — ephemeral test clone (a DATASET)
#
# A clone is a dataset clone, so the image file comes with it:
#   zfs clone datapool/niagara/images@baseline datapool/niagara/test-boot-123
#     -> /datapool/niagara/test-boot-123/primary.img
#
# WHY A FILE: memory_region_init_ram_from_file() needs a regular file for
# MAP_SHARED. Block devices do not support MAP_SHARED writeback reliably. The ZFS
# safety net is unaffected — datasets snapshot and clone exactly as zvols do.
#
# NIAGARA_SNAP selects the clone source. It defaults to @baseline, which carries
# the working toolchain, PPP and telnet. The old @clean/@clean-2gb snapshots are
# on the pre-migration ZVOL at vms/primary and are not usable here.
#
# Usage:
#   source tests/lib/disk.sh
#   disk_clone   test-boot-$$      # clone $CLEAN_SNAP -> test dataset
#   disk_path    test-boot-$$      # -> /datapool/niagara/test-boot-$$/primary.img
#   disk_destroy test-boot-1234
#   disk_prune_snaps               # reap accumulated throwaway snapshots

set -euo pipefail

_DISK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DISK_LIB_DIR/../../tools/lib/image.sh"

POOL="${NIAGARA_POOL:-datapool}"
DATASET="${NIAGARA_DATASET:-niagara}"
IMAGES="${NIAGARA_IMAGES:-$POOL/$DATASET/images}"
CLEAN_SNAP="${NIAGARA_SNAP:-images@baseline}"

_disk_full() {
    echo "$POOL/$DATASET/$1"
}

# disk_path <name> -> path of the image file inside that dataset
disk_path() {
    img_path "$(_disk_full "$1")"
}

# disk_exists <name>
# Deliberately accepts EITHER type. It used to test only -t filesystem, which
# made disk_destroy silently return 0 for a zvol clone and leak it -- observed
# when a test pinned a pre-migration zvol snapshot and left
# datapool/niagara/test-toolchain-3641222 behind with no warning at all.
# A cleanup path must not go quiet just because the thing is the wrong type.
disk_exists() {
    zfs list "$(_disk_full "$1")" &>/dev/null
}

# disk_is_volume <name> -> 0 if it is a zvol (i.e. a pre-P2-012 leftover)
disk_is_volume() {
    [[ "$(zfs get -H -o value type "$(_disk_full "$1")" 2>/dev/null)" == "volume" ]]
}

# disk_snap_exists <name@snap>
disk_snap_exists() {
    zfs list -t snapshot "$(_disk_full "$1")" &>/dev/null
}

# _disk_detach_loops <image-path>
# Any loop device still attached to the image keeps the file open, which makes
# `zfs destroy` fail — and it fails SILENTLY enough that a caller can believe the
# dataset is gone while it still holds hundreds of MB. Measured: an orphan loop
# left /datapool/niagara/xtest alive at 585M after a destroy that appeared to
# succeed. Always detach before destroying.
_disk_detach_loops() {
    local img="$1" lo
    [[ -n "$img" ]] || return 0
    for lo in $(losetup -j "$img" -O NAME --noheadings 2>/dev/null); do
        findmnt -S "$lo" >/dev/null 2>&1 && umount "$lo" 2>/dev/null || true
        losetup -d "$lo" 2>/dev/null || true
    done
}

# disk_clone <name>
# Clones $CLEAN_SNAP to the given name and waits for the image file to appear.
# No udev wait: a dataset clone is mounted by ZFS, there is no block device.
disk_clone() {
    local name="$1" full src i=0 p
    full=$(_disk_full "$name")
    src=$(_disk_full "$CLEAN_SNAP")

    if ! disk_snap_exists "$CLEAN_SNAP"; then
        echo "ERROR: clone source $src does not exist." >&2
        echo "       Set NIAGARA_SNAP, or run: sudo bash tests/zfs-setup.sh" >&2
        return 1
    fi
    if disk_exists "$name"; then
        echo "ERROR: $full already exists; refusing to clobber it" >&2
        return 1
    fi

    zfs clone "$src" "$full"

    # The mount is synchronous in practice, but assert it rather than assume.
    while (( i++ < 40 )); do
        p=$(img_path "$full" 2>/dev/null) || true
        [[ -n "${p:-}" && -f "$p" ]] && { printf '%s\n' "$p"; return 0; }
        sleep 0.2
    done
    echo "ERROR: image never appeared in $full" >&2
    return 1
}

# disk_destroy <name>
# Detaches loops first, then destroys recursively.
#
# -r is required for a different reason than it used to be: QEMU's atexit
# writeback used to mint a @pre-exit-<pid> snapshot on the disk it opened, so a
# plain destroy failed with "has children". P2-012 deleted that writeback, but
# tests may still snapshot their own clones, so -r stays.
disk_destroy() {
    local name="$1" full p
    full=$(_disk_full "$name")
    disk_exists "$name" || return 0

    if disk_is_volume "$name"; then
        echo "NOTE: $full is a ZVOL (pre-P2-012 leftover); destroying anyway" >&2
    else
        p=$(img_path "$full" 2>/dev/null) || true
        _disk_detach_loops "${p:-}"
    fi

    if ! zfs destroy -r "$full" 2>/dev/null; then
        echo "WARNING: could not destroy $full — still open?" >&2
        losetup -a 2>/dev/null | grep -F "${p:-__none__}" >&2 || true
        return 1
    fi
}

# disk_prune_snaps [keep]
# Throwaway snapshots accumulate from interrupted runs and block plain rollbacks.
disk_prune_snaps() {
    local keep="${1:-0}" s n=0
    while read -r s; do
        [[ -n "$s" ]] || continue
        (( n++ <= keep )) && continue
        zfs destroy "$s" 2>/dev/null && echo "pruned $s"
    done < <(zfs list -H -t snapshot -o name -r "$POOL/$DATASET" 2>/dev/null \
             | grep -E -- '@(pre-exit-|peek-|tmp-)' | sort -r || true)
}
