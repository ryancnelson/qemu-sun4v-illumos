#!/usr/bin/env bash
set -u

if (( $# < 3 || $# > 4 )); then
    echo "usage: $0 QEMU_PID MONITOR_SOCKET CONSOLE_LOG [INTERVAL_SECONDS]" >&2
    exit 2
fi

pid=$1
monitor=$2
console_log=$3
interval=${4:-15}

while kill -0 "$pid" 2>/dev/null; do
    now=$(date -Ins)
    process=$(ps -p "$pid" -o etimes=,%cpu=,rss=,stat= | xargs)
    io=$(awk '
        /rchar:/ { rchar=$2 }
        /wchar:/ { wchar=$2 }
        /read_bytes:/ { rb=$2 }
        /write_bytes:/ { wb=$2 }
        END { printf "rchar=%s wchar=%s read_bytes=%s write_bytes=%s",
                     rchar, wchar, rb, wb }
    ' "/proc/$pid/io")
    log_state=$(stat -c 'console_bytes=%s console_mtime=%Y' "$console_log" 2>/dev/null ||
        echo 'console_bytes=missing console_mtime=missing')

    echo "[$now] pid=$pid $process $io $log_state"

    for task in /proc/"$pid"/task/*; do
        tid=${task##*/}
        awk -v tid="$tid" '{
            printf "  thread=%s name=%s utime=%s stime=%s state=%s cpu=%s\n",
                   tid, $2, $14, $15, $3, $39
        }' "$task/stat"
    done

    if [[ -S "$monitor" ]]; then
        printf 'cpu 0\ninfo registers\ncpu 1\ninfo registers\n' |
            socat - "UNIX-CONNECT:$monitor" 2>/dev/null |
            sed $'s/\033\\[[0-9;?]*[ -\/]*[@-~]//g' |
            grep -E 'CPU#|cpu:[01] pc:|^pc:' |
            sed 's/^/  /'
    else
        echo "  monitor_socket=missing"
    fi

    sleep "$interval"
done

echo "[$(date -Ins)] pid=$pid exited"
