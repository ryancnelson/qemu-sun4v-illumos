#!/usr/bin/env bash
# Solaris 10 on QEMU UltraSPARC T1 (Niagara / sun4v) — daily driver.
#
#   ./run-solaris.sh           boot the primary zvol
#   ./run-solaris.sh reset     rollback primary to $RESET_SNAP (default @clean-2gb)
#   ./run-solaris.sh status    show zvol/snapshot state and lock holder
#
# BOOT:  at the "ok" prompt type:  boot disk
# LOGIN: root (no password)
#
# ---------------------------------------------------------------------------
# EXIT PROCEDURE — NOT OPTIONAL
#
#   Inside Solaris:   lockfs -f / && sync
#   Then:             Ctrl-A c   →   quit
#
# `lockfs -f /` commits the UFS logging (LUFS) journal. Skip it and the atexit
# writeback persists an image with a dirty journal; the NEXT boot panics
# replaying it:  BAD TRAP type=10  ufs:fetchbuf -> readlog -> vfs_mountroot
# Recover with: ./run-solaris.sh reset
# ---------------------------------------------------------------------------
#
# STORAGE
#   /dev/zvol/datapool/niagara/vms/primary  is the root filesystem.
#   Guest writes go: UFS -> hcall_disk_write (0xf1) -> q.bin -> vdisk_ram,
#   and QEMU's atexit handler writes vdisk_ram back to the zvol, taking a
#   @pre-exit-<pid> snapshot first as a rollback point.
#
# LOCKING
#   Takes the same lock the test harness uses, so a `tests/run-all.sh` run and
#   this script cannot both open `primary` at once. That would corrupt it.

set -euo pipefail

PROJ="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$PROJ/tests/lib/lock.sh"

QEMU="${QEMU_BIN:-$PROJ/qemu/build/qemu-system-sparc64}"
S10DIR="${S10DIR:-/datapool/niagara/base}"
POOL="${NIAGARA_POOL:-datapool}"
DATASET="${NIAGARA_DATASET:-niagara}"
PRIMARY_DS="$POOL/$DATASET/vms/primary"
PRIMARY="/dev/zvol/$PRIMARY_DS"
RESET_SNAP="${RESET_SNAP:-clean-2gb}"
ZVOL_LOCK="vms/primary"

case "${1:-}" in
reset)
    # NOTE: `zfs rollback` also reverts volsize to whatever it was when the
    # snapshot was taken. @clean-2gb was taken at volsize=2G with a 2GB VTOC
    # and a 1.9GB UFS, so that is self-consistent and needs no re-grow.
    # -r destroys the @pre-exit-* snapshots that would otherwise block it.
    echo "Rolling back $PRIMARY_DS -> @$RESET_SNAP"
    sudo zfs rollback -r "$PRIMARY_DS@$RESET_SNAP"
    echo "volsize now: $(sudo zfs get -H -o value volsize "$PRIMARY_DS")"
    exit 0
    ;;
status)
    echo "=== $PRIMARY_DS ==="
    sudo zfs list -t all -r "$POOL/$DATASET/vms"
    echo
    echo "volsize: $(sudo zfs get -H -o value volsize "$PRIMARY_DS")"
    lf="/run/niagara-${ZVOL_LOCK//\//-}.lock"
    if [[ -f "$lf" ]]; then
        p=$(cat "$lf" 2>/dev/null || true)
        if kill -0 "$p" 2>/dev/null; then echo "lock: HELD by pid $p"
        else echo "lock: stale (pid $p dead)"; fi
    else
        echo "lock: free"
    fi
    exit 0
    ;;
"") ;;
*)  echo "usage: $0 [reset|status]" >&2; exit 1 ;;
esac

[[ -x "$QEMU" ]] || { echo "ERROR: no QEMU at $QEMU" >&2; exit 1; }
[[ -b "$PRIMARY" ]] || { echo "ERROR: no zvol device $PRIMARY" >&2; exit 1; }

trap 'lock_release "$ZVOL_LOCK" 2>/dev/null || true' EXIT INT TERM
lock_acquire "$ZVOL_LOCK"

echo "Booting Solaris 10 / sun4v (Niagara)"
echo "  Boot:  boot disk"
echo "  Login: root (no password)"
echo "  EXIT:  lockfs -f / && sync   then   Ctrl-A c , quit"
echo ""

# `exec sudo CMD`, not `sudo exec CMD` — exec is a shell builtin, so the
# latter asks sudo to find a binary named "exec" and fails.
# No exec here though: we want the trap to release the lock afterwards.
sudo "$QEMU" \
    -M niagara \
    -L "$S10DIR" \
    -m 256 \
    -nographic \
    -drive "if=pflash,file=$PRIMARY,format=raw"
