#!/usr/bin/env bash
set -euo pipefail

project=$(cd "$(dirname "$0")/.." && pwd)
uts=${ILLUMOS_UTS:-$HOME/devel/masa-sun4v/hsimd-version1-candidate/header-worktree-31d3d510/usr/src/uts}
out=${SNET_DRIVER_BUILD:-$project/build/snet}
cc=${SPARC_CC:-sparc64-linux-gnu-gcc-13}
gcc_include=${SPARC_GCC_INCLUDE:-/usr/lib/gcc-cross/sparc64-linux-gnu/13/include}

test -f "$uts/common/sys/mac_provider.h"
test -f "$uts/sun4v/sys/hypervisor_api.h"
command -v "$cc" >/dev/null

mkdir -p "$out"

common_flags=(
    -O2 -m64 -mcpu=ultrasparc -mno-app-regs -msoft-float -ffreestanding
    -fno-pie -fno-pic -fno-strict-aliasing -fno-asynchronous-unwind-tables -nostdinc
    -isystem "$gcc_include"
    -D_KERNEL -D__sun -D__SVR4 -D__sparc -D__sparcv9 -D_LP64
    -I "$uts/sun4v"
    -I "$uts/sun"
    -I "$uts/sparc"
    -I "$uts/common"
)

"$cc" "${common_flags[@]}" -c \
    -o "$out/snet.o" "$project/drivers/snet/snet.c"
"$cc" "${common_flags[@]}" -D_ASM -x assembler-with-cpp -c \
    -o "$out/snet_hcall.o" "$project/drivers/snet/snet_hcall.s"

file "$out/snet.o" "$out/snet_hcall.o"
bash "$project/scripts/check-sparc-kernel-object.sh" \
    "$out/snet.o" "$out/snet_hcall.o"
