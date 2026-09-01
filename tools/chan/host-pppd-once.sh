#!/bin/sh
# Attach one host pppd session to an already-running channel bridge.
set -eu

SOCK=${1:-/run/niag0}
HOST_IP=${HOST_IP:-10.0.5.1}
GUEST_IP=${GUEST_IP:-10.0.5.15}
PPPD=${PPPD:-}

if [ -z "$PPPD" ]; then
    if [ -x /usr/sbin/pppd ]; then
        PPPD=/usr/sbin/pppd
    elif [ -x /usr/bin/pppd ]; then
        # Tribblix's TRIBsys-net-ppp package installs the native daemon here.
        PPPD=/usr/bin/pppd
    else
        echo "host-pppd-once: no pppd found in /usr/sbin or /usr/bin" >&2
        exit 1
    fi
fi

[ -x "$PPPD" ] || {
    echo "host-pppd-once: PPPD is not executable: $PPPD" >&2
    exit 1
}

exec socat "UNIX-CONNECT:$SOCK" \
    "EXEC:'$PPPD notty noauth local noccp nodeflate nobsdcomp novj asyncmap 0 ${HOST_IP}:${GUEST_IP} nodetach debug',nofork"
