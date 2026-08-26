#!/usr/bin/env bash
# Consume one hash-pinned boot archive and atomically publish a matching
# OpenIndiana big-disk release.  This script never boots QEMU and never writes
# a source or previously-published artifact.
set -euo pipefail

usage() {
    echo "usage: $0 REQUEST_DIR" >&2
    echo "env: SOURCE_ISO RELEASE_ROOT VTOC_TOOL" >&2
    exit 2
}

[[ $# == 1 ]] || usage
request_dir=$(readlink -f -- "$1")
source_iso=${SOURCE_ISO:?SOURCE_ISO is required}
release_root=${RELEASE_ROOT:?RELEASE_ROOT is required}
vtoc_tool=${VTOC_TOOL:?VTOC_TOOL is required}

source_iso=$(readlink -f -- "$source_iso")
vtoc_tool=$(readlink -f -- "$vtoc_tool")
[[ -f "$request_dir/INPUT_READY" && -f "$request_dir/request.json" \
   && -f "$request_dir/boot_archive.ufs" ]] || {
    echo "request is incomplete: $request_dir" >&2; exit 1; }
[[ -f "$source_iso" && -f "$vtoc_tool" ]] || {
    echo "missing SOURCE_ISO or VTOC_TOOL" >&2; exit 1; }

readarray -t req < <(python3 - "$request_dir/request.json" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
bid = d["build_id"]
if not re.fullmatch(r"[A-Za-z0-9._-]+", bid):
    raise SystemExit("unsafe build_id")
a = d["boot_archive"]
print(bid)
print(a["size"])
print(a["sha256"])
PY
)
build_id=${req[0]}
expected_arc_size=${req[1]}
expected_arc_sha=${req[2]}

readonly SOURCE_SIZE=644198400
readonly SOURCE_SHA=173ade54c7f390ab0ba86500b0340f03aa92160a1805cb2d0ed7dd4e0bd85f04
readonly ARC_SIZE=192595968
readonly ARC_OFFSET_SECTOR=878408
readonly ARC_LENGTH_SECTORS=376164
readonly ARC_END_BYTE=642340864
readonly BIG_DISK_SIZE=2791702528
readonly NCYL=8520
readonly S2_BLOCKS=5452544
readonly S7_START_CYL=1966
readonly S7_BLOCKS=4194304
readonly GAP_START=644198400
readonly GAP_BYTES=20480

mkdir -p "$release_root"/{releases,failures}
exec 9>"$release_root/.build.lock"
flock -n 9 || { echo "another artifact build owns the lock" >&2; exit 75; }

final="$release_root/releases/$build_id"
if [[ -f "$final/READY" ]]; then
    ln -sfn "releases/$build_id" "$release_root/current.new"
    mv -Tf "$release_root/current.new" "$release_root/current"
    echo "$final"
    exit 0
fi
[[ ! -e "$final" ]] || { echo "incomplete release already exists: $final" >&2; exit 1; }

work="$release_root/.${build_id}.partial.$$"
log="$work/build.log"
failed_step=initializing
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cleanup() {
    rc=$?
    if (( rc != 0 )) && [[ -d "$work" ]]; then
        printf 'FAILED_STEP=%q\nRC=%q\n' "$failed_step" "$rc" >>"$log" 2>/dev/null || true
        touch "$work/FAILED" 2>/dev/null || true
        dest="$release_root/failures/${build_id}-$(date -u +%Y%m%dT%H%M%SZ)"
        mv -- "$work" "$dest" 2>/dev/null || true
        echo "artifact build failed at $failed_step; evidence: $dest" >&2
    fi
    exit "$rc"
}
trap cleanup EXIT
mkdir -- "$work"
exec > >(tee -a "$log") 2>&1

failed_step=verify_inputs
[[ "$(stat -c %s "$source_iso")" == "$SOURCE_SIZE" ]]
[[ "$(sha256sum "$source_iso" | awk '{print $1}')" == "$SOURCE_SHA" ]]
[[ "$expected_arc_size" == "$ARC_SIZE" ]]
arc="$request_dir/boot_archive.ufs"
[[ "$(stat -c %s "$arc")" == "$ARC_SIZE" ]]
[[ "$(sha256sum "$arc" | awk '{print $1}')" == "$expected_arc_sha" ]]

failed_step=copy_inputs
cp --reflink=auto --sparse=always -- "$arc" "$work/boot_archive.ufs"
cp --reflink=auto --sparse=always -- "$source_iso" "$work/big-disk.img"
cmp -s -- "$source_iso" "$work/big-disk.img"

failed_step=splice_archive
dd if="$work/boot_archive.ufs" of="$work/big-disk.img" bs=512 \
   seek="$ARC_OFFSET_SECTOR" conv=notrunc status=none
readback_sha=$(dd if="$work/big-disk.img" bs=512 skip="$ARC_OFFSET_SECTOR" \
    count="$ARC_LENGTH_SECTORS" status=none | sha256sum | awk '{print $1}')
[[ "$readback_sha" == "$expected_arc_sha" ]]

failed_step=extend_and_label
truncate -s "$BIG_DISK_SIZE" "$work/big-disk.img"
python3 "$vtoc_tool" set-ncyl "$work/big-disk.img" "$NCYL"
python3 "$vtoc_tool" set "$work/big-disk.img" 2 0 "$S2_BLOCKS"
python3 "$vtoc_tool" set "$work/big-disk.img" 7 "$S7_START_CYL" "$S7_BLOCKS"
python3 "$vtoc_tool" verify "$work/big-disk.img"

failed_step=verify_unchanged_regions
# Sector zero contains the intentionally edited Sun label.  Everything after
# it and before the archive, plus the original suffix after the archive, must
# remain byte-identical to the immutable source ISO.
cmp -n $((ARC_OFFSET_SECTOR * 512 - 512)) -i 512:512 \
    "$source_iso" "$work/big-disk.img"
cmp -n $((SOURCE_SIZE - ARC_END_BYTE)) -i "$ARC_END_BYTE:$ARC_END_BYTE" \
    "$source_iso" "$work/big-disk.img"
gap_nonzero=$(dd if="$work/big-disk.img" bs=1 skip="$GAP_START" count="$GAP_BYTES" \
    status=none | tr -d '\000' | wc -c)
[[ "$gap_nonzero" == 0 ]]
[[ "$(stat -c %s "$work/big-disk.img")" == "$BIG_DISK_SIZE" ]]

failed_step=publish_manifest
qemu_sha=${QEMU_SHA256:-unknown}
qemu_path=${QEMU_PATH:-unknown}
big_sha=$(sha256sum "$work/big-disk.img" | awk '{print $1}')
big_allocated=$(du -B1 "$work/big-disk.img" | awk '{print $1}')
script_sha=$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')
completed=$(date -u +%Y-%m-%dT%H:%M:%SZ)
python3 - "$work/manifest.json.tmp" "$build_id" "$started" "$completed" \
    "$script_sha" "$qemu_path" "$qemu_sha" "$source_iso" \
    "$expected_arc_sha" "$big_allocated" "$big_sha" <<PY
import json, os, sys
(out, build_id, started, completed, script_sha, qemu_path, qemu_sha,
 source_iso, arc_sha, big_allocated, big_sha) = sys.argv[1:]
d = {
  "schema_version": 1, "build_id": build_id, "state": "READY",
  "created_utc": started, "completed_utc": completed,
  "builder": {"host": os.uname().nodename, "script_sha256": script_sha},
  "qemu": {"path": qemu_path, "sha256": qemu_sha},
  "inputs": {
    "source_iso": {"path": source_iso, "size": $SOURCE_SIZE, "sha256": "$SOURCE_SHA"},
    "boot_archive": {"size": $ARC_SIZE, "sha256": arc_sha}
  },
  "layout": {"sector_size": 512, "archive_offset_sector": $ARC_OFFSET_SECTOR,
    "archive_length_sectors": $ARC_LENGTH_SECTORS, "image_size": $BIG_DISK_SIZE,
    "ncyl": $NCYL, "s2_blocks": $S2_BLOCKS,
    "s7_start_cyl": $S7_START_CYL, "s7_blocks": $S7_BLOCKS,
    "gap_bytes": $GAP_BYTES},
  "outputs": {
    "boot_archive": {"relative_path": "boot_archive.ufs", "size": $ARC_SIZE,
      "sha256": arc_sha},
    "big_disk": {"relative_path": "big-disk.img", "size": $BIG_DISK_SIZE,
      "allocated_bytes": int(big_allocated), "sha256": big_sha}
  },
  "tests": [
    {"name": "input hashes", "status": "PASS"},
    {"name": "sector-exact archive readback", "status": "PASS"},
    {"name": "VTOC geometry", "status": "PASS"},
    {"name": "unchanged source regions", "status": "PASS"},
    {"name": "zero safety gap", "status": "PASS"}
  ]
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(d, f, sort_keys=True, indent=2); f.write("\n"); f.flush(); os.fsync(f.fileno())
PY
mv "$work/manifest.json.tmp" "$work/manifest.json"
cat >"$work/smoke.env.tmp" <<EOF
RELEASE_ID=$build_id
RELEASE_DIR=$final
BOOT_ARCHIVE=$final/boot_archive.ufs
BOOT_ARCHIVE_SHA=$expected_arc_sha
BIG_DISK=$final/big-disk.img
BIG_DISK_SHA=$big_sha
QEMU_PATH=$qemu_path
QEMU_SHA=$qemu_sha
EOF
mv "$work/smoke.env.tmp" "$work/smoke.env"
chmod 0444 "$work/boot_archive.ufs" "$work/big-disk.img" \
    "$work/manifest.json" "$work/smoke.env"
touch "$work/READY"
mv -- "$work" "$final"
ln -s "releases/$build_id" "$release_root/current.new"
mv -Tf "$release_root/current.new" "$release_root/current"
trap - EXIT
echo "$final"
