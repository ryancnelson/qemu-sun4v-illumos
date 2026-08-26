#!/usr/bin/env bash
# safe-console.sh -- the ONLY interactive guest console to use once the guest
# is up. Do not type into the QEMU -nographic pane after boot.
#
#   bash tools/openindiana/safe-console.sh <tmux-session> [window-name]
#
# WHY THIS EXISTS (read this before ever touching the QEMU pane again).
#
# QEMU's -nographic pane is literally the QEMU PROCESS's own stdin/stdout.
# Every terminal signal sent into that pane -- Ctrl-C, Ctrl-D, a shell
# built-in like `wait` that blocks and then gets interrupted -- lands on QEMU
# ITSELF, not on a shell inside the guest. This has killed a live guest THREE
# times in this project's history:
#   - OPENINDIANA-PERFORMANCE-NOTEBOOK.md 2026-08-25: "Sending Ctrl-C through
#     QEMU's -nographic terminal terminated QEMU itself, so the resulting pool
#     was not cleanly exported."
#   - CURRENT-STATE.md "Single-console ownership": "Ctrl-C and Ctrl-D have
#     previously killed shells and logged out root sessions ... never an abort
#     mechanism."
#   - repeated again during the 2026-08-25 recovery session, corrupting the
#     already-unclean install-6g.patched-8ad4fe2e.iso a second time.
#
# The project's own channel-1 design exists SPECIFICALLY to prevent this:
# terminal signals sent into a channel stay inside the GUEST pty and cannot
# reach QEMU. This script opens exactly that connection, in its own tmux
# window, so you have a real, separately interruptible shell into the guest.
#
# HARD RULE: after this script's window exists and channel 1 answers, the
# QEMU -nographic pane becomes WRITE-ONCE (boot commands only, at the OBP/
# single-user prompt, before guest services start). Never send it Ctrl-C,
# Ctrl-D, or a signal-sensitive shell builtin again for the rest of that boot.
set -uo pipefail

SESSION="${1:?usage: safe-console.sh <tmux-session> [window-name]}"
WINDOW="${2:-channel1}"
SOCK="${NIAG_CHAN1_SOCK:-/run/niag1}"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "ERROR: tmux session '$SESSION' does not exist" >&2
    exit 1
fi

if [[ ! -S "$SOCK" ]]; then
    echo "ERROR: $SOCK does not exist yet -- host bridge for channel 1 is not up." >&2
    echo "       Bring up channels first (tools/chan/host-up.sh or chan-up.sh)." >&2
    exit 1
fi

if tmux list-windows -t "$SESSION" -F '#{window_name}' | grep -qx "$WINDOW"; then
    echo "window '$WINDOW' already exists in session '$SESSION' -- reusing it."
    echo "attach with: tmux attach -t $SESSION:$WINDOW"
else
    tmux new-window -t "$SESSION" -n "$WINDOW"
    # socat -,raw,echo=0: raw mode passes Ctrl-C/Ctrl-D through to the GUEST
    # pty untouched by the local tty driver, and it is a completely separate
    # process from QEMU -- killing this socat, or this whole tmux window,
    # cannot touch the QEMU process or the guest's execution state at all.
    tmux send-keys -t "$SESSION:$WINDOW" \
        "socat -,raw,echo=0 UNIX-CONNECT:$SOCK" Enter
    echo "opened channel-1 safe console in $SESSION:$WINDOW"
fi

cat <<'EOF'

This is now your interactive guest shell. It is safe to Ctrl-C here.
Verify it is really talking to the guest, not a dead socket:

    <blank line, then> id ; uname -a

If you see nothing, the guest has not started its channel-1 service yet
(guest-start.sh start / S99niagara start), or the guest has not booted far
enough to run it.
EOF
