#!/usr/bin/env bash
# Poll a log file until a marker appears. Returns the moment it does.
#
#   tools/waitfor.sh <logfile> <done-regex> [timeout_s] [fail-regex]
#
# Exit: 0 = done-regex matched   1 = timed out   2 = fail-regex matched
#       3 = STALLED (log stopped growing and never matched)
#
# Replaces `sleep 240 && tail log`, which wastes real time when the job
# finishes in 40s and lies to you when it needs 400s. Poll, don't guess.
#
# STALL DETECTION is the important part. A wrong expect pattern, a dropped
# carriage return, or a guest that booted its console to the wrong device all
# produce the same signature: the log goes quiet and the marker NEVER arrives.
# Waiting out the full timeout for that is pure waste. If the log has not grown
# for WAITFOR_STALL seconds (default 45) and has not matched, that is a failure
# NOW -- report it and dump the tail so the cause is visible immediately.
#
# Tune with WAITFOR_STALL. Raise it only for steps with genuinely silent
# stretches (a long compile); do not raise it to paper over a bad pattern.
#
# Typical use with a VM run:
#   sudo expect /tmp/x.exp 2>&1 | tee /tmp/x.log &
#   tools/waitfor.sh /tmp/x.log 'vdisk writeback complete' 1800 'PANICKED'
#
# "vdisk writeback complete" is emitted by the patched QEMU as its very last
# action on a clean exit, so it is a reliable end-of-run marker.
#
# Two traps that make a live run look dead, both of which defeat this tool:
#   * expect buffers `puts` when stdout is a pipe. Put this at the top of every
#     expect script:  fconfigure stdout -buffering none
#   * `| tail -N` buffers until the pipeline ends, so a tmux pane stays blank.
#     Use plain `| tee log` when a human is watching.

set -uo pipefail

LOG="${1:?usage: waitfor.sh <logfile> <done-regex> [timeout_s] [fail-regex]}"
DONE_RE="${2:?need a done regex}"
TIMEOUT="${3:-1800}"
FAIL_RE="${4:-}"
INTERVAL="${WAITFOR_INTERVAL:-2}"
STALL="${WAITFOR_STALL:-45}"

start=$(date +%s)
last_size=0
last_change=$start

dump_tail() {
    echo "waitfor: last 15 lines of $LOG:" >&2
    tr -d '\r' < "$LOG" 2>/dev/null | grep -vE '^\s*$' | tail -15 | cut -c1-160 >&2
}

while :; do
    now=$(date +%s); elapsed=$(( now - start ))

    if [[ -f "$LOG" ]]; then
        # strip CRs: the serial console emits \r\n and breaks naive matching
        if tr -d '\r' < "$LOG" | grep -aqE "$DONE_RE"; then
            echo
            echo "waitfor: matched '$DONE_RE' after ${elapsed}s"
            exit 0
        fi
        if [[ -n "$FAIL_RE" ]] && tr -d '\r' < "$LOG" | grep -aqE "$FAIL_RE"; then
            echo
            echo "waitfor: FAILURE marker '$FAIL_RE' after ${elapsed}s"
            dump_tail
            exit 2
        fi

        size=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
        if (( size != last_size )); then
            printf '\rwaitfor: %ds, %d bytes...' "$elapsed" "$size" >&2
            last_size=$size
            last_change=$now
        elif (( now - last_change >= STALL )); then
            echo
            echo "waitfor: STALLED -- no output for $(( now - last_change ))s" \
                 "and '$DONE_RE' never matched (${elapsed}s elapsed)."
            echo "waitfor: this is a failure now; not waiting out the ${TIMEOUT}s timeout."
            dump_tail
            exit 3
        fi
    fi

    if (( elapsed >= TIMEOUT )); then
        echo
        echo "waitfor: TIMEOUT after ${elapsed}s waiting for '$DONE_RE'"
        dump_tail
        exit 1
    fi
    sleep "$INTERVAL"
done
