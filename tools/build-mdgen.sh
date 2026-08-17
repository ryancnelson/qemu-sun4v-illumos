#!/usr/bin/env bash
# Build Sun's mdgen (Machine Description compiler) for x86 Linux.
#
# mdgen turns .pdesc/.hdesc text into the binary MD blobs the Niagara
# machine loads (1up-md.bin, 1up-hv.bin). It is host code, not SPARC code,
# so it cross-builds fine — Sun just never built it on a little-endian host.
#
# Two fixes are required (patches/0002-mdgen-x86-crossbuild.patch):
#   1. output_bin.c / output_text.c had a literal
#      "#error FIXME: Define byte reversal functions for network byte ordering"
#      in the !_BIG_ENDIAN branch. Supplied via <endian.h>.
#   2. output_bin.c PE_int case wrote mde.d.prop_val WITHOUT hton64().
#      Latent bug — invisible on SPARC (hton64 is identity there), corrupts
#      every integer property when built on x86.
#
# Verified: with both fixes, regenerating from
#   ~/vms/opensparc/legion/src/config/niagara/{1up.pdesc,1up.hdesc}
# reproduces the shipped 1up-md.bin and 1up-hv.bin BYTE-IDENTICALLY.
#
# Usage: tools/build-mdgen.sh [outdir]     (default: build/mdgen)

set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENSPARC="${OPENSPARC:-$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)/vms/opensparc}"
MDSRC="$OPENSPARC/hypervisor/src/md/mdgen"
INCDIR="$OPENSPARC/hypervisor/src/include"
OUT="${1:-$PROJ/build/mdgen}"
PATCH="$PROJ/patches/0002-mdgen-x86-crossbuild.patch"

for f in "$MDSRC/mdmain.c" "$INCDIR/md/md_impl.h" "$PATCH"; do
    [[ -f "$f" ]] || { echo "ERROR: missing $f" >&2; exit 1; }
done
command -v flex >/dev/null || { echo "ERROR: flex not installed" >&2; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT"; cd "$OUT"

cp "$MDSRC"/*.c "$MDSRC"/*.h "$MDSRC"/mdlex.l .
patch -p1 --quiet < "$PATCH"

# mdlex.l uses the mdlex* symbol prefix (see mdgen/Makefile: $(LEX) -Pmdlex)
flex -Pmdlex -omdlex.c mdlex.l

# -include stdint.h: md_impl.h uses uint32_t/uint64_t without including it
#                    (Sun's headers pulled it in transitively)
# -fcommon:          2007-era tentative definitions
gcc -O2 -w -fcommon -include stdint.h -I"$INCDIR" -o mdgen \
    mdmain.c mdparse.c mdlex.c output_bin.c output_text.c output_dot.c \
    allocate.c warning.c fatal.c vfatal.c

echo "built: $OUT/mdgen"
