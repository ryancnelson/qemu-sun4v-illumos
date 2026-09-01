#!/usr/bin/bash

set -euo pipefail

QEMU=/tink/builds/qemu-sun4v-879fee-tribblix/build/qemu-system-sparc64
LATEST=/tink/runs/oi-basecamp-latest
RUNNER=/root/run-sun4v.sh
SESSION=oi-basecamp

qemu_pid()
{
    [[ -f "$LATEST/qemu.pid" ]] || return 0
    pid=$(cat "$LATEST/qemu.pid")
    case $pid in
        ''|*[!0-9]*) return 0 ;;
    esac
    if kill -0 "$pid" 2>/dev/null; then
        echo "$pid"
    fi
}

qmp()
{
    command=$1
    arguments=${2:-}
    [[ -S "$LATEST/qmp.sock" ]] || {
        echo '{"ok":false,"error":"qmp_unavailable"}'
        exit 1
    }
    if [[ -n "$arguments" ]]; then
        request="{\"execute\":\"$command\",\"arguments\":$arguments}"
    else
        request="{\"execute\":\"$command\"}"
    fi
    printf '%s\n%s\n' '{"execute":"qmp_capabilities"}' "$request" |
        /usr/bin/socat - "UNIX-CONNECT:$LATEST/qmp.sock"
}

case ${1:-status} in
status)
    pid=$(qemu_pid)
    if [[ -n "$pid" ]]; then
        metrics=$(/usr/bin/ps -o etime,pcpu,pmem,rss,vsz -p "$pid" | tail -1)
        set -- $metrics
        printf '{"ok":true,"running":true,"pid":%s,"run":"%s","elapsed":"%s","cpu_percent":%s,"memory_percent":%s,"rss_kib":%s,"vsz_kib":%s}\n' \
            "$pid" "$(readlink -f "$LATEST")" "$1" "$2" "$3" "$4" "$5"
    else
        printf '{"ok":true,"running":false,"run":"%s"}\n' "$(readlink -f "$LATEST" 2>/dev/null || true)"
    fi
    ;;
break)
    qmp chardev-send-break '{"id":"guestconsole"}'
    ;;
reset)
    qmp system_reset
    ;;
powerdown)
    qmp system_powerdown
    ;;
stop)
    qmp quit
    ;;
start)
    [[ -z "$(qemu_pid)" ]] || {
        echo '{"ok":false,"error":"already_running"}'
        exit 1
    }
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        tmux kill-session -t "$SESSION"
    fi
    tmux new-session -d -s "$SESSION" "$RUNNER"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pid=$(qemu_pid)
        if [[ -n "$pid" ]]; then
            printf '{"ok":true,"running":true,"pid":%s}\n' "$pid"
            exit 0
        fi
        sleep 1
    done
    echo '{"ok":false,"error":"start_timeout"}'
    exit 1
    ;;
*)
    echo "usage: $0 {status|break|reset|powerdown|stop|start}" >&2
    exit 2
    ;;
esac
