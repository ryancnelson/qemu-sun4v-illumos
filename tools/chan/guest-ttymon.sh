#!/bin/sh
# ttymon express mode only converts an INIT_PROCESS utmpx entry supplied by
# init. The wrapper creates that entry before execing ttymon, while the socat
# child owns the controlling PTY. ttymon reopens its actual device path
# read/write; Solaris does not permit that operation through /dev/fd/0.
DEV=`/usr/bin/tty`
case "$DEV" in
/dev/pts/*) ;;
*) echo "unexpected tty: $DEV" >&2; exit 1 ;;
esac
exec /opt/niag/bin/guest-utmp-ttymon
