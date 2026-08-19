#!/usr/bin/env bash
# Stop the P2-014 channel set on both sides.
#   sudo bash tools/chan/chan-down.sh
set -uo pipefail
GUEST="${CHAN_GUEST:-10.0.5.15}"
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

echo "==> stopping host bridges"
pkill -f 'host-chan.py bridge' 2>/dev/null
sleep 1
for s in /run/niag*; do [[ -S "$s" ]] && rm -f "$s"; done

echo "==> stopping guest daemons"
expect <<XEOF >/dev/null 2>&1
log_user 0
set timeout 40
spawn telnet $GUEST 23
expect "login:" { send "root\r" }
expect -re {# \$}
send "pkill -9 guest-chand; pkill -9 guest-echocli; sleep 1; echo DONE\r"
expect -re {# \$}
send "exit\r"
expect eof
XEOF
echo "==> down. host bridges: $(pgrep -cf 'host-chan.py bridge' 2>/dev/null || echo 0)"
