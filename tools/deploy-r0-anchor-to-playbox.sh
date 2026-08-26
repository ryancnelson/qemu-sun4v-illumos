#!/usr/bin/env bash
# Deploy the exact, hash-verified R0 recovery-anchor scripts (and the pinned
# payload artifact they depend on) from this repo onto niagara-playbox,
# preserving the REPO-RELATIVE directory layout.
#
# tools/basecamp-r0-cold-anchor.sh resolves its dependencies as
# $SELFDIR/openindiana/..., $SELFDIR/chan/..., and
# $SELFDIR/../captures/openindiana-live-20260824/staged-payload/... --
# SELFDIR being wherever this script itself lands. Flattening every file
# into one directory (an earlier version of this deploy script did exactly
# that) silently breaks every one of those lookups. This version instead
# mirrors PLAYBOX_DIR as a repo root and preserves each file's relative path
# under it, so the deployed tree has the identical shape as this checkout.
#
# This is a required, explicit step of the R0 cold-anchor contract: a script
# that only exists on the Mac and merely SAYS "run on playbox" is not a
# runnable recovery. This script closes that gap and proves closure by
# comparing hashes after transfer, not by assuming scp succeeded.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAYBOX_HOST="${PLAYBOX_HOST:-niagara@niagara-playbox}"
# A repo-shaped root, distinct from $PROJ (~/niag-proj, the separate QEMU
# source checkout) which basecamp-r0-cold-anchor.sh reads images/binaries
# from via $HOME-relative paths, not via this deploy tree.
PLAYBOX_DIR="${PLAYBOX_DIR:-/home/niagara/niag-proj-anchor}"

FILES=(
    tools/openindiana/r0-maintenance-login.exp
    tools/openindiana/r0-guest-command.exp
    tools/openindiana/r0-obp-boot-and-login.exp
    tools/openindiana/maintenance-login.sh
    tools/openindiana/safe-console.sh
    tools/openindiana/qemu-owner.sh
    tools/basecamp-r0-cold-anchor.sh
    tools/chan/host-chan.py
    tools/chan/chan.h
    tools/chan/chan-test.py
    captures/openindiana-live-20260824/staged-payload/basecamp-r0-bootstrap.proven.tar
)

EXEC_FILES=(
    tools/openindiana/r0-maintenance-login.exp
    tools/openindiana/r0-guest-command.exp
    tools/openindiana/r0-obp-boot-and-login.exp
    tools/openindiana/maintenance-login.sh
    tools/openindiana/safe-console.sh
    tools/openindiana/qemu-owner.sh
    tools/basecamp-r0-cold-anchor.sh
)

echo "=== deploying $(printf '%s ' "${FILES[@]}" | wc -w) files to $PLAYBOX_HOST:$PLAYBOX_DIR (repo-relative layout) ==="
ssh "$PLAYBOX_HOST" "mkdir -p '$PLAYBOX_DIR'"

fail=0
for f in "${FILES[@]}"; do
    local_path="$REPO/$f"
    remote_path="$PLAYBOX_DIR/$f"
    remote_dir="$(dirname "$remote_path")"
    [[ -f "$local_path" ]] || { echo "MISSING LOCALLY: $local_path" >&2; fail=1; continue; }
    local_sha=$(sha256sum "$local_path" | awk '{print $1}')
    ssh "$PLAYBOX_HOST" "mkdir -p '$remote_dir'"
    scp -q "$local_path" "$PLAYBOX_HOST:$remote_path"
    remote_sha=$(ssh "$PLAYBOX_HOST" "sha256sum '$remote_path'" | awk '{print $1}')
    if [[ "$local_sha" != "$remote_sha" ]]; then
        echo "HASH MISMATCH after transfer: $f  local=$local_sha remote=$remote_sha" >&2
        fail=1
        continue
    fi
    echo "  OK  $f  $local_sha"
done

for f in "${EXEC_FILES[@]}"; do
    ssh "$PLAYBOX_HOST" "chmod +x '$PLAYBOX_DIR/$f'" 2>/dev/null || true
done

(( fail == 0 )) || { echo "DEPLOY FAILED -- do not treat the anchor as runnable" >&2; exit 1; }
echo "=== deploy verified: all files hash-match on playbox, layout preserved ==="
echo "Run on playbox as:  bash $PLAYBOX_DIR/tools/basecamp-r0-cold-anchor.sh"
