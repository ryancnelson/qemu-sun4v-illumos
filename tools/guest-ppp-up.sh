#!/bin/sh
# Bring up the guest end of the PPP link over the qcn console.
PATH=/usr/bin:/usr/sbin:/sbin
export PATH
nohup /tmp/wd.sh >/dev/null 2>&1 &
# CRITICAL: `notty` deliberately does NOT set terminal modes. Leaving the console
# in canonical mode with ECHO on makes the guest tty echo every byte the host
# sends, so the host's pppd receives its own frames back -- it detects the
# loopback ("rcvd" identical to "sent", same magic) and eventually gives up with
# "LCP: timeout sending Config-Requests". Set the line raw ourselves.
stty raw -echo < /dev/console
# stdout/stdin ARE the PPP link, so pppd's own logging MUST go elsewhere or it
# corrupts the frame stream.
exec pppd notty noauth local 10.0.5.15:10.0.5.1 nodetach debug 2>/tmp/gppp.log
