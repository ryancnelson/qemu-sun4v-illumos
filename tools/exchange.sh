#!/usr/bin/env bash
# Bulk host <-> guest data channel using a VTOC slice.
#
#   RAW mode (one-shot, one-way):
#     tools/exchange.sh setup <zvol-dataset>
#     tools/exchange.sh push  <zvol-dataset> <file.tar>
#     tools/exchange.sh info
#
#   FAT mode (bidirectional, random access) — needs `setup` done once first:
#     tools/exchange.sh mkfs   <zvol-dataset>            # format slice 3
#     tools/exchange.sh put    <zvol-dataset> <file>...  # host -> slice
#     tools/exchange.sh get    <zvol-dataset> <name> [dest]   # slice -> host
#     tools/exchange.sh ls     <zvol-dataset>
#     tools/exchange.sh mount  <zvol-dataset>            # leaves it mounted
#     tools/exchange.sh umount <zvol-dataset>
#
#   RAW and FAT are mutually exclusive on the same slice: `push` overwrites the
#   FAT superblock and `mkfs` overwrites a pushed tar. Pick one per session.
#
#   NEVER run these while the VM is up. The whole vdisk lives in QEMU's RAM and
#   is written back wholesale on exit, so host-side edits made during a session
#   are silently overwritten.
#
# WHY THIS WORKS, with no new emulation:
#   q.bin serves the WHOLE vdisk (its size comes from VTOC slice 2's nblk, at
#   offset 0x1d0). Slices are just byte offsets into that same disk. So an
#   unused slice is reachable from the guest as /dev/rdsk/c0t0d0sN with no new
#   MD node, no new QEMU device, no q.bin change, and no new driver.
#
#   Contrast with the paths that do NOT work:
#     - second console (ttyb): qcn is a singleton driver, see qcn.c:347
#     - second -drive: invisible without an MD node, and q.bin only tracks one
#       disk (a single disk_pa in vdev_simdisk.s)
#
# LAYOUT (inside the served disk):
#   s0  block       0 .. 4194295   2048MB   root UFS
#   s3  block 4194304 .. 5242879    512MB   exchange (raw tar, or FAT32)
#   s2  block       0 .. 5242879   2560MB   whole disk -> q.bin's served size
#
# GUEST SIDE:
#   raw: dd if=/dev/rdsk/c0t0d0s3 bs=512 count=<blocks> 2>/dev/null | tar xvf -
#        (count is optional; tar stops at the end-of-archive marker either way,
#        but bounding it avoids reading 512MB of trailing garbage.)
#   FAT: mount -F pcfs /dev/dsk/c0t0d0s3:c /mnt
#        The ":c" suffix addresses the whole logical drive on the slice.
#
# Solaris /bin/sh is not POSIX: no $(...). Use backticks in payload scripts.

set -euo pipefail

PROJ="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
VTOC="$PROJ/tools/vtoc.py"

S0_NBLKS=4194296          # existing root slice, do not touch
EXCH_START=4194304        # 8 blocks of pad after s0 (cylinder alignment)
EXCH_NBLKS=1048576        # 512MB — the SLICE
DISK_NBLKS=$(( EXCH_START + EXCH_NBLKS ))   # 5242880 = 2560MB
VOLSIZE_MB=$(( DISK_NBLKS / 2048 ))         # 2560

# P1-008. The FAT filesystem is deliberately SMALLER than its slice so that the
# tail is outside any filesystem and safe to use as a raw shared region (P2-014's
# channel lives there). Formatting the full slice silently reclaims that tail and
# corrupts whatever is using it, with no error at the time.
#
# These two numbers MUST sum to EXCH_NBLKS. Keeping them as named constants, and
# asserting the sum below, is the fix: the old code hardcoded only the slice size
# and let mkfs default to "all of it".
FAT_NBLKS=1015808                                  # 496MB filesystem
SCRATCH_NBLKS=$(( EXCH_NBLKS - FAT_NBLKS ))        # 32768 blocks = 16MB
SCRATCH_START=$(( EXCH_START + FAT_NBLKS ))        # 5210112, absolute
SCRATCH_BYTE=$(( SCRATCH_START * 512 ))            # 2667577344, absolute

