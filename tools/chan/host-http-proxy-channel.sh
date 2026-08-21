#!/bin/sh
# Attach one host niag channel to an existing TCP HTTP CONNECT proxy.
#
# Usage on the QEMU host:
#   host-http-proxy-channel.sh 1 127.0.0.1 3128
#
# Pair this with guest-http-proxy.sh in Tribblix.  Like the guest side, this
# reconnects after each proxy connection and never forks onto one channel.

set -u

CH=${1:-1}
PROXY_HOST=${2:-127.0.0.1}
PROXY_PORT=${3:-3128}
SOCK=${NIAG_HOST_SOCK:-/run/niag${CH}}
SOCAT=${NIAG_SOCAT:-socat}

while :; do
    "$SOCAT" "UNIX-CONNECT:${SOCK}" "TCP4:${PROXY_HOST}:${PROXY_PORT}"
    sleep 1
done
