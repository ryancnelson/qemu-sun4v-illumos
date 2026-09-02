#!/sbin/sh

PATH=/sbin:/usr/sbin:/bin:/usr/bin:/opt/niag/bin
export PATH

DEV=${NIAG_CHAN_DEV:-/dev/rdsk/c1d0s2}
GUEST_IP=10.0.5.15
HOST_IP=10.0.5.1
GUEST_IF=${NIAG_PPP_IF:-sppp0}

fail()
{
    echo "NETWORKING=FAIL reason=$*" >&2
    for log in /tmp/niag-chand0.log /tmp/niag-chand1.log /tmp/gppp0.log \
        /tmp/gppp-chan0.wait /tmp/gppp-chan0.log /tmp/gpppd-chan0.log
    do
        [ -f "$log" ] && { echo "--- $log" >&2; tail -40 "$log" >&2; }
    done
    exit 1
}

[ "$(id -u)" = 0 ] || fail "run this script as root"
[ -x /opt/niag/bin/guest-chand ] || fail "guest-chand is missing"
[ -r /opt/niag/bin/guest-ppp-chan.pl ] || fail "guest PPP wrapper is missing"
[ -c "$DEV" ] || fail "channel device is missing: $DEV"

/usr/sbin/devfsadm -i sppp -i sppptun >/tmp/niag-devfsadm.log 2>&1 || \
    fail "devfsadm could not create sppp devices"

NIAG_CHAN_DEV=$DEV
export NIAG_CHAN_DEV

for ch in 0 1
do
    socket=/tmp/niag${ch}
    log=/tmp/niag-chand${ch}.log
    count=$(/usr/bin/pgrep -f "/opt/niag/bin/guest-chand ${ch} " 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -le 1 ] || fail "more than one channel-$ch daemon is running"
    if [ "$count" = 0 ]; then
        rm -f "$socket"
        nohup /opt/niag/bin/guest-chand "$ch" "$socket" </dev/null >"$log" 2>&1 &
    fi
done

n=0
while [ ! -S /tmp/niag0 ] || [ ! -S /tmp/niag1 ]
do
    n=$((n + 1))
    [ "$n" -lt 60 ] || fail "channel sockets did not become ready"
    sleep 1
done

ppp_count=$(/usr/bin/pgrep -f 'guest-ppp-chan.pl 0 10.0.5.15:10.0.5.1' 2>/dev/null | wc -l | tr -d ' ')
[ "$ppp_count" -le 1 ] || fail "more than one PPP wrapper is running"
if [ "$ppp_count" = 0 ] && ! /sbin/ifconfig "$GUEST_IF" >/dev/null 2>&1; then
    nohup /usr/bin/perl /opt/niag/bin/guest-ppp-chan.pl 0 \
        ${GUEST_IP}:${HOST_IP} </dev/null >/tmp/gppp0.log 2>&1 &
fi

n=0
while ! /sbin/ifconfig "$GUEST_IF" 2>/dev/null | /usr/bin/grep -q "$GUEST_IP"
do
    n=$((n + 1))
    [ "$n" -lt 120 ] || fail "ppp0 did not acquire $GUEST_IP"
    sleep 1
done

if ! /usr/bin/grep -q "^nameserver ${HOST_IP}$" /etc/resolv.conf 2>/dev/null; then
    cp -p /etc/resolv.conf /etc/resolv.conf.before-niagara 2>/dev/null || true
    echo "nameserver ${HOST_IP}" >/etc/resolv.conf
fi

echo "NETWORKING=PASS guest=${GUEST_IP} peer=${HOST_IP}"
/sbin/ifconfig "$GUEST_IF"
/usr/bin/netstat -rn
echo "DNS server: ${HOST_IP}"
echo "HTTP proxy: http://${HOST_IP}:8888"
echo "For proxy-aware tools:"
echo "  export http_proxy=http://${HOST_IP}:8888"
echo "  export https_proxy=http://${HOST_IP}:8888"
