#!/usr/bin/env bash
# Reclaim leaked test clones, stale snapshots, and orphaned loop devices.
#
# Test clones are named test-<name>-<pid>. Each test's exit trap destroys its
# own clone, but interrupted or crashed runs leak them.
#
# LOOP DEVICES (new with P2-012): the disk is a FILE in a dataset now, and
# exchange.sh attaches a size-limited loop device to reach the FAT slice inside
# it. If a tool dies between attach and detach the loop survives, keeps the file
# open, and can outlive the dataset entirely — one was found pointing at
# /datapool/niagara/xtest/primary.img after that dataset had been destroyed.
# Left alone they also block `zfs destroy`.
#
# @pre-exit-<pid> snapshots are a PRE-P2-012 artifact: QEMU's atexit writeback
# used to mint one on every exit. That writeback is gone, so no new ones appear,
# but old ones are still worth clearing.
#
# Usage: sudo bash tests/reap-orphans.sh [--dry-run]

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "ERROR: must run as root" >&2; exit 1; }

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

POOL="${NIAGARA_POOL:-datapool}"
DATASET="${NIAGARA_DATASET:-niagara}"
ROOT="$POOL/$DATASET"
# Pre-P2-012 clones lived under vms/; file-backed ones are direct children of
# ROOT. Scan both so this keeps working during and after the migration.
VMS="$ROOT/vms"

mapfile -t clones < <( { zfs list -H -o name -r "$ROOT" 2>/dev/null || true; } \
    | grep -E "^$ROOT/(vms/)?(test-|peek-|xtest|p1008)" || true)
mapfile -t snaps  < <( { zfs list -H -t snapshot -o name -r "$ROOT" 2>/dev/null || true; } \
    | grep -E -- '@(pre-exit-|peek-)' || true)

# NOTE: no early exit on "nothing to reap" — loop devices are checked below and
# leak independently of any dataset. An earlier version returned here and would
# have missed exactly the orphan that motivated this section.

reclaimed=0
for c in "${clones[@]:-}"; do
    [[ -n "$c" ]] || continue
    # Belt and braces: refuse anything that is not clearly disposable
    case "$c" in
        "$ROOT"/test-*|"$ROOT"/peek-*|"$ROOT"/xtest*|"$ROOT"/p1008*) ;;
        "$VMS"/test-*|"$VMS"/peek-*) ;;
        *) echo "SKIP (not a disposable clone): $c" >&2; continue ;;
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

# --- orphaned loop devices over niagara image files ---------------------
# Reap a loop only if it is NOT mounted. A mounted one is somebody's live
# session (exchange.sh mount leaves it up deliberately), and yanking it would
# corrupt whatever is writing through it.
loops=0
while read -r lo backing; do
    [[ -n "$lo" ]] || continue
    if findmnt -S "$lo" >/dev/null 2>&1; then
        echo "SKIP (mounted): $lo -> $backing"
        continue
    fi
    if (( DRY )); then
        echo "would detach: $lo -> $backing"
    elif losetup -d "$lo" 2>/dev/null; then
        echo "detached: $lo -> $backing"
        (( loops++ )) || true
    else
        echo "FAILED to detach: $lo -> $backing" >&2
    fi
done < <(losetup -a 2>/dev/null \
         | sed -n 's#^\([^:]*\): *\[[^]]*\]: *(\([^)]*\)).*#\1 \2#p' \
         | grep -E "/${DATASET}/" || true)

(( DRY )) || echo "reclaimed $reclaimed clone(s), detached $loops loop device(s)"
