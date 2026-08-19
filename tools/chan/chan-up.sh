#!/usr/bin/env bash
# Bring the P2-014 channel set up: host bridges + guest daemons.
#
#   sudo bash tools/chan/chan-up.sh [nchan]      default 4
#   sudo bash tools/chan/chan-down.sh
#
# Sockets afterwards:  host /run/niag<N>   guest /tmp/niag<N>
#
# ORDER IS LOAD-BEARING and this script exists mostly to enforce it:
#   1. stop every daemon on both sides
#   2. THEN init the control blocks
#   3. THEN start the guest daemons
#   4. THEN start the host bridges
# Initialising underneath a running daemon leaves it holding a stale seq, and the
# peer replays a leftover frame as new -- measured once as a 262144-byte transfer
# returning 274176 bytes. See chan.h.
#
# WHY NOT 16 BY DEFAULT: each guest daemon polls its control block, and the raw
# disk path measures ~4000 single-block reads/sec total. Idle backoff (20ms ->
# 400ms) makes idle channels nearly free, but there is no reason to start more
# than you use. Pass 16 if you want all of them.

set -uo pipefail

PROJ="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
N="${1:-4}"
GUEST="${CHAN_GUEST:-10.0.5.15}"
GBIN="${CHAN_GUEST_BIN:-/opt/niag/bin}"

say() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo (needs the image and /run)"
(( N >= 1 && N <= 16 )) || die "nchan must be 1..16"
command -v expect >/dev/null || die "expect not installed"

# --- 1. stop everything ------------------------------------------------------
say "stopping host bridges"
pkill -f 'host-chan.py bridge' 2>/dev/null
sleep 1

say "stopping guest daemons"
expect <<EOF >/dev/null 2>&1
log_user 0
set timeout 40
spawn telnet $GUEST 23
expect "login:" { send "root\r" }
expect -re {# \$}
send "pkill -9 guest-chand; sleep 1; echo STOPPED\r"
expect -re {# \$}
send "exit\r"
expect eof
EOF

# --- 2. init AFTER stopping --------------------------------------------------
say "initialising $N channel(s)"
python3 "$PROJ/tools/chan/host-chan.py" init || die "init failed"

# --- 3. guest daemons --------------------------------------------------------
say "starting guest daemons ch0..$((N-1))"
expect <<EOF
log_user 0
set timeout 90
spawn telnet $GUEST 23
expect "login:" { send "root\r" }
expect -re {# \$}
send "test -x $GBIN/guest-chand || echo MISSING_BINARY\r"
expect -re {# \$}
# One send per channel: \$(...) inside a Tcl string is parsed by TCL, not the
# shell, and "\$(seq 0 3)" fails with: can't read "(seq 0 3)": no such variable.
for {set c 0} {\$c < $N} {incr c} {
    send "nohup $GBIN/guest-chand \$c > /var/tmp/chand\$c.log 2>&1 &\r"
    expect -re {# \$}
}
send "sleep 3; ls /tmp/niag* 2>/dev/null | wc -l\r"
expect -re {# \$}
send "exit\r"
expect eof
EOF

# --- 4. host bridges ---------------------------------------------------------
say "starting host bridges"
for ((c = 0; c < N; c++)); do
    nohup python3 "$PROJ/tools/chan/host-chan.py" bridge "$c" \
        > "/tmp/niag-bridge$c.log" 2>&1 &
done
sleep 3

up=0
for ((c = 0; c < N; c++)); do [[ -S "/run/niag$c" ]] && ((up++)); done
say "host sockets up: $up/$N"
(( up == N )) || die "not all bridges came up; see /tmp/niag-bridge*.log"

# Verify the GUEST side too. An earlier version checked only host sockets and
# printed READY while zero guest daemons were running, because the command that
# started them had failed inside expect.
gup=$(expect <<EOF 2>/dev/null | tr -dc '0-9'
log_user 0
set timeout 30
spawn telnet $GUEST 23
expect "login:" { send "root\r" }
expect -re {# \$}
send "ls -d /tmp/niag* 2>/dev/null | wc -l\r"
expect -re {(\\d+)\s*\r\n[^\r\n]*# \$} { puts \$expect_out(1,string) }
send "exit\r"
expect eof
EOF
)
say "guest sockets up: ${gup:-0}/$N"
[[ "${gup:-0}" == "$N" ]] || die "guest daemons did not all start; check /var/tmp/chand*.log in the guest"

cat <<EOF

  READY.  $N channel(s).

    host   /run/niag0 .. /run/niag$((N-1))
    guest  /tmp/niag0 .. /tmp/niag$((N-1))

    status:  sudo python3 tools/chan/host-chan.py status
    test:    sudo python3 tools/chan/chan-test.py 0
    down:    sudo bash tools/chan/chan-down.sh

  A guest client must CONNECT before a channel carries anything -- the daemon
  waits in accept(). Channels with no client are idle, not broken.
EOF
