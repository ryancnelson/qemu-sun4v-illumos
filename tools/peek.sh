#!/usr/bin/env bash
# Inspect the guest filesystem from the host WITHOUT booting the VM.
#
#   tools/peek.sh                      interactive: mount and drop to a shell
#   tools/peek.sh 'ls /opt/csw/bin'    run a command against the mounted tree
#   tools/peek.sh -s @clean-2gb 'df -h /mnt/...'   peek at a snapshot instead
#
# Clones the zvol, mounts the clone read-only, runs your command, then destroys
# the clone. Takes seconds instead of a ~60s boot.
#
# WHY A CLONE, not the zvol directly: QEMU's atexit writeback rewrites the
# whole zvol on exit, so reading the live device races with that and can return
# a torn view. A clone is a stable point-in-time image and is unaffected by
# anything the VM does afterwards. It also works while the VM is running.
#
# Linux mounts Solaris UFS read-only reliably (ufstype=sun). Read-WRITE is not
# supported for this format, so this is strictly for inspection — to change
# the guest filesystem, push a tar through tools/exchange.sh instead.
#
# $MNT is exported to your command as the mountpoint.

set -euo pipefail

POOL="${NIAGARA_POOL:-datapool}"
DATASET="${NIAGARA_DATASET:-niagara}"
SRC="${POOL}/${DATASET}/vms/primary"
SNAP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--snapshot) SNAP="$2"; shift 2 ;;
        *) break ;;
    esac
done

[[ $EUID -eq 0 ]] || { echo "ERROR: must run as root (zfs clone + mount)" >&2; exit 1; }

CLONE="${POOL}/${DATASET}/vms/peek-$$"
MNT="/mnt/peek-$$"
DEV="/dev/zvol/$CLONE"

cleanup() {
    mountpoint -q "$MNT" 2>/dev/null && umount "$MNT"
    rmdir "$MNT" 2>/dev/null || true
    zfs destroy -r "$CLONE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Clone from an explicit snapshot, or take a throwaway one of the live zvol.
if [[ -n "$SNAP" ]]; then
    ORIGIN="${SRC}${SNAP}"
    zfs list -t snapshot "$ORIGIN" >/dev/null 2>&1 \
        || { echo "ERROR: no such snapshot: $ORIGIN" >&2; exit 1; }
else
    ORIGIN="${SRC}@peek-$$"
    zfs snapshot "$ORIGIN"
    trap 'cleanup; zfs destroy "'"$ORIGIN"'" 2>/dev/null || true' EXIT INT TERM
fi

zfs clone "$ORIGIN" "$CLONE"
for _ in $(seq 40); do [[ -b "$DEV" ]] && break; sleep 0.2; done
[[ -b "$DEV" ]] || { echo "ERROR: $DEV never appeared" >&2; exit 1; }

mkdir -p "$MNT"
mount -t ufs -o ro,ufstype=sun "$DEV" "$MNT"
export MNT

if [[ $# -eq 0 ]]; then
    echo "mounted $ORIGIN read-only at $MNT  (exit the shell to clean up)"
    ${SHELL:-/bin/bash}
else
    ( cd "$MNT" && eval "$@" )
fi
