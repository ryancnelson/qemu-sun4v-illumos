#!/usr/bin/env bash
# Own a socket-console QEMU in a separate session so terminal Ctrl-C cannot
# reach it. The caller must interact through QEMU's serial/monitor sockets.
set -euo pipefail

RUN_DIR=${1:?usage: qemu-owner.sh run-dir -- qemu-system-sparc64 args...}
shift
[[ ${1:-} == -- ]] || { echo "qemu-owner: missing --" >&2; exit 2; }
shift
(( $# > 0 )) || { echo "qemu-owner: missing QEMU command" >&2; exit 2; }

case ${1##*/} in
    qemu-system-sparc64|qemu-system-sparc64.*) ;;
    *) echo "qemu-owner: refusing non-QEMU command: $1" >&2; exit 2 ;;
esac

mkdir -p -- "$RUN_DIR"
LOG=$RUN_DIR/qemu.log
PIDFILE=$RUN_DIR/qemu.pid
OWNER_PIDFILE=$RUN_DIR/qemu-owner.pid
printf '%s\n' "$$" > "$OWNER_PIDFILE"

on_int() {
    printf '%s qemu-owner: ignored terminal SIGINT; use the monitor for shutdown\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG"
}
trap on_int INT

command -v setsid >/dev/null || {
    echo "qemu-owner: setsid is required" >&2
    exit 1
}

# QEMU receives no controlling terminal and occupies a new session/process
# group. Its serial and monitor sockets are the only supported control paths.
setsid "$@" </dev/null >>"$LOG" 2>&1 &
qemu_pid=$!
printf '%s\n' "$qemu_pid" > "$PIDFILE"

rc=0
while kill -0 "$qemu_pid" 2>/dev/null; do
    set +e
    wait "$qemu_pid"
    rc=$?
    set -e
    kill -0 "$qemu_pid" 2>/dev/null || break
    # An ignored signal interrupted wait; continue owning the same QEMU.
done

wait "$qemu_pid" 2>/dev/null || rc=$?
exit "$rc"
