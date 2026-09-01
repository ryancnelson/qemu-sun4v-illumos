#!/usr/bin/env bash

set -euo pipefail
umask 077

ASSET_DIR=${ASSET_DIR:-/assets}
STATE_DIR=${STATE_DIR:-/state}
ROOT_IMAGE=${ROOT_IMAGE:-root-unit104.raw}
ROOT_BYTES=${ROOT_BYTES:-64424509440}
ROOT_UNIT=${ROOT_UNIT:-104}
EMBEDDED_BUNDLE=${EMBEDDED_BUNDLE:-}
EMBEDDED_BUNDLE_SHA256=${EMBEDDED_BUNDLE_SHA256:-}
EMBEDDED_MANIFEST=${EMBEDDED_MANIFEST:-}
EMBEDDED_PREFIX=${EMBEDDED_PREFIX:-sparc64-qemu-openindiana-20g-beta}
EMBEDDED_STATE_DIR=${EMBEDDED_STATE_DIR:-/var/lib/illumos-appliance}
CONSOLE_MODE=${CONSOLE_MODE:-auto}

die()
{
    echo "APPLIANCE_START=FAIL reason=$*" >&2
    exit 1
}

materialize_embedded_assets()
{
    local marker actual_digest

    [[ -n "$EMBEDDED_BUNDLE" ]] || return 0
    [[ -r "$EMBEDDED_BUNDLE" ]] || die "embedded bundle is unreadable"
    [[ -r "$EMBEDDED_MANIFEST" ]] || die "embedded asset manifest is unreadable"
    command -v zstd >/dev/null 2>&1 || die "zstd is unavailable"

    mkdir -p "$EMBEDDED_STATE_DIR"
    marker="$EMBEDDED_STATE_DIR/materialized-v1.manifest"
    ASSET_DIR="$EMBEDDED_STATE_DIR/assets"

    if [[ -e "$marker" ]]; then
        [[ -d "$ASSET_DIR" ]] || die "materialization marker exists without assets"
        echo "EMBEDDED_ASSETS_REUSED=PASS"
        return 0
    fi

    [[ ! -e "$ASSET_DIR" ]] || \
        die "incomplete embedded extraction exists without marker"

    if [[ -n "$EMBEDDED_BUNDLE_SHA256" ]]; then
        actual_digest=$(sha256sum "$EMBEDDED_BUNDLE" | cut -d ' ' -f 1)
        [[ "$actual_digest" = "$EMBEDDED_BUNDLE_SHA256" ]] || \
            die "embedded bundle checksum mismatch"
    else
        actual_digest=not-declared
    fi

    echo "EMBEDDED_ASSETS_EXTRACT=START"
    tar --sparse -I zstd -xf "$EMBEDDED_BUNDLE" \
        -C "$EMBEDDED_STATE_DIR" --strip-components=1 \
        "$EMBEDDED_PREFIX/assets"

    (cd "$ASSET_DIR" && sha256sum -c "$EMBEDDED_MANIFEST") || \
        die "materialized asset verification failed"
    [[ "$(stat -c %s "$ASSET_DIR/root-unit105-20g.raw")" = 21474836480 ]] || \
        die "materialized root has the wrong apparent size"

    cat > "$marker" <<EOF
materialized_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
bundle_sha256=$actual_digest
root_sha256=24306fcf52c9d05c6dd49115f5e2833a3b8563e59d88b923f7022a214308e722
root_apparent_bytes=$(stat -c %s "$ASSET_DIR/root-unit105-20g.raw")
root_allocated_blocks=$(stat -c %b "$ASSET_DIR/root-unit105-20g.raw")
root_block_bytes=$(stat -c %B "$ASSET_DIR/root-unit105-20g.raw")
EOF
    echo "EMBEDDED_ASSETS_EXTRACT=PASS"
    cat "$marker"
}

materialize_embedded_assets

UNIT100_DIR=/run/unit100
UNIT100_PATH=${UNIT100_DIR}/carrier-unit100.raw
UNIT103_PATH=${ASSET_DIR}/installer-unit103.img
UNIT104_PATH=${ASSET_DIR}/${ROOT_IMAGE}
FIRMWARE_SOURCE=${FIRMWARE_DIR:-${ASSET_DIR}/firmware}
FIRMWARE_MANIFEST=${FIRMWARE_MANIFEST:-}
NVRAM_SOURCE=${ASSET_DIR}/nvram1
QEMU=/usr/local/bin/qemu-system-sparc64
EXTRA_DRIVES=()

for required in \
    "$QEMU" \
    "$ASSET_DIR/carrier-unit100.img" \
    "$UNIT103_PATH" \
    "$UNIT104_PATH" \
    "$FIRMWARE_SOURCE/q.bin" \
    "$NVRAM_SOURCE"
do
    [[ -e "$required" ]] || die "required artifact is missing: $required"
done

if [[ -n "$FIRMWARE_MANIFEST" ]]; then
    [[ -r "$FIRMWARE_MANIFEST" ]] || \
        die "firmware manifest is missing: $FIRMWARE_MANIFEST"
    (cd "$FIRMWARE_SOURCE" && sha256sum -c "$FIRMWARE_MANIFEST")
fi

[[ -w "$UNIT104_PATH" ]] || die "unit104 must be writable: $UNIT104_PATH"
[[ "$(stat -c %s "$ASSET_DIR/carrier-unit100.img")" = 1073741824 ]] || \
    die "unit100 has the wrong apparent size"
[[ "$(stat -c %s "$UNIT104_PATH")" = "$ROOT_BYTES" ]] || \
    die "unit104 has the wrong apparent size for $ROOT_IMAGE"

