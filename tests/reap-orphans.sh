#!/usr/bin/env bash
# Reclaim leaked test clones and stale @pre-exit snapshots.
#
# Test clones are named vms/test-<name>-<pid>. Each test's exit trap destroys
# its own clone, but interrupted or crashed runs leak them at ~260MB each.
#
# -r is required: QEMU's atexit writeback takes a @pre-exit-<pid> snapshot on
# the zvol it opened — the clone — so a plain `zfs destroy` fails permanently
# with "volume has children".
#
# Usage: sudo bash tests/reap-orphans.sh [--dry-run]

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "ERROR: must run as root" >&2; exit 1; }

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

POOL="${NIAGARA_POOL:-datapool}"
DATASET="${NIAGARA_DATASET:-niagara}"
VMS="$POOL/$DATASET/vms"

mapfile -t clones < <(zfs list -H -o name -r "$VMS" 2>/dev/null | grep "^$VMS/test-" || true)
mapfile -t snaps  < <(zfs list -H -t snapshot -o name -r "$VMS" 2>/dev/null | grep -- '@pre-exit-' || true)

if (( ${#clones[@]} == 0 && ${#snaps[@]} == 0 )); then
    echo "nothing to reap"
    exit 0
fi

reclaimed=0
for c in "${clones[@]:-}"; do
    [[ -n "$c" ]] || continue
    # Belt and braces: refuse anything not clearly a test clone
    case "$c" in
        "$VMS"/test-*) ;;
        *) echo "SKIP (not a test clone): $c" >&2; continue ;;
    esac
    sz=$(zfs list -H -o refer "$c" 2>/dev/null || echo "?")
    if (( DRY )); then
        echo "would destroy: $c ($sz)"
    elif zfs destroy -r "$c" 2>/dev/null; then
        echo "destroyed: $c ($sz)"
        (( reclaimed++ )) || true
    else
        echo "FAILED (still open?): $c ($sz)" >&2
    fi
done

for s in "${snaps[@]:-}"; do
    [[ -n "$s" ]] || continue
    if (( DRY )); then
        echo "would destroy snapshot: $s"
    elif zfs destroy "$s" 2>/dev/null; then
        echo "destroyed snapshot: $s"
    else
        echo "FAILED: $s" >&2
    fi
done

(( DRY )) || echo "reclaimed $reclaimed clone(s)"
