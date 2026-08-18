#!/usr/bin/env bash
# Inspect the guest filesystem from the host WITHOUT booting the VM.
#
#   tools/peek.sh                      interactive: mount and drop to a shell
#   tools/peek.sh 'ls /opt/csw/bin'    run a command against the mounted tree
#   tools/peek.sh -s @clean-2gb 'ls $MNT/etc'      peek at a snapshot instead
#
# Clones the image DATASET, mounts the clone's disk file read-only, runs your
# command, then destroys the clone. Seconds instead of a ~60s boot.
#
# WHY A CLONE, not the live image: with MAP_SHARED (P2-012) the running guest's
# writes land in the page cache continuously, so reading the live file gives a
# torn, mid-transaction view. A clone is a stable point-in-time image and is
# unaffected by anything the VM does afterwards. It also works while the VM runs.
#
# P2-012 note: the disk is now a regular FILE inside a dataset, not a zvol, so
# there is no /dev/zvol path and no waiting for a device node to appear. mount(8)
# sets up the loop device implicitly and releases it on umount.
#
# Linux mounts Solaris UFS read-only reliably (ufstype=sun). Read-WRITE is not
# supported for this format, so this is strictly for inspection — to change the
# guest filesystem, push files through tools/exchange.sh instead.
#
# $MNT is exported to your command as the mountpoint.

set -euo pipefail

PROJ="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
source "$PROJ/tools/lib/image.sh"

POOL="${NIAGARA_POOL:-datapool}"
DATASET="${NIAGARA_DATASET:-niagara}"
SRC="${NIAGARA_IMAGES:-${POOL}/${DATASET}/images}"
SNAP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--snapshot) SNAP="$2"; shift 2 ;;
        *) break ;;
    esac
done

[[ $EUID -eq 0 ]] || { echo "ERROR: must run as root (zfs clone + mount)" >&2; exit 1; }

CLONE="${POOL}/${DATASET}/peek-$$"
MNT="/mnt/peek-$$"
ORIGIN=""

cleanup() {
    img_umount "$MNT" 2>/dev/null || true
    rmdir "$MNT" 2>/dev/null || true
    zfs destroy -r "$CLONE" 2>/dev/null || true
    [[ -n "$ORIGIN" && "$ORIGIN" == *"@peek-$$" ]] && \
        zfs destroy "$ORIGIN" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Clone from an explicit snapshot, or take a throwaway one of the live dataset.
if [[ -n "$SNAP" ]]; then
    ORIGIN="${SRC}${SNAP}"
    zfs list -t snapshot "$ORIGIN" >/dev/null 2>&1 \
        || { echo "ERROR: no such snapshot: $ORIGIN" >&2; exit 1; }
else
    ORIGIN="${SRC}@peek-$$"
    zfs snapshot "$ORIGIN"
fi

zfs clone "$ORIGIN" "$CLONE"

IMG=$(img_require "$CLONE") || exit 1

# s0 (the root UFS) starts at block 0 of the disk, so no offset is needed here.
# Slices at a non-zero start use img_mount_slice from tools/lib/image.sh.
mkdir -p "$MNT"
mount -t ufs -o ro,loop,ufstype=sun "$IMG" "$MNT"
export MNT

if [[ $# -eq 0 ]]; then
    echo "mounted $ORIGIN read-only at $MNT  (exit the shell to clean up)"
    ${SHELL:-/bin/bash}
else
    ( cd "$MNT" && eval "$@" )
fi
