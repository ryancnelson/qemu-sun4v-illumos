#!/usr/bin/env bash
# Bring up IP over channel 0 (P2-017), leaving the console FREE.
#
#   sudo bash tools/chan/net-chan-up.sh [nchan]     default 4
#   telnet 10.0.5.15                               <- root, no password
#   sudo bash tools/chan/net-chan-down.sh
#
# WHAT THIS REPLACES: tools/net-up.sh ran pppd over /dev/console, which meant
# networking and an interactive console were mutually exclusive, and `init 5`
# afterwards reliably landed in a broken OBP (Fast Data Access MMU Miss). Here PPP
# rides channel 0 and the console is never touched.
#
# WHY channel 0 SPECIFICALLY, and why 16 channels existed first: IP is the heavy
# consumer, and putting it on the only channel would have recreated the console
# problem with better throughput. Channels 1..N-1 stay free.
#
# TOPOLOGY
#   guest  pppd notty  <-fd 0/1->  perl guest-ppp-chan.pl  <->  /tmp/niag0
#                                                                    |
#                                                       shared pages (P2-012)
#                                                                    |
#   host   pppd notty  <-fd 0/1->  socat  <->  /run/niag0
#
#   10.0.5.1 (host)  <-->  10.0.5.15 (guest), plus NAT to the default route.
#
# NOT slirp in QEMU's sense: this machine has no NIC for QEMU to attach slirp to,
# so the userspace-NAT role is played by host pppd + iptables MASQUERADE. The
# effect is the same -- the guest reaches the outside world without a tap device.

set -uo pipefail

PROJ="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
N="${1:-4}"
GUEST_IP=10.0.5.15
HOST_IP=10.0.5.1
GUEST="${CHAN_GUEST:-$GUEST_IP}"
CH=0

say() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo"
command -v socat >/dev/null || die "socat required on the host"

# --- channels up (this also enforces stop -> init -> guest -> host ordering) ---
say "bringing up $N channel(s)"
bash "$PROJ/tools/chan/chan-up.sh" "$N" >/tmp/net-chan-up-chan.log 2>&1 \
    || { tail -5 /tmp/net-chan-up-chan.log >&2; die "chan-up failed"; }

# --- anything already squatting channel 0 must go -----------------------------
# guest-echocli from a test run would hold the accept slot and PPP would never
# connect. The daemon serves one client at a time by design.
say "clearing channel $CH"
expect <<EOF >/dev/null 2>&1
log_user 0
set timeout 40
spawn telnet $GUEST 23
expect "login:" { send "root\r" }
expect -re {# \$}
send "pkill -9 guest-echocli; pkill -9 pppd; sleep 1; echo CLEARED\r"
expect -re {# \$}
send "exit\r"
expect eof
EOF
pkill -f 'socat.*niag0' 2>/dev/null
pkill -f 'pppd .*10.0.5.1' 2>/dev/null
sleep 1

# --- guest pppd on the channel ------------------------------------------------
say "starting guest pppd on channel $CH"
expect <<EOF >/dev/null 2>&1
log_user 0
set timeout 60
spawn telnet $GUEST 23
expect "login:" { send "root\r" }
expect -re {# \$}
send "cp /share/chan/guest-ppp-chan.pl /opt/niag/bin/ 2>/dev/null; nohup perl /opt/niag/bin/guest-ppp-chan.pl $CH $GUEST_IP:$HOST_IP > /tmp/gppp-wrap.log 2>&1 &\r"
expect -re {# \$}
send "sleep 2; echo STARTED\r"
expect -re {# \$}
send "exit\r"
expect eof
EOF

# --- host pppd on the other end ----------------------------------------------
# socat hands the socket to pppd as fd 0/1, which is what `notty` wants.
say "attaching host pppd"
nohup socat "UNIX-CONNECT:/run/niag$CH" \
    "EXEC:'/usr/sbin/pppd notty noauth local noccp nodeflate nobsdcomp novj asyncmap 0xffffffff $HOST_IP:$GUEST_IP nodetach',nofork" \
    > /tmp/net-chan-pppd.log 2>&1 &
sleep 6

# --- NAT so the guest can reach the world ------------------------------------
WAN=$(ip route show default | awk '/default/{print $5; exit}')
sysctl -w net.ipv4.ip_forward=1 >/dev/null
if [[ -n "${WAN:-}" ]]; then
    iptables -t nat -C POSTROUTING -s "$GUEST_IP/32" -o "$WAN" -j MASQUERADE 2>/dev/null \
        || iptables -t nat -A POSTROUTING -s "$GUEST_IP/32" -o "$WAN" -j MASQUERADE
    iptables -C FORWARD -i ppp0 -o "$WAN" -j ACCEPT 2>/dev/null \
        || iptables -I FORWARD -i ppp0 -o "$WAN" -j ACCEPT
    iptables -C FORWARD -i "$WAN" -o ppp0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
        || iptables -I FORWARD -i "$WAN" -o ppp0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    say "NAT via $WAN"
fi

# --- verify, rather than announce --------------------------------------------
say "verifying"
ok=0
for i in $(seq 30); do
    if ping -c1 -W2 "$GUEST_IP" >/dev/null 2>&1; then ok=1; break; fi
    sleep 2
done
(( ok )) || { tail -12 /tmp/net-chan-pppd.log >&2; die "no ping to $GUEST_IP"; }
say "ping OK"

tel=0
for i in $(seq 15); do
    if timeout 3 bash -c "echo > /dev/tcp/$GUEST_IP/23" 2>/dev/null; then tel=1; break; fi
    sleep 2
done

cat <<EOF

  READY.  IP is on channel $CH; the console was never touched.

    telnet $GUEST_IP        (root, no password)   telnet reachable: $tel
    channels 1..$((N-1)) are free for other use

    status:  sudo python3 tools/chan/host-chan.py status
    down:    sudo bash tools/chan/net-chan-down.sh
    logs:    /tmp/net-chan-pppd.log   guest /tmp/gppp-chan$CH.log
EOF