(( FAT_NBLKS + SCRATCH_NBLKS == EXCH_NBLKS )) || {
    echo "BUG: FAT_NBLKS + SCRATCH_NBLKS != EXCH_NBLKS" >&2; exit 1; }

# Print the header comment block, however long it grows. The old form was
# `sed -n '2,40p'`, which silently truncated mid-sentence as soon as the header
# gained the FAT subcommands.
usage() { sed -e '1d' -e '/^#/!Q' "$0"; exit 1; }

cmd_info() {
    cat <<EOF
exchange slice geometry
  s0       blocks 0..$(( S0_NBLKS - 1 ))  (root UFS, untouched)
  s3       blocks $EXCH_START..$(( DISK_NBLKS - 1 ))  = $(( EXCH_NBLKS / 2048 ))MB  (the SLICE)
  s2       blocks 0..$(( DISK_NBLKS - 1 ))  = ${VOLSIZE_MB}MB  (q.bin served size)
  host byte offset of s3 = $(( EXCH_START * 512 ))
  required zvol volsize  = ${VOLSIZE_MB}M

s3 is split: the FAT filesystem does NOT fill it
  FAT      blocks $EXCH_START..$(( SCRATCH_START - 1 ))  = $(( FAT_NBLKS / 2048 ))MB
  scratch  blocks $SCRATCH_START..$(( DISK_NBLKS - 1 ))  = $(( SCRATCH_NBLKS / 2048 ))MB  (raw, no filesystem)
  scratch host byte offset = $SCRATCH_BYTE
  guest sees scratch at /dev/rdsk/c0t0d0s3 block $FAT_NBLKS

  NOTE: vdisk_ram is anonymous host RAM of the served size, so this costs
  ${VOLSIZE_MB}MB of host memory per running VM, and the boot-time load and
  exit-time writeback both move that much data. P2-012 (MAP_SHARED file backing)
  removes all three costs.
EOF
}

# Emit shell-sourceable offsets so callers stop recomputing them by hand.
# A literal 2668003328 was once copied into niagara.c from a stale note and was
# 832 blocks wrong; it stayed inside the region so nothing broke, which is
# exactly why it survived. Single source of truth instead.
cmd_scratch() {
    cat <<EOF
SCRATCH_START_BLK=$SCRATCH_START
SCRATCH_NBLKS=$SCRATCH_NBLKS
SCRATCH_BYTE=$SCRATCH_BYTE
SCRATCH_BYTES=$(( SCRATCH_NBLKS * 512 ))
SCRATCH_GUEST_S3_BLK=$FAT_NBLKS
EOF
}

cmd_setup() {
    local ds="$1" dev="/dev/zvol/$1" i
    [[ -n "$ds" ]] || usage
    zfs list -t volume "$ds" >/dev/null || { echo "no such zvol: $ds" >&2; exit 1; }

    local cur; cur=$(zfs get -H -o value volsize "$ds")
    echo "volsize: $cur -> ${VOLSIZE_MB}M"
    zfs set "volsize=${VOLSIZE_MB}M" "$ds"
    for i in $(seq 40); do [[ -b "$dev" ]] && break; sleep 0.2; done
    [[ -b "$dev" ]] || { echo "device $dev never appeared" >&2; exit 1; }

    # slice 2 must cover the exchange slice or q.bin will not serve those blocks
    python3 "$VTOC" set "$dev" 2 0            "$DISK_NBLKS"
    python3 "$VTOC" set "$dev" 3 "$EXCH_START" "$EXCH_NBLKS"
    python3 "$VTOC" verify "$dev"
    python3 "$VTOC" show "$dev" | sed -n '/slice/,$p'
}

