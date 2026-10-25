#!/usr/bin/env bash
# Invoke through ~/bin/safe-bash. Imports compiled artifacts, never executes them.
set -euo pipefail

if [[ $# -ne 1 && ! ( $# -eq 3 && "$2" == --expected-manifest ) ]]; then
    echo "usage: bash import-artifacts.sh /path/to/exported-build [--expected-manifest /path/to/SHA256SUMS]" >&2
    exit 2
fi
source_dir=$(cd "$1" && pwd)
harness_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
asset_dir="$harness_dir/assets"
expected_manifest="${3:-$harness_dir/ASSET-SHA256SUMS}"
module_file="$source_dir/qemu-system-sparc64.js"
if [[ ! -f "$module_file" ]]; then
    module_file="$source_dir/qemu-system-sparc64"
fi
wasm_file="$source_dir/qemu-system-sparc64.wasm"
worker_file="$source_dir/qemu-system-sparc64.worker.js"
for artifact in "$module_file" "$wasm_file" "$worker_file"; do
    [[ -s "$artifact" ]] || { echo "Missing/empty artifact: $artifact" >&2; exit 1; }
done
# Validate the complete fixed bundle before creating or changing the destination.
# A deliberately supplied manifest selects independently pinned candidate bytes;
# it does not select filenames or establish runtime/ABI compatibility.
python3 - "$expected_manifest" "$module_file" "$wasm_file" "$worker_file" <<'PY'
import hashlib
import re
import sys
from pathlib import Path

names = ('qemu-system-sparc64.js', 'qemu-system-sparc64.wasm',
         'qemu-system-sparc64.worker.js')
required = {'assets/' + name for name in names}
allowed = required | {'assets/openbios-sparc64.patched'}
try:
    pins = {}
    for line in Path(sys.argv[1]).read_text(encoding='ascii').splitlines():
        match = re.fullmatch(r'([0-9a-fA-F]{64})  (assets/[^\s]+)', line)
        if not match or match[2] not in allowed or match[2] in pins:
            raise ValueError('Malformed, duplicate, or unexpected manifest entry')
        pins[match[2]] = match[1].lower()
    if not required <= pins.keys():
        raise ValueError('Manifest must pin all three QEMU companions')
    for name, source in zip(names, sys.argv[2:]):
        digest = hashlib.sha256()
        with open(source, 'rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(chunk)
        if digest.hexdigest() != pins['assets/' + name]:
            raise ValueError('Expected-bundle hash mismatch: ' + name)
except (OSError, UnicodeError, ValueError) as error:
    sys.exit('Artifact manifest refusal: ' + str(error))
PY
magic=$(od -An -tx1 -N8 "$wasm_file" | tr -d ' \n')
[[ "$magic" == '0061736d01000000' ]] || { echo 'Not a Wasm v1 binary' >&2; exit 1; }
rg -q 'export.*default|export.*as default' "$module_file" || {
    echo 'JS does not look like an ES6 default factory' >&2; exit 1;
}
node --check --input-type=module < "$module_file"
node --check "$worker_file"
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
mkdir -p "$asset_dir"
for i in 0 1 2; do
    destination="$asset_dir/${names[$i]}"
    [[ -e "$destination" ]] || cp "${sources[$i]}" "$destination"
done
shasum -a 256 "$asset_dir/qemu-system-sparc64.js" \
    "$asset_dir/qemu-system-sparc64.wasm" "$asset_dir/qemu-system-sparc64.worker.js"
echo 'Artifact import complete. This does not establish browser execution or firmware boot.'
echo 'Reload http://localhost:8089/, click Start, and follow ACCEPTANCE.md.'
