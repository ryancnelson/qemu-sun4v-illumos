#!/usr/bin/bash

set -euo pipefail

# Reproducible build/test/run entry point for the Solaris 9 SS-5 lab on
# Tribblix.  Keep every toolchain assumption here; do not reconstruct the
# configure environment in an interactive shell.
export PATH=/usr/versions/llvm/bin:/usr/gnu/bin:/usr/bin:/usr/sbin
export PKG_CONFIG_LIBDIR=/usr/lib/amd64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig

TOOLCHAIN=${TOOLCHAIN:-gcc}
case "$TOOLCHAIN" in
gcc)
    CC=${CC:-gcc}
    CXX=${CXX:-g++}
    ;;
clang)
    CC=${CC:-clang}
    CXX=${CXX:-clang++}
    ;;
*)
    echo "ec2trib-sun4m-lab: TOOLCHAIN must be gcc or clang" >&2
    exit 2
    ;;
esac
export CC CXX

ACTION=${1:-help}
QEMU_TAG=${2:-v7.2.0}
QEMU_SERIES=${QEMU_TAG%.*}
QEMU_GIT=${QEMU_GIT:-/tink/builds/qemu-ss5-v11.0}
QEMU_SOURCE=${QEMU_SOURCE:-/tink/builds/qemu-ss5-${QEMU_SERIES}}
QEMU_BUILD=${QEMU_BUILD:-${QEMU_SOURCE}/build-amd64}
QEMU_BINARY=${QEMU_BINARY:-${QEMU_BUILD}/qemu-system-sparc}
VM_RUNNER=${VM_RUNNER:-/tink/sun4m-solaris9/run-qemu.sh}
MAKE_JOBS=${MAKE_JOBS:-$(psrinfo | wc -l | tr -d ' ')}

die()
{
    echo "ec2trib-sun4m-lab: $*" >&2
    exit 1
}

require_toolchain()
{
    for tool in git bash "$CC" "$CXX" ar gmake pkg-config python3; do
        command -v "$tool" >/dev/null 2>&1 ||
            die "required tool is absent from the pinned PATH: $tool"
    done
}

ensure_worktree()
{
    if [[ -d "$QEMU_SOURCE/.git" || -f "$QEMU_SOURCE/.git" ]]; then
        return
    fi
    [[ ! -e "$QEMU_SOURCE" ]] ||
        die "QEMU source path exists but is not a git worktree: $QEMU_SOURCE"
    git -C "$QEMU_GIT" rev-parse --verify "$QEMU_TAG" >/dev/null ||
        die "QEMU tag is unavailable in $QEMU_GIT: $QEMU_TAG"
    git -C "$QEMU_GIT" worktree add --detach "$QEMU_SOURCE" "$QEMU_TAG"
}

configure_qemu()
{
    [[ -f "$QEMU_BUILD/build.ninja" ]] && return
    mkdir -p "$QEMU_BUILD"
    (
        cd "$QEMU_BUILD"
        # Tribblix /bin/sh lacks the `local` extension used by QEMU's
        # configure script.  Invoke it with Bash instead of trusting its
        # generic /bin/sh shebang.
        bash "$QEMU_SOURCE/configure" \
            --cpu=x86_64 \
            --target-list=sparc-softmmu \
            --disable-plugins \
            --disable-docs \
            --disable-gtk \
            --disable-sdl \
            --disable-opengl \
            --disable-curses \
            --disable-werror \
            --disable-gnutls
    )
}

build_qemu()
{
    require_toolchain
    ensure_worktree
    configure_qemu
    (
        cd "$QEMU_BUILD"
        gmake -j"$MAKE_JOBS" qemu-system-sparc
    )
}

test_qemu()
{
    [[ -x "$QEMU_BINARY" ]] || die "QEMU binary is missing: $QEMU_BINARY"
    "$QEMU_BINARY" --version | head -1
    file "$QEMU_BINARY"
    "$QEMU_BINARY" -machine help | grep -F 'SS-5' >/dev/null ||
        die "QEMU binary does not advertise the SS-5 machine"
    ldd "$QEMU_BINARY" | grep -F libslirp ||
        die "QEMU binary is not linked to libslirp"
    echo "QEMU SPARC smoke test passed: $QEMU_BINARY"
}

run_vm()
{
    local persistent_nvram

    [[ -x "$VM_RUNNER" ]] || die "VM runner is missing: $VM_RUNNER"
    if pgrep -f 'qemu-system-sparc.*Sun Solaris 9' >/dev/null 2>&1; then
        die "Solaris 9 QEMU is already running; halt it before an A/B run"
    fi

    if [[ -n "${PERSISTENT_NVRAM+x}" ]]; then
        persistent_nvram=$PERSISTENT_NVRAM
    elif grep -q 'DEFINE_PROP_STRING("filename"' \
        "$QEMU_SOURCE/hw/rtc/m48t59.c"; then
        persistent_nvram=1
    else
        persistent_nvram=0
    fi

    echo "Persistent NVRAM: $persistent_nvram"
    PERSISTENT_NVRAM=$persistent_nvram \
        QEMU="$QEMU_BINARY" exec "$VM_RUNNER"
}

case "$ACTION" in
build)
    build_qemu
    ;;
test)
    test_qemu
    ;;
build-test)
    build_qemu
    test_qemu
    ;;
run)
    test_qemu
    run_vm
    ;;
build-test-run)
    build_qemu
    test_qemu
    run_vm
    ;;
paths)
    printf 'tag=%s\ntoolchain=%s\ncc=%s\ncxx=%s\nsource=%s\nbuild=%s\nbinary=%s\nrunner=%s\n' \
        "$QEMU_TAG" "$TOOLCHAIN" "$CC" "$CXX" "$QEMU_SOURCE" \
        "$QEMU_BUILD" "$QEMU_BINARY" "$VM_RUNNER"
    ;;
help|-h|--help)
    echo "usage: $0 {build|test|build-test|run|build-test-run|paths} [qemu-tag]"
    echo "example: $0 build-test v7.2.0"
    echo "example: TOOLCHAIN=clang QEMU_BUILD=/tink/builds/qemu-ss5-persistent-nvram/build-clang-amd64 $0 build-test v11.1.0"
    ;;
*)
    die "unknown action: $ACTION"
    ;;
esac