cmd_push() {
    local ds="$1" tarfile="$2" dev="/dev/zvol/$1"
    [[ -n "$ds" && -n "$tarfile" ]] || usage
    [[ -f "$tarfile" ]] || { echo "no such file: $tarfile" >&2; exit 1; }
    [[ -b "$dev" ]] || { echo "no such device: $dev" >&2; exit 1; }

    local sz blocks
    sz=$(stat -c%s "$tarfile")
    blocks=$(( (sz + 511) / 512 ))
    if (( blocks > EXCH_NBLKS )); then
        echo "ERROR: $tarfile is $sz bytes ($blocks blocks), exchange slice holds $EXCH_NBLKS" >&2
        exit 1
    fi

    # Confirm the label actually declares s3 where we are about to write.
    python3 "$VTOC" verify "$dev" >/dev/null || {
        echo "ERROR: invalid VTOC on $dev — run '$0 setup $ds' first" >&2; exit 1; }

    dd if="$tarfile" of="$dev" bs=512 seek="$EXCH_START" conv=notrunc status=none
    sync
    echo "pushed $sz bytes ($blocks blocks) to $ds slice 3"
    echo "guest: dd if=/dev/rdsk/c0t0d0s3 bs=512 count=$blocks 2>/dev/null | tar xvf -"
}

# ---------------------------------------------------------------------------
# FAT mode: same slice, but with a filesystem both sides can mount.
#
# `push` above is one-shot and one-way: a tar blasted at raw blocks, and the
# guest has to be told the block count. FAT gives a real filesystem, so the
# host can drop files in and read guest output back with no block arithmetic.
#
# Host side: Linux vfat is fully read-write, unlike UFS (this kernel has no
# CONFIG_UFS_FS_WRITE, so the guest's root is host-READ-ONLY forever).
# Guest side: mount -F pcfs /dev/dsk/c0t0d0s3:c /mnt
# The ":c" suffix is how pcfs addresses a whole logical drive on a slice.
#
# The two modes are mutually exclusive: `push` overwrites the FAT superblock,
# and `mkfs` overwrites any pushed tar. Pick one per session.

FAT_MNT="${FAT_MNT:-/mnt/niagara-exchange}"

# Echo the loop device for slice 3, creating it if needed.
_fat_loop() {
    local dev="$1" existing
    existing=$(losetup -j "$dev" -O NAME,OFFSET --noheadings 2>/dev/null \
               | awk -v o="$(( EXCH_START * 512 ))" '$2==o {print $1; exit}')
    if [[ -n "$existing" ]]; then echo "$existing"; return 0; fi
    losetup --show -f -o "$(( EXCH_START * 512 ))" \
            --sizelimit "$(( EXCH_NBLKS * 512 ))" "$dev"
}

_fat_detach() {
    local dev="$1" lo
    for lo in $(losetup -j "$dev" -O NAME --noheadings 2>/dev/null); do
        losetup -d "$lo" 2>/dev/null || true
    done
}

