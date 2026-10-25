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
    sparc64-linux-gnu-objdump sha256sum patch; do
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

# Exact approved token fix; reject drift before modifying disposable source.
token_patch="$project_dir/patches/openbios/0004-fcode-64bit-token-slots.patch"
token_patch_sha256=d27a3c9e8148340c51af663b60e6eb9fc59931c8835b0c21c16ec81ca823c30b
token_base_sha256=7691a6aae98da1de270304071791dbb3e34fb30372790a1ff21d86b68fd0d9d2
token_fixed_sha256=cef7bb8cfe39a7c0e27dcad8568b6890da7837a936063b81cf997687804f46c2
printf '%s  %s\n' "$token_patch_sha256" "$token_patch" | sha256sum -c -
printf '%s  %s\n' "$token_base_sha256" "$source_dir/forth/device/table.fs" | sha256sum -c -

# Pin the approved absent-only SPARC64 ATA disk binding before any mutation.
dad_patch="$project_dir/patches/openbios/0005-sparc64-ata-dad-compatible.patch"
dad_patch_sha256=81eaa3f4e4f5816d7d55ac2825879ecaa926b96f3280d2087606ac096f8b4650
dad_base_sha256=60ac3a0d1aa22d8b87ffbde695b96ba8202309a4c6b3ee0aeb1189362edce654
dad_fixed_sha256=54d8f54b0db401a173e91da7837c94875ad8f4f680a9541764765cc61f11bfa2
printf '%s  %s\n' "$dad_patch_sha256" "$dad_patch" | sha256sum -c -
printf '%s  %s\n' "$dad_base_sha256" "$source_dir/drivers/ide.c" | sha256sum -c -

patches=(
    "$project_dir/patches/openbios/0001-aarch64-host-bitwidth.patch"
    "$project_dir/patches/openbios/0002-sun4u-solaris-device-paths.patch"
    "$project_dir/patches/openbios/0003-sparc64-available-ranges.patch"
)

for patch in "${patches[@]}"; do
    git -C "$source_dir" apply --unidiff-zero --check "$patch"
    git -C "$source_dir" apply --unidiff-zero "$patch"
done

# Keep the reviewed patch bytes and upstream whitespace. Select the pinned
# target explicitly because the original patch headers differ in path depth.
printf '%s  %s\n' "$token_base_sha256" "$source_dir/forth/device/table.fs" | sha256sum -c -
patch --batch --forward --dry-run "$source_dir/forth/device/table.fs" "$token_patch"
patch --batch --forward "$source_dir/forth/device/table.fs" "$token_patch"
printf '%s  %s\n' "$token_fixed_sha256" "$source_dir/forth/device/table.fs" | sha256sum -c -

# Earlier project patches must not silently alter the approved dad base.
printf '%s  %s\n' "$dad_base_sha256" "$source_dir/drivers/ide.c" | sha256sum -c -
git -C "$source_dir" apply --check "$dad_patch"
git -C "$source_dir" apply "$dad_patch"
printf '%s  %s\n' "$dad_fixed_sha256" "$source_dir/drivers/ide.c" | sha256sum -c -

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
install -m 0644 "$unstripped" "$output_file.nostrip"

echo "OPENBIOS_BUILD=PASS"
echo "openbios_commit=$expected_commit"
echo "firmware=$output_file"
stat -c 'firmware_bytes=%s' "$output_file"
echo "token_patch_sha256=$token_patch_sha256"
echo "token_table_sha256=$token_fixed_sha256"
echo "dad_patch_sha256=$dad_patch_sha256"
echo "dad_ide_sha256=$dad_fixed_sha256"
sha256sum "$output_file" "$output_file.nostrip"
