#!/usr/bin/env bash
# Serialize and consume every atomically-ready inbox request.  Suitable for a
# systemd.path-triggered oneshot and for a periodic timer as missed-event
# recovery.  It does not poll or boot a VM.
set -euo pipefail

INBOX=${INBOX:?INBOX is required}
BUILDER=${BUILDER:?BUILDER is required}
mkdir -p "$INBOX"

found=0
while IFS= read -r marker; do
    found=1
    req=${marker%/INPUT_READY}
    "$BUILDER" "$req"
    mv -- "$marker" "$req/INPUT_CONSUMED"
done < <(find "$INBOX" -mindepth 2 -maxdepth 2 -type f -name INPUT_READY -print | sort)

(( found )) || echo "no ready artifact requests"
