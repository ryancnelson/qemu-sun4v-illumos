#!/usr/bin/env bash
# Reuse only hash-pinned archives; never reuse a previous writable guest disk.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
cache_parent=${GOLDEN_CACHE_PARENT:-$(dirname "$root")}
source_host=${GOLDEN_SOURCE_HOST:-root@100.71.153.107}
source_root=/root/devel/sparc64-qemu-illumos-docker-guest

stage_archive() (
    local rel=$1 manifest=$2 expected candidate tmp
    expected=$(awk -v name="${rel##*/}" '$2 == name {print $1}' "$manifest")
    [[ $expected =~ ^[0-9a-f]{64}$ ]]
    tmp=$(mktemp "$root/${rel}.partial.XXXXXX")
    trap 'rm -f -- "$tmp"' EXIT
    for candidate in "$cache_parent"/golden-volume-amd64-*/"$rel"; do
        [[ -f $candidate && $candidate != "$root/$rel" ]] || continue
        [[ $(sha256sum "$candidate" | cut -d ' ' -f1) == "$expected" ]] || continue
        cp --reflink=auto "$candidate" "$tmp"
        if [[ $(sha256sum "$tmp" | cut -d ' ' -f1) == "$expected" ]]; then
            mv "$tmp" "$rel"
            echo "GOLDEN_INPUT_CACHE=PASS archive=$rel"
            exit 0
        fi
    done
    scp -o BatchMode=yes -o ConnectTimeout=15 "$source_host:$source_root/$rel" "$tmp"
    [[ $(sha256sum "$tmp" | cut -d ' ' -f1) == "$expected" ]]
    mv "$tmp" "$rel"
    echo "GOLDEN_INPUT_DOWNLOAD=PASS archive=$rel"
)

stage_archive sources/qemu-049affb20df67162cf58deeaf74d5ad4b83cbdc3.tar.gz sources/SHA256SUMS
stage_archive release/sparc64-qemu-openindiana-20g-beta-20260901.tar.zst RELEASE-ARCHIVE.SHA256SUMS
scp -o BatchMode=yes -o ConnectTimeout=15 -r "$source_host:$source_root/assets/firmware" assets/
chmod 0755 appliance scripts/*.sh
