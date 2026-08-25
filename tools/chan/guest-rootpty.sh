#!/bin/sh
# Emergency root PTY over a P2-014 channel.  Unlike QEMU's stdio console,
# terminal signals stay inside the guest PTY, so Ctrl-C cannot terminate QEMU.
# This is a recovery shell, not the authenticated ttymon/getty service.
CH=${1:-1}
SOCK=/tmp/niag$CH
SOCAT=${NIAG_SOCAT:-/opt/niag/bin/socat}
GUEST_SHELL=${NIAG_GUEST_SHELL:-/bin/bash}

while true; do
        "$SOCAT" "UNIX-CONNECT:$SOCK" \
            "EXEC:$GUEST_SHELL,pty,setsid,ctty,stderr"
        sleep 1
done
