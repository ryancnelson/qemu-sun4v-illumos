#!/bin/sh
# Attach one Linux pppd session to an already-running channel bridge.
set -eu

SOCK=${1:-/run/niag0}
HOST_IP=${HOST_IP:-10.0.5.1}
GUEST_IP=${GUEST_IP:-10.0.5.15}

exec socat "UNIX-CONNECT:$SOCK" \
    "EXEC:'/usr/sbin/pppd notty noauth local noccp nodeflate nobsdcomp novj asyncmap 0 ${HOST_IP}:${GUEST_IP} nodetach debug',nofork"
