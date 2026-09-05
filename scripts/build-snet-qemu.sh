#!/usr/bin/env bash
set -euo pipefail

project=$(cd "$(dirname "$0")/.." && pwd)
base=${QEMU_BASE:-$HOME/devel/masa-sun4v/qemu}
source_tree=${QEMU_SNET_SOURCE:-$project/build/qemu-snet-source}
build_tree=${QEMU_SNET_BUILD:-$project/build/qemu-snet-build}
revision=${QEMU_REVISION:-879fee341a}

test -d "$base/.git"

if [[ ! -d "$source_tree/.git" ]]; then
    mkdir -p "$(dirname "$source_tree")"
    git clone --shared "$base" "$source_tree"
fi

git -C "$source_tree" checkout --detach "$revision"
"$project/scripts/apply-snet-qemu-overlay.sh" "$source_tree"

mkdir -p "$build_tree"
(
    cd "$build_tree"
    "$source_tree/configure" \
        --target-list=sparc64-softmmu \
        --disable-docs \
        --disable-gtk \
        --disable-sdl \
        --disable-spice \
        --disable-werror \
        --prefix="$build_tree/install" \
        --python="$(command -v python3)" \
        --cross-prefix=
)

ninja -C "$build_tree" qemu-system-sparc64
"$build_tree/qemu-system-sparc64" -device sun4v-snet,help >/dev/null

printf '%s\n' "$build_tree/qemu-system-sparc64"
