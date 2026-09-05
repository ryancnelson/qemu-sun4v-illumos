#!/usr/bin/env bash
set -euo pipefail

repo=${1:?usage: apply-snet-qemu-overlay.sh QEMU_SOURCE_TREE}
project=$(cd "$(dirname "$0")/.." && pwd)

test -f "$repo/hw/sparc64/niagara.c"
test -f "$repo/hw/sparc64/meson.build"
grep -q 'NIAGARA_FPGA_UART_BASE' "$repo/hw/sparc64/niagara.c"

install -D -m 0644 "$project/qemu-overlay/hw/net/sun4v_snet.c" \
    "$repo/hw/net/sun4v_snet.c"
install -D -m 0644 "$project/qemu-overlay/include/hw/net/sun4v_snet.h" \
    "$repo/include/hw/net/sun4v_snet.h"

python3 "$project/tools/snet/patch_niagara.py" "$repo"

