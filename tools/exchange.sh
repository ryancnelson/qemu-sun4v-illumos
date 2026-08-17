#!/usr/bin/env bash
# Bulk host -> guest data channel using a raw VTOC slice.
#
#   tools/exchange.sh setup <zvol-dataset>
#   tools/exchange.sh push  <zvol-dataset> <file.tar>
#   tools/exchange.sh info
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
#   s3  block 4194304 .. 5242879    512MB   exchange (raw, no filesystem)
#   s2  block       0 .. 5242879   2560MB   whole disk -> q.bin's served size
#
# GUEST SIDE:
#   dd if=/dev/rdsk/c0t0d0s3 bs=512 count=<blocks> 2>/dev/null | tar xvf -
#   (count is optional; tar stops at the end-of-archive marker either way, but
#   bounding it avoids reading 512MB of trailing garbage.)
#
# Solaris /bin/sh is not POSIX: no $(...). Use backticks in payload scripts.

set -euo pipefail

PROJ="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
VTOC="$PROJ/tools/vtoc.py"

S0_NBLKS=4194296          # existing root slice, do not touch
EXCH_START=4194304        # 8 blocks of pad after s0 (cylinder alignment)
EXCH_NBLKS=1048576        # 512MB
DISK_NBLKS=$(( EXCH_START + EXCH_NBLKS ))   # 5242880 = 2560MB
VOLSIZE_MB=$(( DISK_NBLKS / 2048 ))         # 2560

usage() { sed -n '2,40p' "$0"; exit 1; }

cmd_info() {
    cat <<EOF
exchange slice geometry
  s0     blocks 0..$(( S0_NBLKS - 1 ))  (root UFS, untouched)
  s3     blocks $EXCH_START..$(( DISK_NBLKS - 1 ))  = $(( EXCH_NBLKS / 2048 ))MB
  s2     blocks 0..$(( DISK_NBLKS - 1 ))  = ${VOLSIZE_MB}MB  (q.bin served size)
  host byte offset of s3 = $(( EXCH_START * 512 ))
  required zvol volsize   = ${VOLSIZE_MB}M

  NOTE: vdisk_ram is anonymous host RAM of the served size, so this costs
  ${VOLSIZE_MB}MB of host memory per running VM, and the boot-time load and
  exit-time writeback both move that much data.
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

case "${1:-}" in
    info)  cmd_info ;;
    setup) shift; cmd_setup "${1:-}" ;;
    push)  shift; cmd_push "${1:-}" "${2:-}" ;;
    *)     usage ;;
esac
