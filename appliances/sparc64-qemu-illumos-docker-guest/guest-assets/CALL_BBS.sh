#!/sbin/sh

PATH=/sbin:/usr/sbin:/bin:/usr/bin:/opt/niag/bin
export PATH

if [ ! -S /tmp/niag1 ]; then
    echo "CALL_BBS=FAIL channel 1 is not ready" >&2
    echo "Run /jack/BRING_UP_NETWORKING.sh first." >&2
    exit 1
fi

echo "Dial the container-local Sunset BBS with: ATDT18005551212"
echo "Press Ctrl-C to hang up."
exec /opt/niag/bin/socat - UNIX-CONNECT:/tmp/niag1