cmd_mkfs() {
    local ds="${1:-}" dev="/dev/zvol/${1:-}" lo before after
    [[ -n "$ds" ]] || usage
    [[ -b "$dev" ]] || { echo "no such device: $dev" >&2; exit 1; }
    python3 "$VTOC" verify "$dev" >/dev/null || {
        echo "ERROR: invalid VTOC on $dev — run '$0 setup $ds' first" >&2; exit 1; }

    # P1-008: canary the scratch tail so a regression here is LOUD instead of
    # silent. The old code formatted the whole slice and quietly ate this region.
    before=$(dd if="$dev" bs=512 skip="$SCRATCH_START" count=1 \
                status=none 2>/dev/null | cksum | awk '{print $1}')

    lo=$(_fat_loop "$dev")
    # -F 32: 496MB/4K = 126976 clusters, comfortably over FAT32's 65525 floor.
    # Explicit -S 512 and -h 0: the filesystem starts at offset 0 of the loop
    # device, so there are no hidden/preceding sectors to declare. Solaris pcfs
    # reads these BPB fields, and a wrong hidden-sector count is a classic way
    # to make a Linux-made FAT unmountable there.
    #
    # THE TRAILING BLOCK COUNT IS THE WHOLE POINT (P1-008). Without it mkfs.vfat
    # sizes the filesystem to the entire loop device, reclaiming the scratch tail
    # that P2-014's channel lives in. mkfs.vfat counts in 1K blocks, not sectors.
    mkfs.vfat -F 32 -S 512 -h 0 -n NIAGARAX "$lo" $(( FAT_NBLKS / 2 )) >/dev/null
    sync
    _fat_detach "$dev"

    after=$(dd if="$dev" bs=512 skip="$SCRATCH_START" count=1 \
               status=none 2>/dev/null | cksum | awk '{print $1}')
    if [[ "$before" != "$after" ]]; then
        echo "ERROR: mkfs modified the scratch region at block $SCRATCH_START" >&2
        echo "       (cksum $before -> $after). The FAT is too large." >&2
        exit 1
    fi

    echo "formatted $ds slice 3 as FAT32 (label NIAGARAX, $(( FAT_NBLKS / 2048 ))MB)"
    echo "scratch tail preserved: $(( SCRATCH_NBLKS / 2048 ))MB at block $SCRATCH_START (cksum $after)"
    echo "guest: mount -F pcfs /dev/dsk/c0t0d0s3:c /mnt"
}

cmd_mount() {
    local ds="${1:-}" dev="/dev/zvol/${1:-}" lo
    [[ -n "$ds" ]] || usage
    [[ -b "$dev" ]] || { echo "no such device: $dev" >&2; exit 1; }
    mkdir -p "$FAT_MNT"
    mountpoint -q "$FAT_MNT" && { echo "$FAT_MNT"; return 0; }
    lo=$(_fat_loop "$dev")
    mount -t vfat -o rw "$lo" "$FAT_MNT"
    echo "$FAT_MNT"
}

cmd_umount() {
    local ds="${1:-}" dev="/dev/zvol/${1:-}"
    [[ -n "$ds" ]] || usage
    mountpoint -q "$FAT_MNT" && { sync; umount "$FAT_MNT"; }
    _fat_detach "$dev"
    echo "unmounted $FAT_MNT"
}

cmd_put() {
    local ds="${1:-}"; shift || true
    [[ -n "$ds" && $# -gt 0 ]] || usage
    cmd_mount "$ds" >/dev/null
    cp -f "$@" "$FAT_MNT/"
    sync
    cmd_umount "$ds" >/dev/null
    echo "put $# file(s) into $ds slice 3 (FAT)"
}

cmd_get() {
    local ds="${1:-}" name="${2:-}" dest="${3:-.}"
    [[ -n "$ds" && -n "$name" ]] || usage
    cmd_mount "$ds" >/dev/null
    if [[ ! -e "$FAT_MNT/$name" ]]; then
        cmd_umount "$ds" >/dev/null
        echo "ERROR: no such file on the FAT slice: $name" >&2; exit 1
    fi
    cp -f "$FAT_MNT/$name" "$dest"
    cmd_umount "$ds" >/dev/null
    echo "got $name -> $dest"
}

cmd_ls() {
    local ds="${1:-}"
    [[ -n "$ds" ]] || usage
    cmd_mount "$ds" >/dev/null
    ls -la "$FAT_MNT"
    cmd_umount "$ds" >/dev/null
}

case "${1:-}" in
    info)   cmd_info ;;
    setup)  shift; cmd_setup  "${1:-}" ;;
    push)   shift; cmd_push   "${1:-}" "${2:-}" ;;
    mkfs)   shift; cmd_mkfs   "${1:-}" ;;
    mount)  shift; cmd_mount  "${1:-}" ;;
    umount) shift; cmd_umount "${1:-}" ;;
    put)    shift; cmd_put    "$@" ;;
    get)    shift; cmd_get    "${1:-}" "${2:-}" "${3:-.}" ;;
    ls)     shift; cmd_ls     "${1:-}" ;;
    *)      usage ;;
esac
