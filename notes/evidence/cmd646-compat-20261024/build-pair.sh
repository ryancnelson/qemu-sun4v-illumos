#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
flags=(--target-list=sparc64-softmmu --disable-docs --disable-gtk --disable-sdl
       --disable-vnc --disable-spice --disable-opengl --disable-vte --disable-curses
       --disable-libssh --disable-bzip2 --disable-snappy --disable-lzo --enable-slirp
       --disable-download --disable-install-blobs --disable-curl)
printf '%s\n' "${flags[@]}" > final-configure-flags.txt
for variant in baseline candidate; do
    (
        cd "$variant-build"
        "../$variant-src/configure" "${flags[@]}" > "../$variant-configure-nocurl.log" 2>&1
        ninja -j2 qemu-system-sparc64 > "../$variant-build-nocurl.log" 2>&1
    )
done
python3 check-runtime.py > final-runtime-audit.log 2>&1
mkdir -p artifacts
for variant in baseline candidate; do
    install -m 0555 "$variant-build/qemu-system-sparc64" "artifacts/qemu-system-sparc64.$variant"
done
sha256sum artifacts/* > artifacts/SHA256SUMS
{
    gcc --version
    ld --version
    ninja --version
    meson --version
    python3 --version
    pkg-config --modversion glib-2.0 pixman-1 slirp
} > final-toolchain.txt