mkdir -p "$UNIT100_DIR" "$STATE_DIR/firmware"
qemu-img convert -q -f raw -O raw -S 4096 \
    "$ASSET_DIR/carrier-unit100.img" "$UNIT100_PATH"

cp -a "$FIRMWARE_SOURCE/." "$STATE_DIR/firmware/"
if [[ ! -e "$STATE_DIR/nvram.bin" ]]; then
    cp -p "$NVRAM_SOURCE" "$STATE_DIR/nvram.bin"
fi
[[ "$(stat -c %s "$STATE_DIR/nvram.bin")" = 8192 ]] || \
    die "working NVRAM is not 8192 bytes"

if [[ "${ATTACH_MIGRATION_TARGET:-0}" = 1 ]]; then
    [[ -e "$ASSET_DIR/root-unit105-20g.raw" ]] || \
        die "migration target is missing"
    [[ -w "$ASSET_DIR/root-unit105-20g.raw" ]] || \
        die "optional unit105 must be writable"
    [[ "$(stat -c %s "$ASSET_DIR/root-unit105-20g.raw")" = 21474836480 ]] || \
        die "optional unit105 has the wrong apparent size"
    EXTRA_DRIVES+=(
        -drive "id=target105,format=raw,if=none,bus=0,unit=105,readonly=off,cache=none,file.locking=off,file=$ASSET_DIR/root-unit105-20g.raw"
    )
fi

case "$CONSOLE_MODE" in
auto)
    if [[ -t 0 && -t 1 ]]; then
        CONSOLE_MODE=stdio
    else
        CONSOLE_MODE=socket
    fi
    ;;
stdio|socket)
    ;;
*)
    die "CONSOLE_MODE must be auto, stdio, or socket"
    ;;
esac

rm -f "$STATE_DIR/console.sock" "$STATE_DIR/qmp.sock"

case "$CONSOLE_MODE" in
stdio)
    GUEST_CONSOLE_ARGS=(
        -chardev "stdio,id=guestconsole,signal=off,logfile=$STATE_DIR/console.log,logappend=on"
        -serial chardev:guestconsole
    )
    ;;
socket)
    GUEST_CONSOLE_ARGS=(
        -chardev "socket,id=guestconsole,path=$STATE_DIR/console.sock,server=on,wait=off,logfile=$STATE_DIR/console.log,logappend=on"
        -serial chardev:guestconsole
    )
    ;;
esac

cat > "$STATE_DIR/runtime-manifest.txt" <<EOF
started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
qemu_commit=049affb20df67162cf58deeaf74d5ad4b83cbdc3
unit100_role=RAM-backed raw channel carrier
unit103_role=read-only installer/boot media
unit104_role=writable ZFS root
unit104_image=$ROOT_IMAGE
unit104_bytes=$ROOT_BYTES
root_unit=$ROOT_UNIT
asset_mode=$([[ -n "$EMBEDDED_BUNDLE" ]] && echo embedded || echo bind-mounted)
console_mode=$CONSOLE_MODE
openboot_command=boot /virtual-devices@100/disk@${ROOT_UNIT}:a -k -v
EOF

echo "APPLIANCE_START=PASS"
if [[ "$CONSOLE_MODE" = stdio ]]; then
    echo "console=stdio"
else
    echo "console_socket=$STATE_DIR/console.sock"
fi
echo "openboot_command=boot /virtual-devices@100/disk@${ROOT_UNIT}:a -k -v"

network_mode=${NIAGARA_NETWORK:-auto}
network_helper=/usr/local/sbin/illumos-appliance-network
if [[ "$network_mode" != off ]]; then
    if [[ ! -x "$network_helper" ]]; then
        if [[ "$network_mode" = required ]]; then
            die "network helpers are required but are not installed"
        fi
        echo "network_helpers=disabled reason=not-installed"
    elif "$network_helper" prepare; then
        /usr/local/sbin/illumos-appliance-network serve \
            >"$STATE_DIR/network-helper.log" 2>&1 &
        network_helper_pid=$!
        echo "$network_helper_pid" >"$STATE_DIR/network-helper.pid"
        echo "network_helpers=started pid=$network_helper_pid"
    elif [[ "$network_mode" = required ]]; then
        die "network helpers are required but their preflight failed"
    else
        echo "network_helpers=disabled"
    fi
fi

# unit100 lives on tmpfs. cache=none makes QEMU request O_DIRECT, which is
# unsupported by tmpfs on otherwise valid Linux hosts (observed on hp2).
# The persistent installer and root disks deliberately retain cache=none.
exec "$QEMU" \
    -name oi-login-docker \
    -D "$STATE_DIR/qemu-debug.log" \
    -d guest_errors \
    -M "niagara,nvram-file=$STATE_DIR/nvram.bin" \
    -L "$STATE_DIR/firmware" \
    -m 3072 \
    -smp 1 \
    -display none \
    -monitor none \
    -qmp "unix:$STATE_DIR/qmp.sock,server=on,wait=off" \
    -serial "file:$STATE_DIR/serial0.log" \
    "${GUEST_CONSOLE_ARGS[@]}" \
    -drive "id=carrier100,format=raw,if=none,bus=0,unit=100,readonly=off,cache=writeback,file.locking=off,file=$UNIT100_PATH" \
    -drive "id=installer103,format=raw,if=none,bus=0,unit=103,readonly=on,cache=none,file.locking=off,file=$UNIT103_PATH" \
    -drive "id=targetroot,format=raw,if=none,bus=0,unit=$ROOT_UNIT,readonly=off,cache=none,file.locking=off,file=$UNIT104_PATH" \
    "${EXTRA_DRIVES[@]}"
