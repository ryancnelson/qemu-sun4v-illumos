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
SRC_IMAGE="${SRC_IMAGE:-$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)/vms/opensparc/S10image/disk.s10hw2}"

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

# P2-012: the disk is a FILE in a dataset, not a zvol.
#
#   recordsize=8K  MAP_SHARED writeback is 4K-page granular. ZFS's 128K default
#                  turns each dirtied page into a 128K read-modify-write.
#   compression    the image is mostly empty; measured 585M on disk against
#                  2.5G apparent.
IMAGES="$BASE/images"
if zfs list -t filesystem "$IMAGES" &>/dev/null; then
    echo "  exists: $IMAGES"
else
    echo "  creating: $IMAGES (recordsize=8K, lz4)"
    zfs create -o recordsize=8K -o compression=lz4 "$IMAGES"
fi

IMG_MNT=$(zfs get -H -o value mountpoint "$IMAGES")
PRIMARY_IMG="$IMG_MNT/primary.img"
CLEAN_SNAP="$IMAGES@baseline"

if [[ -f "$PRIMARY_IMG" ]]; then
    echo "  exists: $PRIMARY_IMG ($(stat -c%s "$PRIMARY_IMG") bytes)"
else
    echo "  copying image -> $PRIMARY_IMG ..."
    dd if="$SRC_IMAGE" of="$PRIMARY_IMG" bs=4M status=progress conv=fsync
    echo "  copy complete"
fi

# The vdisk MUST be a regular file: memory_region_init_ram_from_file() needs one,
# and block devices do not support MAP_SHARED writeback reliably. Assert it here
# so a bad setup fails at provisioning rather than as silent data loss later.
[[ -f "$PRIMARY_IMG" ]] || { echo "ERROR: $PRIMARY_IMG is not a regular file"; exit 1; }

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
echo "Primary image: $PRIMARY_IMG"
echo "Clean snap:    $CLEAN_SNAP"
echo "Firmware ROMs: $ROMS_DEST"
echo ""
echo "To boot the primary VM:"
echo "  sudo ~/vms/opensparc/run-solaris.sh"
echo ""
echo "To run tests:"
echo "  sudo bash tests/run-all.sh"
