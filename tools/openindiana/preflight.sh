#!/usr/bin/env bash
# preflight.sh -- hash-gate everything the 2026-08-25 incident got wrong,
# BEFORE any boot happens.
#
#   sudo bash tools/openindiana/preflight.sh <image-path>
#
# WHY THIS EXISTS. The 2026-08-25 OpenIndiana incident burned hours because the
# actual state on niagara-playbox silently diverged from what the operator
# believed was there:
#   - host-up.sh on disk had `persist maxfail 0` reintroduced, which the local
#     repo copy did not have -- nobody compared hashes before running it;
#   - the running QEMU binary was stale (build c0ee6012) while the patched
#     source (build 8ad4fe2e) sat unbuilt for hours;
#   - the working image had inherited an unclean, never-exported ZFS pool from
#     a previous failed run and was mistaken for a fresh baseline.
#
# This script asserts, in one place, every fact that incident wished someone
# had checked first. It is READ-ONLY: it never starts, stops, or modifies
# anything. A clean run is the ONLY thing that should gate `orchestrate-boot.sh`
# proceeding past its first checkpoint.
set -uo pipefail

PROJ="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
IMG="${1:?usage: preflight.sh <image-path>}"
QEMU="${NIAGARA_QEMU:-$HOME/niag-proj/qemu/build/qemu-system-sparc64}"
HOST_UP="$PROJ/tools/chan/host-up.sh"
GUEST_START="$PROJ/tools/openindiana/guest-start.sh"

fail=0
ok()  { printf '  \033[32mok\033[0m    %s\n' "$*"; }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=1; }
head_() { printf '\n== %s ==\n' "$*"; }

head_ "identity: is this the checked-in tooling, or has it drifted?"
for f in "$HOST_UP" "$GUEST_START"; do
    if [[ -f "$f" ]]; then
        h=$(sha256sum "$f" | awk '{print $1}')
        # Compare the deployed copy against the repo's OWN tracked copy, not a
        # hardcoded hash, so this preflight can never itself go stale relative
        # to the repo. Run this FROM the repo checkout on the target host.
        repo_rel="${f#$PROJ/}"
        if git -C "$PROJ" cat-file -e "HEAD:$repo_rel" 2>/dev/null; then
            tracked_h=$(git -C "$PROJ" show "HEAD:$repo_rel" | sha256sum | awk '{print $1}')
            if [[ "$h" == "$tracked_h" ]]; then
                ok "$repo_rel matches HEAD ($h)"
            else
                bad "$repo_rel on disk ($h) DIFFERS from git HEAD ($tracked_h)"
                printf '        this is EXACTLY the 2026-08-25 zombie-storm bug: a stale deployed\n'
                printf '        copy silently differed from the reviewed repo copy. Diff it:\n'
                printf '        diff <(git -C %s show HEAD:%s) %s\n' "$PROJ" "$repo_rel" "$f"
            fi
        else
            bad "$repo_rel exists on disk but is not tracked at HEAD in this checkout"
        fi
    else
        bad "$f is missing"
    fi
done
# Guard against a dirty working tree deploying untracked local edits.
if ! git -C "$PROJ" diff --quiet -- tools/chan/host-up.sh tools/openindiana/guest-start.sh 2>/dev/null; then
    bad "uncommitted local changes to host-up.sh/guest-start.sh -- commit or stash before a real run"
fi

head_ "qemu build identity"
if [[ -x "$QEMU" ]]; then
    build=$("$QEMU" --version 2>/dev/null | head -1)
    bin_hash=$(sha256sum "$QEMU" | awk '{print $1}')
    ok "binary: $build"
    ok "sha256: $bin_hash"
    # The 2026-08-25 incident specifically launched a stale binary while the
    # patched source sat unbuilt for hours. If the range-flush source patch is
    # present in the checked-out qemu source tree, the running binary must
    # actually contain the range-flush call, not merely postdate the edit.
    LDST="$(dirname "$QEMU")/../../target/sparc/ldst_helper.c"
    if [[ -f "$LDST" ]] && grep -q tlb_flush_range_by_mmuidx "$LDST"; then
        if objdump -d "$QEMU" 2>/dev/null | grep -q tlb_flush_range_by_mmuidx; then
            ok "range-flush patch is present in BOTH source and built binary"
        else
            bad "range-flush patch is in source but NOT in the built binary -- rebuild before boot"
        fi
    fi
else
    bad "qemu binary missing or not executable: $QEMU"
fi

head_ "image identity and cleanliness"
if [[ -f "$IMG" ]]; then
    sz=$(stat -c %s "$IMG")
    h=$(sha256sum "$IMG" | awk '{print $1}')
    ok "size: $sz bytes"
    ok "sha256: $h"
    case "$IMG" in
        *.failed-*|*.zombie-storm-*)
            bad "filename marks this as labelled FAILURE EVIDENCE -- refusing to treat as a boot candidate"
            ;;
        *)
            ok "filename does not carry a failure/evidence marker"
            ;;
    esac
else
    bad "image missing: $IMG"
fi

head_ "no live worker already holding this image"
# Match the REAL qemu process only, excluding sudo/setsid wrapper layers --
# the exact class of bug fixed in host-up.sh's SIGUSR2 gate on 2026-08-25.
real_pids() {
    ps -eo pid,args --no-headers | grep -- "$1" \
        | grep -v -e 'sudo ' -e 'setsid ' -e grep | awk '{print $1}'
}
holders=$(real_pids 'qemu-system-sparc64' | while read -r p; do
    cmdline=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
    [[ "$cmdline" == *"$IMG"* ]] && echo "$p"
done)
if [[ -z "$holders" ]]; then
    ok "no running QEMU worker has this image open"
else
    bad "image already open by PID(s): $holders -- a second worker on the same MAP_SHARED image corrupts it"
fi

head_ "guest-side services quiescent (idempotency precondition)"
if command -v pgrep >/dev/null; then
    live=$(pgrep -lf 'guest-chand|guest-rootpty|guest-ppp-chan|pppd' 2>/dev/null)
    if [[ -z "$live" ]]; then
        ok "no leftover guest-side helper processes on this host"
    else
        bad "leftover helper processes present (run guest-start.sh stop first, and verify it, before boot):"
        printf '%s\n' "$live" | sed 's/^/        /'
    fi
fi

printf '\n'
if (( fail )); then
    printf '\033[31mPREFLIGHT FAILED -- do not boot.\033[0m\n'
    exit 1
else
    printf '\033[32mPREFLIGHT PASSED.\033[0m Safe to proceed to orchestrate-boot.sh.\n'
fi
