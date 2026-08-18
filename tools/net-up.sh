#!/usr/bin/env bash
# Bring the Solaris guest up with networking and a telnet login.
#
#   sudo bash tools/net-up.sh
#   telnet 10.0.5.15        <- root, no password
#   sudo bash tools/net-down.sh
#
# Requires snapshot primary@networked (PPP installed, login policy set, scripts
# on the FAT slice). Takes ~3 minutes: the guest boots in ~60s and the PPP and
# telnet bring-up follows.
#
# WHY EACH PIECE IS SHAPED THIS WAY -- none of it is arbitrary:
#
#   * QEMU's console goes to a UNIX SOCKET, not stdio, because the host's pppd
#     needs a tty of its own to attach to.
#   * ONE persistent socat bridge converts that socket to a pty and must stay up
#     for the whole session; if it drops, the guest sees its console close and
#     pppd exits.
#   * The guest runs `pppd notty`, because /dev/console is the cn->qcn
#     pseudo-device and pppd cannot STREAMS-I_LINK it to the PPP mux
#     ("Can't link tty to PPP mux: Invalid argument").
#   * asyncmap 0xffffffff on BOTH ends: the console is not 8-bit clean, and with
#     no escaping anything carrying 0x11/0x13/0x0d gets mangled -- ICMP <=16B
#     replied while >=32B silently failed FCS.
#   * telnetd is served by a perl mini-inetd, because SMF's inetd sits `offline`
#     forever on an absent svc:/milestone/name-services.
#
# A PPP SESSION IS DISPOSABLE. `init 5` after PPP has run always ends in a broken
# OBP, so do not do work here you need to persist -- roll back to @networked.

set -uo pipefail

PROJ="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
ZVOL="${ZVOL:-datapool/niagara/vms/primary}"
DEV="/dev/zvol/$ZVOL"
QEMU="${QEMU_BIN:-$PROJ/qemu/build/qemu-system-sparc64}"
S10DIR="${S10DIR:-/datapool/niagara/base-1gib}"
MEM="${NIAGARA_MEM:-1024}"
SOCK=/tmp/sol-net.sock
# Monitor on a SOCKET, not stdio. Without this there is NO way to query or freeze
# a guest whose console has been handed to PPP -- which is exactly how a session
# was lost: pppd reported "Peer not responding", the console was unreachable, and
# `info status` / `stop` were impossible because the monitor was on stdio.
MON=/tmp/sol-mon.sock
PTY=/tmp/sol-console
GUEST_IP=10.0.5.15
HOST_IP=10.0.5.1

say() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo (needs the zvol, pppd and a pty)"
[[ -b "$DEV" ]] || die "no such zvol device: $DEV"
[[ -x "$QEMU" ]] || die "no qemu at $QEMU"

pgrep -f 'qemu-system-sparc64' >/dev/null && die "a VM is already running; run net-down.sh first"

rm -f "$SOCK" "$PTY" "$MON"

say "starting QEMU (console on $SOCK)"
"$QEMU" -M niagara -L "$S10DIR" -m "$MEM" -nographic \
    -serial "unix:$SOCK,server,nowait" \
    -monitor "unix:$MON,server,nowait" \
    -drive "if=pflash,file=$DEV,format=raw" > /tmp/sol-net-qemu.log 2>&1 &
QPID=$!
for _ in $(seq 40); do [[ -S "$SOCK" ]] && break; sleep 0.25; done
[[ -S "$SOCK" ]] || die "QEMU never created $SOCK (see /tmp/sol-net-qemu.log)"

say "bridging $SOCK -> $PTY"
socat -d -d "UNIX-CONNECT:$SOCK" "PTY,link=$PTY,raw,echo=0,mode=666" \
    > /tmp/sol-net-socat.log 2>&1 &
for _ in $(seq 40); do [[ -e "$PTY" ]] && break; sleep 0.25; done
[[ -e "$PTY" ]] || die "socat never created $PTY"

say "booting Solaris and starting PPP + telnetd in the guest (~2 min)"
expect -f - "$PTY" <<'EXPECT' > /tmp/sol-net-boot.log 2>&1
    fconfigure stdout -buffering none
    set pty [lindex $argv 0]
    set fh [open $pty w+]
    fconfigure $fh -translation binary
    spawn -open $fh
    send "\r"
    expect { -timeout 20 "ok" {} timeout { puts "NO_OBP"; exit 1 } }
    send "boot disk\r"
    expect {
        -timeout 240 "login:" {}
        "BAD TRAP" { puts "PANICKED"; exit 1 }
        timeout { puts "BOOT_TIMEOUT"; exit 1 }
    }
    send "root\r"
    expect { -timeout 30 "# " {} timeout { puts "NO_LOGIN"; exit 1 } }
    send "mkdir -p /x && mount -F pcfs /dev/dsk/c0t0d0s3:c /x\r"
    expect { -timeout 60 "# " {} timeout { puts "NO_MOUNT"; exit 1 } }
    send "cp /x/PPPGO3.SH /tmp/go.sh; cp /x/PPPWD.SH /tmp/wd.sh; chmod +x /tmp/*.sh\r"
    expect { -timeout 60 "# " {} timeout { puts "NO_COPY"; exit 1 } }
    send "sh /tmp/go.sh\r"
    sleep 20
    puts "HANDED_OFF"
    close
EXPECT
grep -q HANDED_OFF /tmp/sol-net-boot.log || { tail -5 /tmp/sol-net-boot.log; die "guest bring-up failed"; }

say "attaching host pppd"
pppd "$PTY" 115200 noauth nolock local nodetach debug novj noccp \
    asyncmap 0xffffffff "$HOST_IP:$GUEST_IP" > /tmp/sol-net-pppd.log 2>&1 &
for _ in $(seq 45); do
    grep -q 'remote IP address' /tmp/sol-net-pppd.log 2>/dev/null && break
    sleep 1
done
grep -q 'remote IP address' /tmp/sol-net-pppd.log || { tail -8 /tmp/sol-net-pppd.log; die "IPCP never completed"; }

say "verifying"
ping -c 3 -W 3 -s 500 "$GUEST_IP" >/dev/null 2>&1 \
    && say "ping OK (500B payload)" || say "WARNING: ping failed"
if timeout 5 bash -c "echo > /dev/tcp/$GUEST_IP/23" 2>/dev/null; then
    say "telnetd is listening on $GUEST_IP:23"
else
    say "WARNING: port 23 not answering yet; give it a few seconds"
fi

cat <<EOF

  READY.   telnet $GUEST_IP        (login: root, no password)

  logs:    /tmp/sol-net-{qemu,socat,boot,pppd}.log
  monitor: sudo socat - UNIX-CONNECT:$MON      (info status / stop / cont)
  down:    sudo bash $PROJ/tools/net-down.sh

  The guest watchdog kills pppd after 3600s (tools/guest-ppp-watchdog.sh).
  To KEEP work from this session:  sudo bash tools/checkpoint.sh [snapname]
  To discard it:                   sudo bash tools/net-down.sh --rollback
EOF
