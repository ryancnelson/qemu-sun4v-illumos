#!/usr/bin/env bash
# Compile a Machine Description source (.pdesc / .hdesc) to a binary MD blob.
#
#   tools/gen-md.sh <src.pdesc|src.hdesc> <out.bin>
#
# The .pdesc/.hdesc sources use PRE-ANSI cpp: token pasting via `name/**/x`,
# which relies on comment removal producing a paste. GNU cpp only does this
# in -traditional-cpp mode. Sun used /usr/ccs/lib/cpp (a K&R cpp).
#
# Pipeline mirrors OpenSPARC's own Makefile
# (hypervisor/src/greatlakes/ontario/t1_fpga/configs/Makefile):
#     cpp   src.pdesc  src-md.pp
#     mdgen --binary --outfile src-md.bin src-md.pp
#
# Canonical sources for the Niagara VM we run:
#   ~/vms/opensparc/legion/src/config/niagara/1up.pdesc  -> 1up-md.bin
#   ~/vms/opensparc/legion/src/config/niagara/1up.hdesc  -> 1up-hv.bin
# Both verified to regenerate the shipped blobs byte-identically.

set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MDGEN="${MDGEN:-$PROJ/build/mdgen/mdgen}"

[[ $# -eq 2 ]] || { echo "usage: $0 <src.pdesc|src.hdesc> <out.bin>" >&2; exit 1; }
SRC="$1"; OUT="$2"

[[ -f "$SRC" ]]   || { echo "ERROR: no such source: $SRC" >&2; exit 1; }
[[ -x "$MDGEN" ]] || { echo "ERROR: mdgen not built. Run tools/build-mdgen.sh" >&2; exit 1; }

PP="$(mktemp --suffix=.pp)"
trap 'rm -f "$PP"' EXIT

# -I <srcdir> so `#include "common.pdesc"` resolves next to the source
cpp -traditional-cpp -P -I "$(dirname "$SRC")" "$SRC" > "$PP"
"$MDGEN" --binary --outfile "$OUT" "$PP"

echo "generated: $OUT ($(stat -c%s "$OUT") bytes)"
