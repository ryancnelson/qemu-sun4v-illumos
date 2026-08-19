#!/usr/bin/env bash
# Tear down IP-over-channel started by net-chan-up.sh.
#   sudo bash tools/chan/net-chan-down.sh [--keep-channels]
set -uo pipefail
PROJ="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

echo "==> stopping host pppd / socat"
pkill -f 'socat.*niag0' 2>/dev/null
pkill -f 'pppd notty.*10.0.5.1' 2>/dev/null
sleep 1
if [[ "${1:-}" != "--keep-channels" ]]; then
    bash "$PROJ/tools/chan/chan-down.sh"
else
    echo "==> channels left running"
fi
echo "==> down. Note the guest's rc scripts restart both on its next boot."
