#!/usr/bin/env bash
# Invoke through ~/bin/safe-bash. Imports compiled artifacts, never executes them.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: bash import-artifacts.sh /path/to/exported-build" >&2
    exit 2
fi
source_dir=$(cd "$1" && pwd)
harness_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
asset_dir="$harness_dir/assets"
module_file="$source_dir/qemu-system-sparc64.js"
if [[ ! -f "$module_file" ]]; then
    module_file="$source_dir/qemu-system-sparc64"
fi
wasm_file="$source_dir/qemu-system-sparc64.wasm"
worker_file="$source_dir/qemu-system-sparc64.worker.js"
for artifact in "$module_file" "$wasm_file" "$worker_file"; do
    [[ -s "$artifact" ]] || { echo "Missing/empty artifact: $artifact" >&2; exit 1; }
done
magic=$(od -An -tx1 -N8 "$wasm_file" | tr -d ' \n')
[[ "$magic" == '0061736d01000000' ]] || { echo 'Not a Wasm v1 binary' >&2; exit 1; }
rg -q 'export.*default|export.*as default' "$module_file" || {
    echo 'JS does not look like an ES6 default factory' >&2; exit 1;
}
node --check --input-type=module < "$module_file"
node --check "$worker_file"
mkdir -p "$asset_dir"
sources=("$module_file" "$wasm_file" "$worker_file")
names=(qemu-system-sparc64.js qemu-system-sparc64.wasm qemu-system-sparc64.worker.js)
# Check every collision before copying any files, so a new build cannot silently
# mix with old companions. Move an old artifact set aside explicitly to replace it.
for i in 0 1 2; do
    destination="$asset_dir/${names[$i]}"
    if [[ -e "$destination" ]] && ! cmp -s "${sources[$i]}" "$destination"; then
        echo "Refusing different existing artifact: $destination" >&2
        exit 1
    fi
done
for i in 0 1 2; do
    destination="$asset_dir/${names[$i]}"
    [[ -e "$destination" ]] || cp "${sources[$i]}" "$destination"
done
shasum -a 256 "$asset_dir/qemu-system-sparc64.js" \
    "$asset_dir/qemu-system-sparc64.wasm" "$asset_dir/qemu-system-sparc64.worker.js"
echo 'Artifact import complete. This does not establish browser execution or firmware boot.'
echo 'Reload http://localhost:8089/, click Start, and follow ACCEPTANCE.md.'
