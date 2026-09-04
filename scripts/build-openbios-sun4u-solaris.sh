#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "usage: $0 OPENBIOS_SOURCE_DIR OUTPUT_FILE" >&2
    echo "" >&2
    echo "OPENBIOS_SOURCE_DIR must be a clean disposable worktree at the" >&2
    echo "QEMU-pinned OpenBIOS commit." >&2
    exit 2
}

if [ "$#" -ne 2 ]; then
    usage
fi

source_dir=$1
output_file=$2
project_dir=$(cd "$(dirname "$0")/.." && pwd)
expected_commit=af97fd7af5e7c18f591a7b987291d3db4ffb28b5

for tool in git make xsltproc toke sparc64-linux-gnu-gcc \
    sparc64-linux-gnu-objdump sha256sum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing required build tool: $tool" >&2
        exit 1
    fi
done

if [ ! -d "$source_dir/.git" ] && \
    ! git -C "$source_dir" rev-parse --git-dir >/dev/null 2>&1; then
    echo "not an OpenBIOS git worktree: $source_dir" >&2
    exit 1
fi

actual_commit=$(git -C "$source_dir" rev-parse HEAD)
if [ "$actual_commit" != "$expected_commit" ]; then
    echo "wrong OpenBIOS commit: expected $expected_commit, got $actual_commit" >&2
    exit 1
fi

if [ -n "$(git -C "$source_dir" status --porcelain)" ]; then
    echo "OpenBIOS worktree is not clean: $source_dir" >&2
    exit 1
fi

patches=(
    "$project_dir/patches/openbios/0001-aarch64-host-bitwidth.patch"
    "$project_dir/patches/openbios/0002-sun4u-solaris-device-paths.patch"
)

for patch in "${patches[@]}"; do
    git -C "$source_dir" apply --unidiff-zero --check "$patch"
    git -C "$source_dir" apply --unidiff-zero "$patch"
done

git -C "$source_dir" diff --check

(
    cd "$source_dir"
    ./config/scripts/switch-arch sparc64
    EXTRACFLAGS=-fno-stack-protector make -j"${JOBS:-2}"
)

firmware="$source_dir/obj-sparc64/openbios-builtin.elf"
unstripped="$source_dir/obj-sparc64/openbios-builtin.elf.nostrip"

if [ ! -s "$firmware" ] || [ ! -s "$unstripped" ]; then
    echo "OpenBIOS build did not produce the expected firmware files" >&2
    exit 1
fi

disassembly_file=$(mktemp)
trap 'rm -f "$disassembly_file"' EXIT
sparc64-linux-gnu-objdump -d "$unstripped" >"$disassembly_file"

if grep -Fq '%g7 + 0x28' "$disassembly_file"; then
    echo "firmware contains a stack-canary TLS load; refusing artifact" >&2
    exit 1
fi

rm -f "$disassembly_file"
trap - EXIT

mkdir -p "$(dirname "$output_file")"
install -m 0644 "$firmware" "$output_file"

echo "OPENBIOS_BUILD=PASS"
echo "openbios_commit=$expected_commit"
echo "firmware=$output_file"
stat -c 'firmware_bytes=%s' "$output_file"
sha256sum "$output_file"
