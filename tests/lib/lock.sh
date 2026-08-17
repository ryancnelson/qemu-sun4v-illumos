#!/usr/bin/env bash
# Lock primitives for niagara QEMU tests.
#
# A lockfile at /run/niagara-<zvol-name>.lock contains the PID of the
# process holding it. Any attempt to acquire a lock held by a live PID
# aborts. Locks are released via trap on exit.
#
# Usage:
#   source tests/lib/lock.sh
#   lock_acquire vms/primary    # acquires lock, registers trap to release
#   lock_check   vms/primary    # returns 0 if free, 1 if held
#   lock_release vms/primary    # explicit release (trap also calls this)

set -euo pipefail

LOCK_DIR="${LOCK_DIR:-/run}"

_lock_path() {
    local zvol_name="${1//\//-}"   # replace / with - for filename safety
    echo "$LOCK_DIR/niagara-${zvol_name}.lock"
}

# lock_check <zvol-name>
# Returns 0 if the lock is free, 1 if held by a live process.
lock_check() {
    local lockfile
    lockfile=$(_lock_path "$1")

    [[ -f "$lockfile" ]] || return 0

    local held_pid
    held_pid=$(cat "$lockfile" 2>/dev/null) || return 0

    if [[ -n "$held_pid" ]] && kill -0 "$held_pid" 2>/dev/null; then
        echo "LOCK HELD: $lockfile by PID $held_pid" >&2
        return 1
    fi

    # Stale lockfile — process is dead
    echo "Removing stale lock $lockfile (PID $held_pid no longer alive)" >&2
    rm -f "$lockfile"
    return 0
}

# lock_acquire <zvol-name>
# Acquires the lock or exits 1 if held. Registers a trap to release on exit.
lock_acquire() {
    local zvol="$1"
    local lockfile
    lockfile=$(_lock_path "$zvol")

    if ! lock_check "$zvol"; then
        echo "ERROR: cannot acquire lock for $zvol — already held" >&2
        exit 1
    fi

    echo "$$" > "$lockfile"
    # Register release for all exit paths
    trap "lock_release $(printf '%q' "$zvol")" EXIT INT TERM
}

# lock_release <zvol-name>
# Releases the lock. Safe to call multiple times.
lock_release() {
    local lockfile
    lockfile=$(_lock_path "$1")

    local held_pid
    held_pid=$(cat "$lockfile" 2>/dev/null) || true

    if [[ "${held_pid:-}" == "$$" ]]; then
        rm -f "$lockfile"
    fi
}
