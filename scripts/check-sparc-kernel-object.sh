#!/usr/bin/env bash
# SPARC kernel code cannot assume that the FPU register file is available.
set -euo pipefail
[[ $# -gt 0 ]] || { echo 'usage: check-sparc-kernel-object.sh OBJECT...' >&2; exit 2; }
objdump=${SPARC_OBJDUMP:-sparc64-linux-gnu-objdump}
disassembly=$(mktemp)
trap 'rm -f "$disassembly"' EXIT
for object in "$@"; do
    "$objdump" -d --no-show-raw-insn "$object" >"$disassembly"
    # Only instruction lines: symbol names and comments are not opcodes.
    # flush/flushw and the stack-pointer alias %fp are integer instructions.
    if LC_ALL=C awk '
        /^[[:space:]]*[[:xdigit:]]+:/ {
            if (($2 ~ /^f/ && $2 != "flush" && $2 != "flushw") ||
                $0 ~ /%(f[0-9]+|fsr|fprs|fcc[0-9]+|gsr)([^[:alnum:]_]|$)/) {
                print; bad = 1
            }
        }
        END { exit !bad }
    ' "$disassembly"; then
        echo "SPARC_KERNEL_OBJECT=FAIL floating-point instruction in $object" >&2
        exit 1
    fi
    echo "SPARC_KERNEL_OBJECT=PASS $object"
done
