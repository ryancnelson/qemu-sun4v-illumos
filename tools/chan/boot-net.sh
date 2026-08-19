#!/usr/bin/env bash
# Boot the VM with IP on channel 0 and the console LEFT ALONE.
#
#   sudo bash tools/chan/boot-net.sh [nchan]      default 4
#   telnet 10.0.5.15                              <- root, no password
#   sudo bash tools/chan/net-chan-down.sh
#
# This is the whole thing in one command: init, boot, attach, verify.
#
# ORDER, and every step of it is load-bearing:
#
#   1. init the channel region WHILE THE VM IS DOWN.
#      The guest's rc scripts start their daemons during boot, long before a host
#      script could intervene, and a daemon that starts against a stale region
#      adopts a stale seq -- the peer then replays a leftover frame as new
#      (measured: 262144 bytes returning 274176). Initialising while the VM is
#      down is the only way to guarantee both sides start from zero. It works
#      because since P2-012 the region is just bytes in a regular file.
#
#   2. boot QEMU with the console on a socket and NOTHING attached to it.
#      This is the point of the exercise: pppd used to own /dev/console, so
#      networking and interactive use were mutually exclusive and `init 5`
#      afterwards landed in a broken OBP.
#
#   3. the GUEST starts itself: S98niagchan brings up guest-chand for each
#      channel, S99niagppp starts pppd on channel 0. pppd's socket connect RETRIES,
#      so it does not matter that the host bridge does not exist yet.
#
#   4. host attaches: one bridge per channel, then pppd on channel 0 via socat,
#      then NAT.
#
# NOT slirp in QEMU's sense -- this machine has no NIC to attach slirp to, so the
# userspace-NAT role is host pppd + iptables MASQUERADE. Same effect: the guest
# reaches the world with no tap device.

set -uo pipefail

PROJ="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
source "$PROJ/tools/lib/image.sh"

N="${1:-4}"
CH=0
GUEST_IP=10.0.5.15
HOST_IP=10.0.5.1
DS="${NIAGARA_IMAGES:-datapool/niagara/images}"
QEMU="${QEMU_BIN:-$PROJ/qemu/build/qemu-system-sparc64}"
S10DIR="${S10DIR:-/datapool/niagara/base-1gib}"
MEM="${NIAGARA_MEM:-1024}"
CONSOLE=/tmp/niag-console.sock

say() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo"
[[ -x "$QEMU" ]] || die "no qemu at $QEMU"
command -v socat >/dev/null || die "socat required on the host"
(( N >= 1 && N <= 16 )) || die "nchan must be 1..16"

IMG=$(img_require "$DS") || exit 1

# --- 0. clear any previous run ------------------------------------------------
say "clearing previous state"
pkill -f 'host-chan.py bridge' 2>/dev/null
pkill -f "socat.*niag$CH" 2>/dev/null
pkill -f "pppd notty.*$HOST_IP" 2>/dev/null
if pgrep -f "$(basename "$IMG")" >/dev/null; then
    die "a VM is already running on $IMG; stop it first (net-chan-down.sh, then halt it)"
fi
rm -f "$CONSOLE"
sleep 1

# --- 1. init the region while nothing is mapped it ----------------------------
say "initialising $N channel(s) with the VM DOWN"
python3 "$PROJ/tools/chan/host-chan.py" init || die "init failed"

# --- 2. boot, console on a socket, unattached --------------------------------
say "booting (console on $CONSOLE, nothing attached to it)"
"$QEMU" -M niagara -L "$S10DIR" -m "$MEM" -nographic \
        -serial "unix:$CONSOLE,server,nowait" \
        -monitor "unix:/tmp/niag-mon.sock,server,nowait" \
        -drive "if=pflash,file=$IMG,format=raw" \
        > /tmp/niag-qemu.log 2>&1 &
for i in $(seq 40); do [[ -S "$CONSOLE" ]] && break; sleep 0.5; done
[[ -S "$CONSOLE" ]] || die "QEMU never created $CONSOLE (see /tmp/niag-qemu.log)"

say "telling OBP to boot"
socat -T5 - "UNIX-CONNECT:$CONSOLE" <<< "boot disk" > /tmp/niag-boot.log 2>&1 &
sleep 2

# --- 3. wait for the guest to reach the point where its rc scripts have run ---
say "waiting for the guest to bring up its channel daemons (~2 min)"
booted=0
for i in $(seq 90); do
    if grep -aq 'console login:' /tmp/niag-boot.log 2>/dev/null; then booted=1; break; fi
    sleep 2
done
(( booted )) || say "WARNING: never saw a login prompt; continuing anyway"

# --- 4. host side ------------------------------------------------------------
say "starting $N host bridge(s)"
for ((c = 0; c < N; c++)); do
    nohup python3 "$PROJ/tools/chan/host-chan.py" bridge "$c" \
        > "/tmp/niag-bridge$c.log" 2>&1 &
done
sleep 3
up=0; for ((c = 0; c < N; c++)); do [[ -S "/run/niag$c" ]] && ((up++)); done
say "host sockets: $up/$N"

say "attaching host pppd to channel $CH"
nohup socat "UNIX-CONNECT:/run/niag$CH" \
    "EXEC:'/usr/sbin/pppd notty noauth local noccp nodeflate nobsdcomp novj asyncmap 0xffffffff $HOST_IP:$GUEST_IP nodetach',nofork" \
    > /tmp/niag-pppd.log 2>&1 &

WAN=$(ip route show default | awk '/default/{print $5; exit}')
sysctl -w net.ipv4.ip_forward=1 >/dev/null
if [[ -n "${WAN:-}" ]]; then
    iptables -t nat -C POSTROUTING -s "$GUEST_IP/32" -o "$WAN" -j MASQUERADE 2>/dev/null \
        || iptables -t nat -A POSTROUTING -s "$GUEST_IP/32" -o "$WAN" -j MASQUERADE
    iptables -C FORWARD -i ppp0 -o "$WAN" -j ACCEPT 2>/dev/null \
        || iptables -I FORWARD -i ppp0 -o "$WAN" -j ACCEPT
    iptables -C FORWARD -i "$WAN" -o ppp0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
        || iptables -I FORWARD -i "$WAN" -o ppp0 -m state --state RELATED,ESTABLISHED -j ACCEPT
fi

# --- 5. verify rather than announce -----------------------------------------
say "verifying"
ok=0
for i in $(seq 45); do
    ping -c1 -W2 "$GUEST_IP" >/dev/null 2>&1 && { ok=1; break; }
    sleep 2
done
if (( ! ok )); then
    echo "--- host pppd ---"; tail -8 /tmp/niag-pppd.log 2>/dev/null
    echo "--- boot tail ---";  tail -8 /tmp/niag-boot.log 2>/dev/null | tr -d '\r'
    die "no ping to $GUEST_IP"
fi
say "ping OK"

tel=no
for i in $(seq 15); do
    timeout 3 bash -c "echo > /dev/tcp/$GUEST_IP/23" 2>/dev/null && { tel=yes; break; }
    sleep 2
done

cat <<EOF

  READY.  IP is on channel $CH. The console was never attached to anything.

    telnet $GUEST_IP        (root, no password)      reachable: $tel
    console  socat - UNIX-CONNECT:$CONSOLE           (free, yours)
    monitor  socat - UNIX-CONNECT:/tmp/niag-mon.sock
    channels 1..$((N-1)) free for other use

    status:  sudo python3 tools/chan/host-chan.py status
    down:    sudo bash tools/chan/net-chan-down.sh
    logs:    /tmp/niag-{qemu,boot,pppd,bridge*}.log
EOF
