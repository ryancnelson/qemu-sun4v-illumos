#!/usr/bin/env bash
# Boot the Solaris 10 sun4v guest. Run this in a TERMINAL you can type into --
# the console is this terminal's stdin/stdout, so a backgrounded or nohup'd run
# leaves the guest stuck at "ok" with no way to reach it.
#
#   $ ~/sun4v/run.sh
#   ok boot disk            <- type this
#   ... ~40s ...
#   unknown console login: root      <- no password
#
# To shut down cleanly:   init 5      (then this process exits)
# To detach QEMU instead: Ctrl-A c    then 'quit'
#
# NOTE: init 6 does NOT reboot this machine. It halts cleanly and then reports
#   panic - kernel: prom_reboot: reboot call returned!
# because QEMU's niagara has no OBP reboot. Afterwards 'boot disk' at the ok
# prompt fails with "Last Trap: Level 14 Interrupt", so re-run this script.
set -euo pipefail

H="$HOME"
QEMU="$H/niag-proj/qemu/build/qemu-system-sparc64"
FW="\$H/sun4v/firmware/base-1gib"
IMG="\$H/sun4v/images/primary.img"
MEM="${NIAGARA_MEM:-1024}"

for f in "$QEMU" "$IMG"; do
    [[ -e "$f" ]] || { echo "missing: $f" >&2; exit 1; }
done
[[ -d "$FW" ]] || { echo "missing firmware dir: $FW" >&2; exit 1; }

# Refuse to start a second instance: two QEMUs on one MAP_SHARED image will
# corrupt it, and the failure looks like random filesystem damage later.
if pgrep -f "qemu-system-sparc64 -M niagara" > /dev/null; then
    echo "A niagara guest is ALREADY RUNNING. Stop it first:" >&2
    echo "  sudo pkill -f qemu-system-sparc64" >&2
    exit 1
fi

cat <<'WARN'

  ok boot disk        <- type this, then log in as root (no password)

  SHUT DOWN WITH   init 5   -- NOT by closing this window.
  Killing a booted guest leaves the UFS log mid-transaction and the NEXT boot
  panics before it reaches a prompt:
      panic[cpu0]: BAD TRAP: type=10 ... ufs:readlog+60
  That is unrecoverable in practice; the fix is to replace the image from a
  clean copy, not to repair the journal. Keep a pristine copy:
      cp --reflink=auto IMAGE IMAGE.clean
  A host-side msync (SIGUSR2) does NOT help -- it flushes the host mapping,
  never the guest's dirty pages. Only the guest can quiesce itself.

WARN
# Snapshot-on-first-run, so there is always something to roll back to. Costs
# nothing on a reflink filesystem and 2.5 GB otherwise -- cheap against losing
# a guest you cannot rebuild.
if [[ ! -e "$IMG.clean" ]]; then
    echo "  keeping a pristine copy at $(basename "$IMG").clean"
    cp --reflink=auto "$IMG" "$IMG.clean"
fi
exec sudo "$QEMU" -M niagara -L "$FW" -m "$MEM" -nographic \
    -drive if=pflash,file="$IMG",format=raw
