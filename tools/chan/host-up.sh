#!/usr/bin/env bash
# Bring up the HOST side of the P2-014 channels and PPP. IDEMPOTENT: safe to re-run,
# and re-running is the supported way to recover after the guest reboots.
#
# WHY THIS EXISTS. The guest side is already fully automatic -- S98niagchan starts the
# channel daemons and S99niagppp starts pppd, both verified running after a cold boot.
# Only the host side needed hand-driving, and driving it by hand leaked processes:
# measured 3 bridge processes PER CHANNEL and 5 pppd, because 'pkill -f host-chan.py'
# does not reliably match a setsid'd child, and every "restart" added more.
#
# THAT LEAK IS NOT COSMETIC. The channel design rests on a SINGLE WRITER per control
# block. Multiple bridges on one channel corrupt the sequence handshake, and the
# visible symptom is exactly "PPP does not come up after a reboot" -- which is what
# sent me looking for a stale-sequence bug that was never there.
#
# So this script kills by PID, VERIFIES the kills landed, then starts exactly one
# process per role and verifies that too. It reports measured state, never intent.
set -uo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHANNELS="${CHANNELS:-0 1 2}"
GUEST_IP="${GUEST_IP:-10.0.5.15}"
# On a host without ZFS, point the bridges at the image directly. host-chan.py
# otherwise resolves it through a ZFS dataset name and dies with
#   cannot resolve image: ERROR: no such ZFS filesystem: datapool/niagara/images
# Remember sudo strips the environment, so this needs -E:
#   sudo -nE env NIAGARA_IMG=$HOME/sun4v/images/primary.img bash tools/chan/host-up.sh
export NIAGARA_IMG="${NIAGARA_IMG:-}"
# Logs go to a ROOT-OWNED dir, never /tmp. With fs.protected_regular set, root cannot
# O_CREAT over a file owned by another user inside a sticky world-writable directory,
# so 'sudo ... > /tmp/br0.log' fails with EACCES once a non-root run has created it.
LOGDIR=/var/tmp/niag
HOST_IP="${HOST_IP:-10.0.5.1}"

if [[ $EUID -ne 0 ]]; then echo "run with sudo" >&2; exit 1; fi
mkdir -p "$LOGDIR"

# Match only the REAL worker processes, never the sudo/setsid wrappers -- counting
# wrappers is how I previously concluded "two bridges competing" when there was one.
real_pids() {
    ps -eo pid,args --no-headers | grep -- "$1" \
        | grep -v -e 'sudo ' -e 'setsid ' -e grep \
        | awk '{print $1}'
}

kill_verified() {
    local pat=$1 label=$2 pids
    pids=$(real_pids "$pat" | tr '\n' ' ')
    [[ -z "${pids// /}" ]] && { echo "  $label: none running"; return 0; }
    kill -TERM $pids 2>/dev/null
    for _ in {1..20}; do
        [[ -z "$(real_pids "$pat")" ]] && break
        sleep 0.5
    done
    pids=$(real_pids "$pat" | tr '\n' ' ')
    if [[ -n "${pids// /}" ]]; then
        kill -9 $pids 2>/dev/null; sleep 1
    fi
    # Assert, do not assume. A kill that silently failed is the bug this guards.
    if [[ -n "$(real_pids "$pat")" ]]; then
        echo "  $label: STILL RUNNING after SIGKILL -- refusing to add more writers" >&2
        return 1
    fi
    echo "  $label: stopped"
}

echo "=== stopping host side ==="
kill_verified 'pppd notty'                 'pppd'    || exit 1
kill_verified 'UNIX-CONNECT:/run/niag0'    'socat'   || exit 1
kill_verified 'host-chan.py bridge'        'bridges' || exit 1

echo "=== starting one bridge per channel ==="
for c in $CHANNELS; do
    setsid nohup python3 "$PROJ/tools/chan/host-chan.py" bridge "$c" \
        > "$LOGDIR/br$c.log" 2>&1 < /dev/null &
done
sleep 4

fail=0
for c in $CHANNELS; do
    n=$(real_pids "host-chan.py bridge $c" | wc -l)
    [[ -S "/run/niag$c" ]] && sock=ok || sock=MISSING
    printf "  ch%s: %d writer(s), socket %s\n" "$c" "$n" "$sock"
    [[ "$n" -eq 1 && "$sock" == ok ]] || fail=1
done
[[ $fail -eq 0 ]] || { echo "  ABORT: channel state wrong, not starting PPP" >&2; exit 1; }

echo "=== starting PPP on channel 0 ==="
# noccp/nodeflate/nobsdcomp/novj: Solaris sppp implements none of them and logs
# 'sppp: unknown protocol 0xfd' (CCP) for every offer, wasting round trips.
setsid nohup socat UNIX-CONNECT:/run/niag0 \
    "EXEC:'/usr/sbin/pppd notty noauth local noccp nodeflate nobsdcomp novj persist maxfail 0 asyncmap 0xffffffff ${HOST_IP}:${GUEST_IP} nodetach',nofork" \
    > "$LOGDIR/pppd0.log" 2>&1 < /dev/null &

# NAT, so the guest can reach the internet and not just the host. Without these two
# the guest pings 10.0.5.1 fine and 8.8.8.8 not at all, which reads as a PPP fault
# and is not one. Measured on a fresh host: ip_forward=0, zero MASQUERADE rules.
if [[ "${NIAGARA_NAT:-1}" == "1" ]]; then
    WAN="$(ip route show default | awk '{print $5}' | head -1)"
    if [[ -n "$WAN" ]]; then
        sysctl -qw net.ipv4.ip_forward=1
        iptables -t nat -C POSTROUTING -s "$GUEST_IP/32" -o "$WAN" -j MASQUERADE 2>/dev/null \
            || iptables -t nat -A POSTROUTING -s "$GUEST_IP/32" -o "$WAN" -j MASQUERADE
        echo "  nat: $GUEST_IP -> $WAN (masquerade)"
    else
        echo "  nat: SKIPPED, no default route on this host" >&2
    fi
fi

echo "=== waiting for the link ==="
for i in {1..20}; do
    if ping -c1 -W2 "$GUEST_IP" > /dev/null 2>&1; then
        rtt=$(ping -c2 -W2 "$GUEST_IP" 2>/dev/null | tail -1 | sed 's/.*= //')
        echo "  guest reachable after ${i}0s  rtt $rtt"
        echo "  pppd writers: $(real_pids 'pppd notty' | wc -l)"
        exit 0
    fi
    sleep 10
done
echo "  FAILED: no ping after 200s; see $LOGDIR/pppd0.log and $LOGDIR/br0.log" >&2
exit 1
