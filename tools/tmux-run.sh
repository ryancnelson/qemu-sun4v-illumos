#!/usr/bin/env bash
# Run a long command in a tmux window WITHOUT sending a long line to tmux.
#
#   tools/tmux-run.sh <session> <logfile> <command-string>
#
# WHY THIS EXISTS
#
# `tmux send-keys` drops characters out of the middle of a long literal string
# when the receiving shell cannot drain the pty fast enough. It is intermittent,
# it is silent, and the result is a MANGLED command rather than no command. It
# was observed as:
#
#   $ cd <repo root> && sudo QEMU_BIN=$PWD/qemu/build/qemu-system-sg
#   usage: sudo -h | -K | -k | -V
#
# i.e. "qemu-system-sparc64 VM_TRANSCRIPT=... bash tests/..." arrived as
# "qemu-system-sg", sudo got garbage, and the run died instantly. A caller
# polling a logfile for a completion marker then waits out its whole timeout on
# a command that never even started correctly.
#
# So: write the command to a script, and send only a SHORT line that runs it.
# Same class of bug as the Solaris console's 256-byte line limit — an input
# length cap that truncates silently instead of failing loudly. Keep every line
# handed to tmux short, always.
#
# The command still streams to the pane (plain `tee`, never `| tail`, which
# buffers until the pipeline ends and leaves a watching human staring at
# nothing).

set -euo pipefail

SESSION="${1:?usage: tmux-run.sh <session> <logfile> <command-string>}"
LOGFILE="${2:?need a logfile path}"
COMMAND="${3:?need a command string}"

RUNNER=$(mktemp /tmp/tmux-run-XXXXXX.sh)
cat > "$RUNNER" <<EOF
#!/usr/bin/env bash
cd $(printf '%q' "$PWD")
$COMMAND
echo "TMUX_RUN_EXIT=\$?"
EOF
chmod +x "$RUNNER"

: > "$LOGFILE"
chmod 666 "$LOGFILE" 2>/dev/null || true

# Short line only: "clear; bash /tmp/tmux-run-XXXXXX.sh 2>&1 | tee <log>".
# Keep it well under any plausible cap.
SEND="clear; bash $RUNNER 2>&1 | tee $LOGFILE"
if (( ${#SEND} > 180 )); then
    echo "WARNING: send line is ${#SEND} bytes; shorten \$LOGFILE" >&2
fi

if command -v sane-send-keys >/dev/null 2>&1; then
    sane-send-keys "$SESSION" "$SEND" Enter >/dev/null
else
    tmux send-keys -t "$SESSION" "$SEND" Enter
fi

echo "runner: $RUNNER"
echo "log:    $LOGFILE"
echo "sent ${#SEND} bytes to tmux session '$SESSION'"
