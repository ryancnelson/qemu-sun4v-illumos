#!/usr/bin/env bash
# Tear down a networked Solaris session started by tools/net-up.sh.
#
#   sudo bash tools/net-down.sh            # stop everything, keep the disk
#   sudo bash tools/net-down.sh --rollback # stop everything AND roll back
#
# Why rollback is the default recommendation: `init 5` after a PPP session
# always ends in a broken OBP (ERROR: Last Trap: Fast Data Access MMU Miss)
# rather than "Program terminated", so the guest cannot be shut down cleanly and
# the writeback may persist a dirty LUFS journal -- which panics the NEXT boot in
# ufs:readlog/vfs_mountroot. Rolling back to @networked avoids the whole
# question. Anything you need to keep should leave via the FAT slice
# (tools/exchange.sh get) BEFORE tearing down.

set -uo pipefail

PROJ="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
ZVOL="${ZVOL:-datapool/niagara/images}"
SNAP="${SNAP:-baseline}"
ROLLBACK=0
[[ "${1:-}" == "--rollback" ]] && ROLLBACK=1

say() { echo "==> $*"; }
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

say "stopping host pppd"
pkill -f "pppd /tmp/sol-console" 2>/dev/null

say "stopping socat bridge"
pkill -f 'socat.*sol-net.sock' 2>/dev/null

# SIGTERM, never SIGKILL: the atexit handler is what writes the vdisk back, and
# SIGKILL discards every guest write.
QPID=$(pgrep -f 'qemu-system-sparc64' | head -1)
if [[ -n "$QPID" ]]; then
    say "SIGTERM qemu pid $QPID (atexit writeback)"
    kill -TERM "$QPID" 2>/dev/null
    for _ in $(seq 60); do pgrep -f 'qemu-system-sparc64' >/dev/null || break; sleep 1; done
    pgrep -f 'qemu-system-sparc64' >/dev/null && { say "still up, forcing"; pkill -9 -f 'qemu-system-sparc64'; }
fi
rm -f /tmp/sol-net.sock /tmp/sol-console

if (( ROLLBACK )); then
    say "rolling back $ZVOL to @$SNAP"
    zfs rollback -r "$ZVOL@$SNAP" && say "rolled back"
else
    cat <<EOF

  Disk left as-is. It may carry a dirty journal from the PPP session, which
  panics the next boot. If it does, recover with:

    sudo zfs rollback -r $ZVOL@$SNAP

EOF
fi

say "done. qemu procs: $(pgrep -cf 'qemu-system-sparc64')"
