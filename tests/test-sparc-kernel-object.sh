#!/usr/bin/env bash
set -euo pipefail
project=$(cd "$(dirname "$0")/.." && pwd)
assembler=${SPARC_AS:-sparc64-linux-gnu-as}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
check="$project/scripts/check-sparc-kernel-object.sh"
cat >"$scratch/integer.s" <<'ASM'
.text
.global fixture
fixture:
    save %sp, -176, %sp
    mov %fp, %i0
    flush %g0
    flushw
    ret
    restore
ASM
"$assembler" -64 -Av9 -o "$scratch/integer.o" "$scratch/integer.s"
bash "$check" "$scratch/integer.o"
for instruction in 'ld [%g5], %f8' 'fba fixture' 'fbe %fcc1, fixture' 'rd %fprs, %g1' 'rd %gsr, %g1'; do
    printf '.text\nfixture:\n    %s\n    nop\n' "$instruction" >"$scratch/float.s"
    "$assembler" -64 -Av9a -o "$scratch/float.o" "$scratch/float.s"
    if bash "$check" "$scratch/float.o"; then
        echo "FAIL: accepted $instruction" >&2
        exit 1
    fi
done
echo SPARC_KERNEL_OBJECT_TEST=PASS
