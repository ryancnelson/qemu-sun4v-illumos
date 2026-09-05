#!/usr/bin/env bash
set -euo pipefail
project=$(cd "$(dirname "$0")/.." && pwd)
variant=${1:?usage: build-hsimd-driver.sh oi-aio2|s114-mapin1}
uts=${ILLUMOS_UTS:-$HOME/devel/masa-sun4v/hsimd-version1-candidate/header-worktree-31d3d510/usr/src/uts}
out=${HSIMD_DRIVER_BUILD:-$project/build/hsimd-$variant}
cc=${SPARC_CC:-sparc64-linux-gnu-gcc-13}
case "$variant" in
    oi-aio2) version=0.0.6_aio2 ;;
    s114-mapin1) version=0.0.6_s114_mapin1 ;;
    *) echo "unknown hsimd variant: $variant" >&2; exit 2 ;;
esac
test -f "$uts/common/sys/cmlb.h"
command -v "$cc" >/dev/null
mkdir -p "$out"
cp "$project/drivers/hsimd/hsimd.c" "$out/hsimd.c"
if [[ $variant == s114-mapin1 ]]; then
    patch -d "$out" -p1 <"$project/drivers/hsimd/s114-mapin.patch"
fi
flags=(
    -O2 -m64 -mcpu=v9 -mno-app-regs -msoft-float -ffreestanding -fno-pie -fno-pic
    -fno-strict-aliasing -fno-asynchronous-unwind-tables -U_NO_LONGLONG -D_KERNEL -U_ASM_INLINES
    -D_SYSCALL32 -D_SYSCALL32_IMPL -Dsun -D__sun -D__SVR4 -DC2_AUDIT
    -Dsun4u -D__sparcv9 -DOS_OI -D__INLINE__=inline -DGEM_GCC_RUNTIME
    -DDEBUG -DDEBUG_LEVEL=1 "-DVERSION=\"$version\""
    -I "$uts/common" -I "$uts/sparc" -I "$uts/sun"
    -I "$uts/sun4" -I "$uts/sun4v" -I "$uts/sfmmu"
    -Wno-unknown-pragmas -Wno-implicit-function-declaration
)
"$cc" "${flags[@]}" -c "$out/hsimd.c" -o "$out/hsimd.o"
"$cc" "${flags[@]}" -D_ASM -x assembler-with-cpp -c \
    "$project/drivers/hsimd/hsimd_asm.s" -o "$out/hsimd_asm.o"
bash "$project/scripts/check-sparc-kernel-object.sh" \
    "$out/hsimd.o" "$out/hsimd_asm.o"
{
    printf 'variant=%s\nversion=%s\n' "$variant" "$version"
    "$cc" --version | head -1
    sha256sum "$out/hsimd.c" "$out/hsimd.o" "$out/hsimd_asm.o"
} >"$out/build.manifest"
cat "$out/build.manifest"
