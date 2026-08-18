#!/usr/bin/env bash
# Checkpoint a RUNNING Solaris session to the zvol, without shutting it down.
#
#   sudo bash tools/checkpoint.sh            # quiesce + flush
#   sudo bash tools/checkpoint.sh mywork     # ... and ZFS-snapshot as @mywork
#
# Solves the problem that made every session all-or-nothing: `init 5` after a PPP
# session reliably ends in a broken OBP rather than "Program terminated", so
# there was no way to keep work without a clean shutdown you could not get.
#
# WHY QUIESCING MATTERS. Flushing a running guest gives a CRASH-consistent image,
# not a filesystem-consistent one: the guest may be mid-transaction, so its LUFS
# journal needs replay, and that replay is exactly the
# `BAD TRAP ... ufs:readlog -> vfs_mountroot` panic that has cost us several
# rollbacks. So this script does, in order:
#
#   1. guest `sync` then `lockfs -f /`  -- push UFS metadata out of the guest's
#      buffer cache into the vdisk RAM (over telnet, which is why networking had
#      to work first)
#   2. `kill -USR2` the QEMU pid       -- our niagara.c handler flushes 2560MB of
#      vdisk RAM to the zvol from the main loop
#   3. optional `zfs snapshot`         -- freeze that now-consistent image
#
# LIMITATION, stated honestly: this does not stop the guest's CPUs, so a write
# issued between the lockfs and the flush completing is still in flight. For a
# fully atomic image you would add QEMU monitor `stop` / `cont` around step 2,
# which needs `-monitor unix:...` on the QEMU command line. In practice the guest
# is idle at a shell prompt while you run this, so lockfs is enough. Verify by
# booting the result -- `tests/test-toolchain-compiles.sh` style -- rather than
# trusting it.

set -uo pipefail

PROJ="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
ZVOL="${ZVOL:-datapool/niagara/vms/primary}"
GUEST_IP="${GUEST_IP:-10.0.5.15}"
SNAPNAME="${1:-}"

say() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo"

QPID=$(pgrep -f 'qemu-system-sparc64' | head -1)
[[ -n "$QPID" ]] || die "no running VM to checkpoint"
say "qemu pid $QPID"

# --- 1. quiesce the guest filesystem over telnet ------------------------
if ping -c 1 -W 2 "$GUEST_IP" >/dev/null 2>&1; then
    say "quiescing guest filesystem (sync + lockfs -f /)"
    expect -f - "$GUEST_IP" <<'EXPECT' >/tmp/checkpoint-quiesce.log 2>&1
        set timeout 30
        set ip [lindex $argv 0]
        spawn telnet $ip 23
        expect { "login:" { send "root\r" } timeout { exit 1 } }
        expect { -re {[#$] $} {} timeout { exit 1 } }
        send "sync; lockfs -f /; echo QUIESCED\r"
        expect { "QUIESCED" {} timeout {} }
        expect { -re {[#$] $} {} timeout {} }
        send "exit\r"
        expect { eof {} timeout {} }
EXPECT
    if grep -q QUIESCED /tmp/checkpoint-quiesce.log; then
        say "guest filesystem flushed"
    else
        say "WARNING: could not quiesce over telnet; image will be crash-consistent only"
    fi
else
    say "WARNING: guest not reachable at $GUEST_IP; skipping quiesce"
    say "         the resulting image may need journal replay and could panic"
fi

# --- 2. flush vdisk RAM to the zvol -------------------------------------
say "flushing vdisk to $ZVOL (SIGUSR2)"
BEFORE=$(date +%s)
kill -USR2 "$QPID" || die "could not signal $QPID"

# The handler prints on completion; the timer polls once a second, so allow for
# that plus the time to push 2560MB.
# The timer polls the flag once a second, then pushes 2560MB. Count completion
# lines before and after rather than pattern-matching a tail, so a previous
# flush in the same session cannot be mistaken for this one.
LOG=${QEMU_LOG:-/tmp/sol-net-qemu.log}
N0=$(grep -ac 'writeback complete' "$LOG" 2>/dev/null | head -1); N0=${N0:-0}
for _ in $(seq 60); do
    sleep 1
    pgrep -f 'qemu-system-sparc64' >/dev/null || die "qemu died during checkpoint"
    N1=$(grep -ac 'writeback complete' "$LOG" 2>/dev/null | head -1); N1=${N1:-0}
    if [[ "${N1:-0}" -gt "${N0:-0}" ]]; then say "flush confirmed in $(( $(date +%s) - BEFORE ))s"; break; fi
done
[[ "${N1:-0}" -gt "${N0:-0}" ]] || say "WARNING: no new 'writeback complete' in $LOG -- flush unconfirmed"

# --- 3. optional snapshot ------------------------------------------------
if [[ -n "$SNAPNAME" ]]; then
    say "snapshotting $ZVOL@$SNAPNAME"
    zfs destroy "$ZVOL@$SNAPNAME" 2>/dev/null
    zfs snapshot "$ZVOL@$SNAPNAME" && say "created $ZVOL@$SNAPNAME"
    say "VERIFY it boots before trusting it; a checkpoint is not proof."
fi

say "done"
