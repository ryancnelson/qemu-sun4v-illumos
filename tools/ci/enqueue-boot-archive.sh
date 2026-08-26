#!/usr/bin/env bash
# Publish one finalized UFS boot archive into the continuous-builder inbox.
# INPUT_READY is created last, by atomic rename.  The consumer never guesses
# which archive is newest from filenames or mtimes.
set -euo pipefail

usage() {
    echo "usage: $0 ARCHIVE INBOX [BUILD_ID]" >&2
    exit 2
}

[[ $# -ge 2 && $# -le 3 ]] || usage
archive=$(readlink -f -- "$1")
inbox=$(readlink -m -- "$2")
build_id=${3:-}

[[ -f "$archive" ]] || { echo "archive not found: $archive" >&2; exit 1; }
size=$(stat -c %s -- "$archive")
[[ "$size" == 192595968 ]] || {
    echo "refusing boot archive with unexpected size $size" >&2
    exit 1
}
sha=$(sha256sum -- "$archive" | awk '{print $1}')
[[ -n "$build_id" ]] || build_id="$(date -u +%Y%m%dT%H%M%SZ)-${sha:0:12}"
[[ "$build_id" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "unsafe build id: $build_id" >&2
    exit 1
}

mkdir -p -- "$inbox"
tmp="$inbox/.${build_id}.partial.$$"
final="$inbox/$build_id"
[[ ! -e "$final" ]] || { echo "build id already exists: $final" >&2; exit 1; }
trap 'rm -rf -- "$tmp"' EXIT
mkdir -- "$tmp"
cp --reflink=auto --sparse=always -- "$archive" "$tmp/boot_archive.ufs"
[[ "$(sha256sum "$tmp/boot_archive.ufs" | awk '{print $1}')" == "$sha" ]]

python3 - "$tmp/request.json.tmp" "$build_id" "$archive" "$size" "$sha" <<'PY'
import json, os, sys
out, build_id, source, size, sha = sys.argv[1:]
doc = {
    "schema_version": 1,
    "build_id": build_id,
    "created_utc": __import__("datetime").datetime.now(
        __import__("datetime").timezone.utc).isoformat(),
    "boot_archive": {
        "source_path": source,
        "size": int(size),
        "sha256": sha,
    },
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(doc, f, sort_keys=True, indent=2)
    f.write("\n")
    f.flush()
    os.fsync(f.fileno())
PY
mv -- "$tmp/request.json.tmp" "$tmp/request.json"
touch "$tmp/INPUT_READY.tmp"
mv -- "$tmp/INPUT_READY.tmp" "$tmp/INPUT_READY"
mv -- "$tmp" "$final"
trap - EXIT
echo "$final"
