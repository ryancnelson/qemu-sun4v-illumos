#!/usr/bin/env bash
# One-time ZFS provisioning for niagara QEMU tests.
# Idempotent — safe to run multiple times.
#
# Creates:
#   datapool/niagara/            ZFS filesystem
#   datapool/niagara/base        ZFS filesystem (read-only Oracle assets)
#   datapool/niagara/vms         ZFS filesystem (container)
#   datapool/niagara/vms/primary 512MB zvol (Solaris 10 base install)
#   datapool/niagara/vms/primary@clean  snapshot — clone source for tests
#
# Requires: root (zfs commands), disk.s10hw2 available at SRC_IMAGE.

set -euo pipefail

POOL="${NIAGARA_POOL:-datapool}"
DATASET="${NIAGARA_DATASET:-niagara}"
BASE="${POOL}/${DATASET}"
SRC_IMAGE="${SRC_IMAGE:-$HOME/vms/opensparc/S10image/disk.s10hw2}"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root" >&2
    exit 1
fi

if [[ ! -f "$SRC_IMAGE" ]]; then
    echo "ERROR: source image not found: $SRC_IMAGE" >&2
    exit 1
fi

IMAGE_SIZE=$(stat -c %s "$SRC_IMAGE")
echo "Source image: $SRC_IMAGE ($IMAGE_SIZE bytes)"

# Helper: create ZFS filesystem if it doesn't exist
ensure_fs() {
    local ds="$1"
    if zfs list "$ds" &>/dev/null; then
        echo "  exists: $ds"
    else
        echo "  creating: $ds"
        zfs create "$ds"
    fi
}

echo ""
echo "=== Provisioning $BASE ==="

ensure_fs "$BASE"
ensure_fs "$BASE/base"
ensure_fs "$BASE/vms"

# Create primary zvol from image size if it doesn't exist
PRIMARY="$BASE/vms/primary"
CLEAN_SNAP="$PRIMARY@clean"

if zfs list -t volume "$PRIMARY" &>/dev/null; then
    echo "  exists: $PRIMARY"
else
    echo "  creating zvol: $PRIMARY (${IMAGE_SIZE} bytes)"
    # Round up to nearest MB for ZFS
    SIZE_MB=$(( (IMAGE_SIZE + 1048575) / 1048576 ))
    zfs create -V "${SIZE_MB}M" "$PRIMARY"

    # Wait for block device
    DEV="/dev/zvol/$PRIMARY"
    echo "  waiting for $DEV ..."
    for i in $(seq 1 30); do
        [[ -b "$DEV" ]] && break
        sleep 0.5
    done
    [[ -b "$DEV" ]] || { echo "ERROR: $DEV never appeared"; exit 1; }

    echo "  copying image to $DEV ..."
    dd if="$SRC_IMAGE" of="$DEV" bs=1M status=progress conv=fsync
    echo "  copy complete"
fi

# Take @clean snapshot if it doesn't exist
if zfs list -t snapshot "$CLEAN_SNAP" &>/dev/null; then
    echo "  exists: $CLEAN_SNAP"
else
    echo "  snapshotting: $CLEAN_SNAP"
    zfs snapshot "$CLEAN_SNAP"
fi

# Copy firmware ROMs to base dataset if not already there
ROMS_DEST="$(zfs get -H -o value mountpoint "$BASE/base")"
SRC_ROMS="$(dirname "$SRC_IMAGE")"

echo ""
echo "=== Syncing firmware ROMs to $ROMS_DEST ==="
for f in "$SRC_ROMS"/1*.bin "$SRC_ROMS"/openboot.bin "$SRC_ROMS"/q.bin \
          "$SRC_ROMS"/reset.bin "$SRC_ROMS"/nvram1 "$SRC_ROMS"/netcons; do
    [[ -f "$f" ]] || continue
    dest="$ROMS_DEST/$(basename "$f")"
    if [[ ! -f "$dest" ]]; then
        echo "  copying: $(basename "$f")"
        cp "$f" "$dest"
    else
        echo "  exists: $(basename "$f")"
    fi
done

echo ""
echo "=== Done ==="
echo ""
zfs list -r "$BASE"
echo ""
echo "Primary zvol:  /dev/zvol/$PRIMARY"
echo "Clean snap:    $CLEAN_SNAP"
echo "Firmware ROMs: $ROMS_DEST"
echo ""
echo "To boot the primary VM:"
echo "  sudo ~/vms/opensparc/run-solaris.sh"
echo ""
echo "To run tests:"
echo "  sudo bash tests/run-all.sh"
