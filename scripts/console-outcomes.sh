#!/usr/bin/env bash
# Classification is provisional until final evidence/health checks complete.
outcome=
# Keep final status on harness stdout even if a signal traps inside run redirection.
exec 3>&1
outcome_code=0
container_created=0
finalizing=0
guest_live_non_oom=0
cleanup_preserved=0

capture_outcome() {
    local kind=$1 code=$2
    # Cancellation, host OOM and panic override stale success/maintenance.
    [[ "$outcome" != CANCELLED ]] || return 0
    if [[ "$kind" != CANCELLED ]]; then
        [[ "$outcome" != HOST_OOM ]] || return 0
        if [[ "$kind" != HOST_OOM ]]; then
            [[ "$outcome" != PANIC ]] || return 0
            if [[ "$kind" != PANIC && -n "$outcome" && "$outcome" != PASS ]]; then
                [[ "$outcome" == MAINTENANCE && ( "$kind" == CONTAINER_EXITED || "$kind" == INSPECT_ERROR ) ]] || return 0
            fi
        fi
    fi
    outcome=$kind
    outcome_code=$code
}

check_guest_health() {
    local state oom running status
    guest_live_non_oom=0
    if ! state=$(docker inspect "$container" --format '{{.State.OOMKilled}} {{.State.Running}} {{.State.ExitCode}}' 2>"$run_dir/state-inspect.stderr"); then
        printf '%s\n' "$state" >"$run_dir/state-inspect.txt" || true
        capture_outcome INSPECT_ERROR 26; return 26
    fi
    printf '%s\n' "$state" >"$run_dir/state-inspect.txt" || true
    read -r oom running status <<<"$state"
    if [[ "$oom" != true && "$oom" != false || "$running" != true && "$running" != false || ! "$status" =~ ^[0-9]+$ ]]; then
        capture_outcome INSPECT_ERROR 26; return 26
    fi
    if [[ "$oom" == true ]]; then
        capture_outcome HOST_OOM 22; return 22
    fi
    if grep -Eq 'panic\[|panic:|panic -|nucleus_hblk.*(exhaust|alloc)' "$console_log" 2>/dev/null; then
        capture_outcome PANIC 20; return 20
    fi
    if [[ "$running" != true ]]; then
        capture_outcome CONTAINER_EXITED 25; return 25
    fi
    guest_live_non_oom=1
    if grep -Eiq 'Requesting System Maintenance Mode|Enter user name for system maintenance|Give root password for (system )?maintenance|Type (Ctrl|control)-d to proceed with normal startup' "$console_log" 2>/dev/null; then
        capture_outcome MAINTENANCE 21; return 21
    fi
}

recover_created_container() {
    local file id
    # Docker may have created the guest before run returns or a signal traps.
    # Never fall back to deleting a pre-existing same-name container.
    for file in "$run_dir/owned-container.cid" "$run_dir/container-id.txt"; do
        [[ -s "$file" ]] || continue
        IFS= read -r id <"$file" || true
        if [[ "$id" =~ ^[0-9a-f]{64}$ ]]; then
            container=$id
            container_created=1
            return 0
        fi
    done
    return 0
}

cancel_run() {
    local code=$1
    capture_outcome CANCELLED "$code"
    preserve_ready=0
    # Returning during EXIT finalization lets evidence and cleanup finish.
    [[ "$finalizing" == 1 ]] || exit "$code"
}

finalize_run() {
    local code=$1
    finalizing=1
    set +e
    if [[ -z "$outcome" ]]; then
        if [[ "$code" == 0 ]]; then capture_outcome PASS 0
        else capture_outcome HARNESS_ERROR "$code"; fi
    fi
    recover_created_container
    if [[ "$container_created" == 1 ]]; then
        docker inspect "$container" >"$run_dir/container-inspect-final.json" 2>"$run_dir/container-inspect-final.stderr" ||
            printf 'Final Docker inspect evidence unavailable\n' >&2
        docker logs "$container" >"$run_dir/container-final.log" 2>&1 ||
            printf 'Final Docker log evidence unavailable\n' >&2
        # Catch failures appearing after the final wait or during evidence capture.
        check_guest_health || true
    fi
    if [[ -f "$console_log" ]]; then
        cp "$console_log" "$run_dir/console-final.log" ||
            printf 'Final console snapshot unavailable\n' >&2
    fi
    if declare -F finish_trace >/dev/null; then finish_trace; fi
    cleanup || true
    # A signal during the preservation branch must revoke that decision.
    if [[ "$cleanup_preserved" == 1 && "$outcome" == CANCELLED ]]; then
        cleanup_preserved=0
        cleanup || true
    fi
    # Commit the final result after all blocking evidence/cleanup operations.
    # Signals already observed have precedence. No external commands follow.
    trap '' INT TERM HUP
    printf 'SUN4U_OUTCOME=%s\nEXIT_CODE=%s\n' "$outcome" "$outcome_code" >"$run_dir/outcome.env" ||
        printf 'Final outcome file unavailable: %s/%s\n' "$outcome" "$outcome_code" >&2
    printf 'SUN4U_OUTCOME=%s\n' "$outcome" >&3
    trap - EXIT
    exit "$outcome_code"
}
