#!/usr/bin/env bash
set -euo pipefail

TOOLS=${NIAGARA_HOST_TOOLS:-/opt/niagara-project/tools/chan}
CHANNEL_IMAGE=${NIAGARA_CHANNEL_IMAGE:-/run/unit100/carrier-unit100.raw}
CHANNEL_HOST_BYTE=${NIAGARA_CHANNEL_HOST_BYTE:-520093696}
HOST_IP=${NIAGARA_HOST_IP:-10.0.5.1}
GUEST_IP=${NIAGARA_GUEST_IP:-10.0.5.15}
LOG_DIR=${NIAGARA_NETWORK_LOG_DIR:-/state/network}

export NIAGARA_IMG=$CHANNEL_IMAGE
export NIAG_CHAN_HOST_BYTE=$CHANNEL_HOST_BYTE
export HOST_IP GUEST_IP

preflight()
{
    [[ -c /dev/ppp ]] || {
        echo "NETWORK_HELPERS=SKIP reason=/dev/ppp-not-passed"
        return 1
    }
    [[ -w "$CHANNEL_IMAGE" ]] || {
        echo "NETWORK_HELPERS=SKIP reason=channel-image-not-writable"
        return 1
    }
    for command in awk python3 socat pppd ip iptables; do
        command -v "$command" >/dev/null 2>&1 || {
            echo "NETWORK_HELPERS=SKIP reason=missing-$command"
            return 1
        }
    done
    iptables -t nat -L -n >/dev/null 2>&1 || {
        echo "NETWORK_HELPERS=SKIP reason=NET_ADMIN-not-granted"
        return 1
    }
    [[ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" = 1 ]] || {
        echo "NETWORK_HELPERS=SKIP reason=ip-forwarding-disabled"
        return 1
    }
}

prepare()
{
    preflight
    mkdir -p "$LOG_DIR"
    python3 "$TOOLS/host-chan.py" init 0
    python3 "$TOOLS/host-chan.py" init 1
    echo "NETWORK_HELPERS_PREPARE=PASS image=$CHANNEL_IMAGE byte=$CHANNEL_HOST_BYTE"
}

add_rule()
{
    local table=$1
    shift
    iptables -t "$table" -C "$@" 2>/dev/null || \
        iptables -t "$table" -A "$@"
}

serve()
{
    local wan bridge0 bridge1 bbs ppp_loop
    preflight
    mkdir -p "$LOG_DIR"
    wan=$(ip -4 route show default | awk 'NR == 1 { print $5 }')
    [[ -n "$wan" ]] || {
        echo "NETWORK_HELPERS=FAIL reason=no-default-route" >&2
        exit 1
    }

    add_rule nat POSTROUTING -s "$GUEST_IP/32" -o "$wan" -j MASQUERADE
    add_rule filter FORWARD -i ppp0 -o "$wan" -s "$GUEST_IP/32" -j ACCEPT
    add_rule filter FORWARD -i "$wan" -o ppp0 -d "$GUEST_IP/32" \
        -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    python3 "$TOOLS/host-chan.py" bridge 0 /run/niag0 \
        >"$LOG_DIR/channel0.log" 2>&1 &
    bridge0=$!
    python3 "$TOOLS/host-chan.py" bridge 1 /run/niag1 \
        >"$LOG_DIR/channel1.log" 2>&1 &
    bridge1=$!

    for _ in $(seq 1 50); do
        [[ -S /run/niag0 && -S /run/niag1 ]] && break
        sleep 0.1
    done
    [[ -S /run/niag0 && -S /run/niag1 ]] || {
        echo "NETWORK_HELPERS=FAIL reason=channel-socket-timeout" >&2
        exit 1
    }

    python3 "$TOOLS/host-bbs.py" /run/niag1 \
        >"$LOG_DIR/bbs.log" 2>&1 &
    bbs=$!

    (
        while :; do
            "$TOOLS/host-pppd-once.sh" /run/niag0 \
                >>"$LOG_DIR/ppp.log" 2>&1 || true
            sleep 2
        done
    ) &
    ppp_loop=$!

    cleanup()
    {
        kill "$ppp_loop" "$bbs" "$bridge1" "$bridge0" 2>/dev/null || true
        wait "$ppp_loop" "$bbs" "$bridge1" "$bridge0" 2>/dev/null || true
        iptables -t filter -D FORWARD -i "$wan" -o ppp0 -d "$GUEST_IP/32" \
            -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT \
            2>/dev/null || true
        iptables -t filter -D FORWARD -i ppp0 -o "$wan" \
            -s "$GUEST_IP/32" -j ACCEPT 2>/dev/null || true
        iptables -t nat -D POSTROUTING -s "$GUEST_IP/32" -o "$wan" \
            -j MASQUERADE 2>/dev/null || true
    }
    trap cleanup EXIT INT TERM

    echo "NETWORK_HELPERS=PASS wan=$wan host=$HOST_IP guest=$GUEST_IP channels=0,1"
    while kill -0 "$bridge0" "$bridge1" "$bbs" "$ppp_loop" 2>/dev/null; do
        sleep 5
    done
    echo "NETWORK_HELPERS=FAIL reason=helper-exited" >&2
    exit 1
}

case "${1:-}" in
preflight) preflight ;;
prepare) prepare ;;
serve) serve ;;
*) echo "usage: $0 preflight|prepare|serve" >&2; exit 2 ;;
esac
