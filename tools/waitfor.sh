#!/usr/bin/env bash
# Poll a log file until a marker appears. Returns the moment it does.
#
#   tools/waitfor.sh <logfile> <done-regex> [timeout_s] [fail-regex]
#
# Exit: 0 = done-regex matched   2 = fail-regex matched   1 = timed out
#
# Replaces `sleep 240 && tail log`, which wastes real time when the job
# finishes in 40s and lies to you when it needs 400s. Poll, don't guess.
#
# Typical use with a VM run:
#   sudo expect /tmp/x.exp 2>&1 | tee /tmp/x.log &
#   tools/waitfor.sh /tmp/x.log 'vdisk writeback complete' 1800 'PANICKED|BOOT TIMEOUT'
#
# "vdisk writeback complete" is emitted by the patched QEMU as its very last
# action on a clean exit, so it is a reliable end-of-run marker.

set -uo pipefail

LOG="${1:?usage: waitfor.sh <logfile> <done-regex> [timeout_s] [fail-regex]}"
DONE_RE="${2:?need a done regex}"
TIMEOUT="${3:-1800}"
FAIL_RE="${4:-}"
INTERVAL="${WAITFOR_INTERVAL:-2}"

start=$(date +%s)
last_size=0

while :; do
    now=$(date +%s); elapsed=$(( now - start ))

    if [[ -f "$LOG" ]]; then
        # strip CRs: the serial console emits \r\n and breaks naive matching
        if tr -d '\r' < "$LOG" | grep -aqE "$DONE_RE"; then
            echo "waitfor: matched '$DONE_RE' after ${elapsed}s"
            exit 0
        fi
        if [[ -n "$FAIL_RE" ]] && tr -d '\r' < "$LOG" | grep -aqE "$FAIL_RE"; then
            echo "waitfor: FAILURE marker '$FAIL_RE' after ${elapsed}s"
            exit 2
        fi
        # progress: show growth so a long run does not look hung
        size=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
        if (( size != last_size )); then
            printf '\rwaitfor: %ds, %d bytes...' "$elapsed" "$size" >&2
            last_size=$size
        fi
    fi

    if (( elapsed >= TIMEOUT )); then
        echo
        echo "waitfor: TIMEOUT after ${elapsed}s waiting for '$DONE_RE'"
        exit 1
    fi
    sleep "$INTERVAL"
done
