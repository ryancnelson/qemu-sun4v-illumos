# Shared image-location contract (P2-012).
#
# Source this; it defines no state and takes no action.
#
# WHY THIS FILE EXISTS: before P2-012 every tool built the disk path itself as
# "/dev/zvol/$dataset". After the move to MAP_SHARED the disk is a FILE inside a
# ZFS dataset, and having six tools each reconstruct that path independently is
# how a literal 2668003328 -- wrong by 832 blocks -- ended up hardcoded in
# niagara.c. One resolver, used everywhere.
#
# LAYOUT
#   dataset  datapool/niagara/images            mounted /datapool/niagara/images
#   disk     /datapool/niagara/images/primary.img
#
#   A clone is a dataset clone, so the file comes along:
#     zfs clone datapool/niagara/images@snap datapool/niagara/test-x
#       -> /datapool/niagara/test-x/primary.img
#
# WHY A REGULAR FILE AND NOT A ZVOL: memory_region_init_ram_from_file() needs a
# regular file. Block devices do not support MAP_SHARED writeback reliably, so a
# zvol-backed vdisk would take guest writes into pages that never reach disk.
# niagara.c checks S_ISREG and refuses rather than failing silently.
#
# The ZFS safety net is unchanged by this: datasets snapshot and clone exactly as
# zvols do, instantly and with no extra space.

IMAGE_NAME="${IMAGE_NAME:-primary.img}"

# img_dataset_exists <dataset>  -> 0 if it is a ZFS filesystem
img_dataset_exists() {
    zfs list -H -t filesystem "$1" >/dev/null 2>&1
}

# img_mountpoint <dataset> -> its mountpoint, or fail
# Asks ZFS rather than assuming /$dataset, so altroot and inherited mountpoints
# both work.
img_mountpoint() {
    local ds="$1" mp
    mp=$(zfs get -H -o value mountpoint "$ds" 2>/dev/null) || return 1
    [[ -n "$mp" && "$mp" != "-" && "$mp" != "none" && "$mp" != "legacy" ]] || {
        echo "dataset $ds has no usable mountpoint ($mp)" >&2; return 1; }
    printf '%s\n' "$mp"
}

# img_path <dataset> -> absolute path of the disk image inside it
img_path() {
    local mp; mp=$(img_mountpoint "$1") || return 1
    printf '%s/%s\n' "$mp" "$IMAGE_NAME"
}

# img_require <dataset> -> echo the path, or fail with a useful message
img_require() {
    local ds="$1" p
    img_dataset_exists "$ds" || {
        if zfs list -H -t volume "$ds" >/dev/null 2>&1; then
            echo "ERROR: $ds is a ZVOL. P2-012 moved the disk to a file in a" >&2
            echo "       dataset because MAP_SHARED needs a regular file." >&2
            echo "       Convert:  zfs create -o recordsize=8K <ds> &&" >&2
            echo "                 dd if=/dev/zvol/$ds of=<mnt>/$IMAGE_NAME bs=4M" >&2
        else
            echo "ERROR: no such ZFS filesystem: $ds" >&2
        fi
        return 1
    }
    p=$(img_path "$ds") || return 1
    [[ -f "$p" ]] || { echo "ERROR: no image at $p" >&2; return 1; }
    printf '%s\n' "$p"
}

# img_mount_slice <image> <start-block> <mountpoint> [fstype] [extra-opts]
#   Mounts a filesystem living at a block offset INSIDE the image.
#
#   No losetup needed: mount(8) creates the loop device implicitly for a file,
#   honours offset=, and releases the device on umount. Verified read-write.
#   This is what replaced exchange.sh's _fat_loop/_fat_detach pair.
img_mount_slice() {
    local img="$1" startblk="$2" mnt="$3" fstype="${4:-vfat}" extra="${5:-}"
    mkdir -p "$mnt"
    mount -t "$fstype" -o "loop,offset=$(( startblk * 512 ))${extra:+,$extra}" \
          "$img" "$mnt"
}

# img_umount <mountpoint>
img_umount() {
    local mnt="$1"
    mountpoint -q "$mnt" || return 0
    sync
    umount "$mnt"
}
