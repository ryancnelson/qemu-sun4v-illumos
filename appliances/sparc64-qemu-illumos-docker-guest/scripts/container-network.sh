#!/usr/bin/env bash
set -euo pipefail

TOOLS=${NIAGARA_HOST_TOOLS:-/opt/niagara-project/tools/chan}
CHANNEL_IMAGE=${NIAGARA_CHANNEL_IMAGE:-/run/unit100/carrier-unit100.raw}
CHANNEL_HOST_BYTE=${NIAGARA_CHANNEL_HOST_BYTE:-520093696}
HOST_IP=${NIAGARA_HOST_IP:-10.0.5.1}
GUEST_IP=${NIAGARA_GUEST_IP:-10.0.5.15}
LOG_DIR=${NIAGARA_NETWORK_LOG_DIR:-/state/network}
STATUS_FILE=${NIAGARA_NETWORK_STATUS_FILE:-$LOG_DIR/status.env}
PID_FILE=${NIAGARA_NETWORK_PID_FILE:-/state/network-helper.pid}
DNS_PORT=${NIAGARA_DNS_PORT:-53}
PROXY_PORT=${NIAGARA_PROXY_PORT:-8888}

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
    for command in awk dnsmasq python3 socat pppd ip iptables tinyproxy; do
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

write_status()
{
    local phase=$1
    local temporary
    mkdir -p "$LOG_DIR"
    temporary="$STATUS_FILE.$$"
    {
        echo "phase=$phase"
        echo "host_ip=$HOST_IP"
        echo "guest_ip=$GUEST_IP"
        echo "dns=$HOST_IP:$DNS_PORT"
        echo "http_proxy=http://$HOST_IP:$PROXY_PORT"
        echo "updated_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$temporary"
    mv "$temporary" "$STATUS_FILE"
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
    local wan bridge0 bridge1 bbs ppp_loop dns_pid proxy_pid proxy_config
    bridge0= bridge1= bbs= ppp_loop= dns_pid= proxy_pid=
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

    cleanup()
    {
        local pid
        for pid in "$proxy_pid" "$dns_pid" "$ppp_loop" "$bbs" "$bridge1" "$bridge0"; do
            [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true
        done
        for pid in "$proxy_pid" "$dns_pid" "$ppp_loop" "$bbs" "$bridge1" "$bridge0"; do
            [[ -z "$pid" ]] || wait "$pid" 2>/dev/null || true
        done
        iptables -t filter -D FORWARD -i "$wan" -o ppp0 -d "$GUEST_IP/32" \
            -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT \
            2>/dev/null || true
        iptables -t filter -D FORWARD -i ppp0 -o "$wan" \
            -s "$GUEST_IP/32" -j ACCEPT 2>/dev/null || true
        iptables -t nat -D POSTROUTING -s "$GUEST_IP/32" -o "$wan" \
            -j MASQUERADE 2>/dev/null || true
        write_status stopped
    }
    trap cleanup EXIT INT TERM

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

    write_status waiting_for_ppp
    echo "NETWORK_HELPERS=PASS wan=$wan host=$HOST_IP guest=$GUEST_IP channels=0,1 phase=waiting-for-guest"
    until ip -4 addr show ppp0 2>/dev/null | grep -F "$HOST_IP" >/dev/null; do
        kill -0 "$bridge0" "$bridge1" "$bbs" "$ppp_loop" 2>/dev/null || {
            echo "NETWORK_HELPERS=FAIL reason=helper-exited-before-ppp" >&2
            exit 1
        }
        sleep 1
    done

    dnsmasq --keep-in-foreground --bind-dynamic --interface=ppp0 \
        --listen-address="$HOST_IP" --port="$DNS_PORT" \
        --no-dhcp-interface=ppp0 --log-facility=- \
        >"$LOG_DIR/dns.log" 2>&1 &
    dns_pid=$!

    proxy_config="$LOG_DIR/tinyproxy.conf"
    cat >"$proxy_config" <<EOF
User nobody
Group nogroup
Port $PROXY_PORT
Listen $HOST_IP
Timeout 60
MaxClients 32
StartServers 1
MinSpareServers 1
MaxSpareServers 4
LogFile "$LOG_DIR/proxy-access.log"
LogLevel Info
PidFile "$LOG_DIR/tinyproxy.pid"
Allow $GUEST_IP
ConnectPort 443
ConnectPort 563
EOF
    tinyproxy -d -c "$proxy_config" >"$LOG_DIR/proxy.log" 2>&1 &
    proxy_pid=$!

    sleep 1
    kill -0 "$dns_pid" "$proxy_pid" 2>/dev/null || {
        echo "NETWORK_HELPERS=FAIL reason=proxy-startup" >&2
        exit 1
    }
    write_status ready
    echo "NETWORK_SERVICES=PASS dns=$HOST_IP:$DNS_PORT http_proxy=http://$HOST_IP:$PROXY_PORT"
    while kill -0 "$bridge0" "$bridge1" "$bbs" "$ppp_loop" "$dns_pid" "$proxy_pid" 2>/dev/null; do
        sleep 5
    done
    echo "NETWORK_HELPERS=FAIL reason=helper-exited" >&2
    exit 1
}

health()
{
    local pid
    if [[ "${NIAGARA_NETWORK:-auto}" = off ]]; then
        echo "NETWORK_HEALTH=PASS mode=disabled"
        return 0
    fi
    if [[ ! -r "$PID_FILE" && "${NIAGARA_NETWORK:-auto}" = auto ]]; then
        echo "NETWORK_HEALTH=PASS mode=auto-disabled"
        return 0
    fi
    [[ -r "$PID_FILE" ]] || {
        echo "NETWORK_HEALTH=FAIL reason=pid-file-missing"
        return 1
    }
    read -r pid <"$PID_FILE"
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null || {
        echo "NETWORK_HEALTH=FAIL reason=supervisor-not-running"
        return 1
    }
    [[ -r "$STATUS_FILE" ]] && cat "$STATUS_FILE"
    echo "NETWORK_HEALTH=PASS pid=$pid"
}

case "${1:-}" in
preflight) preflight ;;
prepare) prepare ;;
serve) serve ;;
health) health ;;
*) echo "usage: $0 preflight|prepare|serve|health" >&2; exit 2 ;;
esac
