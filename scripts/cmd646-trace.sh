#!/usr/bin/env bash
# No actions until explicitly enabled. Called only by isolated harness.
trace_enabled=${SUN4U_TRACE_CMD646:-0}
trace_qemu_args=()
trace_watch_pid=
trace_helper="$(dirname "${BASH_SOURCE[0]}")/cmd646-trace.py"
case "$trace_enabled" in 0|1) ;; *) echo 'SUN4U_TRACE_CMD646 must be 0 or 1' >&2; return 2 ;; esac
if [[ "$trace_enabled" == 1 ]]; then
    # A bounded diagnostic must not leave tracing on in a preserved live guest.
    if [[ "$keep_guest" == 1 || "$keep_maintenance" == 1 ]]; then
        echo 'Trace mode requires KEEP_GUEST=0 and KEEP_MAINTENANCE=0' >&2; return 2
    fi
    command -v python3 >/dev/null || return 2
fi

prepare_trace() {
    [[ "$trace_enabled" == 1 ]] || return 0
    local file
    for file in cmd646.trace cmd646.events trace-incomplete.json trace-summary.json; do
        [[ ! -e "$run_dir/$file" && ! -L "$run_dir/$file" ]] || return 2
    done
    printf '%s\n' ide_ioport_read ide_ioport_write ide_status_read \
        bmdma_read_cmd646 bmdma_write_cmd646 pci_cfg_read pci_cfg_write >"$run_dir/cmd646.events"
    trace_qemu_args=(-trace events=/run/sun4u/cmd646.events -msg timestamp=on -D /run/sun4u/cmd646.trace)
}

start_trace_watch() {
    [[ "$trace_enabled" == 1 ]] || return 0
    recover_created_container
    [[ "$container_created" == 1 && "$container" =~ ^[0-9a-f]{64}$ ]] || return 2
    python3 "$trace_helper" watch "$run_dir" "$container" >"$run_dir/trace-observer.log" 2>&1 &
    trace_watch_pid=$!
}

check_trace() {
    [[ "$trace_enabled" == 1 ]] || return 0
    if [[ -e "$run_dir/trace-incomplete.json" ]] ||
       { [[ -n "$trace_watch_pid" ]] && ! kill -0 "$trace_watch_pid" 2>/dev/null; }; then
        capture_outcome TRACE_INCOMPLETE 27
        return 27
    fi
}

finish_trace() {
    [[ "$trace_enabled" == 1 ]] || return 0
    check_trace || true
    if [[ -n "$trace_watch_pid" ]]; then
        kill "$trace_watch_pid" 2>/dev/null || true
        local watch_exit=0
        wait "$trace_watch_pid" 2>/dev/null || watch_exit=$?
        printf '%s\n' "$watch_exit" >"$run_dir/trace-observer.exit" || capture_outcome TRACE_INCOMPLETE 27
        # A failing watcher may have been unable to write its error marker.
        [[ "$watch_exit" == 0 ]] || capture_outcome TRACE_INCOMPLETE 27
    fi
    # Never analyze a possibly live writer. Stop/inspect operations have
    # individual 10s bounds and at most one exact-CID kill fallback.
    if [[ "$container_created" == 1 ]]; then
        if ! python3 "$trace_helper" stop "$run_dir" "$container"; then
            capture_outcome TRACE_INCOMPLETE 27
            return 27
        fi
    fi
    if ! python3 "$trace_helper" finish "$run_dir"; then
        capture_outcome TRACE_INCOMPLETE 27
    fi
    if ! sha256sum "$run_dir/cmd646.trace" "$run_dir/cmd646.events" >"$run_dir/trace-SHA256SUMS"; then
        capture_outcome TRACE_INCOMPLETE 27
    fi
}
