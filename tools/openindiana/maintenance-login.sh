#!/usr/bin/env bash
# Deterministic OpenIndiana live-media maintenance login.
#
# This is deliberately a tiny state machine, not an expect-like retry loop.
# It sends exactly two lines (root/root), once each, and only after recognizing
# the corresponding prompt. Any surprise revokes input authority and fails.
set -euo pipefail

TARGET=${1:?usage: maintenance-login.sh tmux-target [audit-log]}
AUDIT=${2:-/tmp/openindiana-maintenance-login.log}
SESSION=${TARGET%%:*}

stamp() {
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$AUDIT"
}

fail() {
    stamp "FAIL $*; no further console input sent"
    exit 1
}

# A human with a writable client owns the console. Detached panes and read-only
# observers do not count as writers.
writers=$(tmux list-clients -F '#{client_session} #{client_readonly}' 2>/dev/null \
    | awk -v session="$SESSION" '$1 == session && $2 == 0 { n++ } END { print n+0 }')
(( writers == 0 )) || fail "$writers writable tmux client(s) attached to $SESSION"

pane_tail() {
    tmux capture-pane -t "$TARGET" -p -J -S -30 \
        | tr -d '\r' | tail -n 12
}

current_line() {
    pane_tail | awk 'NF { line=$0 } END { print line }'
}

wait_for() {
    local pattern=$1 timeout=${2:-60} start=$SECONDS
    while (( SECONDS - start < timeout )); do
        current_line | grep -Fq "$pattern" && return 0
        sleep 1
    done
    return 1
}

USER_PROMPT='Enter user name for system maintenance (control-d to bypass):'
PASS_PROMPT='Enter root password (control-d to bypass):'
SHELL_PROMPT='root@openindiana:~#'

if current_line | grep -Fq "$SHELL_PROMPT"; then
    stamp "PASS shell prompt already present; sent nothing"
    exit 0
fi

current_line | grep -Fq "$USER_PROMPT" \
    || fail "expected maintenance username prompt is not current"
stamp "STATE username prompt recognized; sending root once"
tmux send-keys -t "$TARGET" -l root
tmux send-keys -t "$TARGET" Enter

wait_for "$PASS_PROMPT" 60 \
    || fail "root password prompt did not appear after username"
stamp "STATE root password prompt recognized; sending root once"
tmux send-keys -t "$TARGET" -l root
tmux send-keys -t "$TARGET" Enter

wait_for "$SHELL_PROMPT" 120 \
    || fail "root shell prompt did not appear after password"
stamp "PASS root maintenance shell established"
