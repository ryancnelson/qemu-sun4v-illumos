#!/bin/sh
# Expose a host-side HTTP CONNECT proxy to Tribblix over one niag channel.
#
# Usage in the guest:
#   guest-chand 1 /tmp/niag1 &
#   guest-http-proxy.sh 1 3128 &
#   http_proxy=http://127.0.0.1:3128
#   https_proxy=http://127.0.0.1:3128
#   export http_proxy https_proxy
#
# A channel is one byte stream, so this intentionally serves one proxy TCP
# connection at a time.  When that connection closes, socat is restarted for
# the next one.  Do not add "fork" here: concurrent clients would become
# concurrent writers to the same channel control block.

set -u

CH=${1:-1}
PORT=${2:-3128}
SOCK=${NIAG_GUEST_SOCK:-/tmp/niag${CH}}
SOCAT=${NIAG_SOCAT:-/opt/niag/bin/socat}

while :; do
    "$SOCAT" "TCP4-LISTEN:${PORT},bind=127.0.0.1,reuseaddr" \
        "UNIX-CONNECT:${SOCK}"
    sleep 1
done
