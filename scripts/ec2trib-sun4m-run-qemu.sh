#!/usr/bin/bash

set -euo pipefail

# Solaris 9 / SPARCstation 5 (sun4m), translated from the UTM bundle:
#   Sun Solaris 9.utm/config.plist
#   Sun Solaris 9.utm/Data/debug.log

QEMU=${QEMU:-/tink/builds/qemu-ss5-persistent-nvram/build-amd64/qemu-system-sparc}
VM_ROOT=${VM_ROOT:-/tink/sun4m-solaris9}
RUN_ROOT=${RUN_ROOT:-/tink/runs/sun4m-solaris9}
IMAGE_ROOT=${IMAGE_ROOT:-/tink/disk-images/solaris9-sun4m-utm-20260828/Data}
NVRAM_FILE=${NVRAM_FILE:-/tink/vm-state/sun4m-solaris9/ss5-nvram.bin}
TELNET_HOST_PORT=${TELNET_HOST_PORT:-2323}
CONSOLE_MODE=${CONSOLE_MODE:-socket}
PERSISTENT_NVRAM=${PERSISTENT_NVRAM:-1}

RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)-$$
RUN_DIR="$RUN_ROOT/$RUN_ID"
mkdir -p "$RUN_DIR"
if [[ -L "$VM_ROOT/latest" ]]; then
    rm -f "$VM_ROOT/latest"
elif [[ -e "$VM_ROOT/latest" ]]; then
    echo "Refusing to replace non-symlink: $VM_ROOT/latest" >&2
    exit 1
fi
ln -s "$RUN_DIR" "$VM_ROOT/latest"

for required in \
    "$NVRAM_FILE" \
    "$IMAGE_ROOT/ss5.bin" \
    "$IMAGE_ROOT/disk-0.qcow2" \
    "$IMAGE_ROOT/disk-1.qcow2" \
    "$IMAGE_ROOT/disk-2.qcow2" \
    "$IMAGE_ROOT/disk-3.qcow2" \
    "$IMAGE_ROOT/disk-4.qcow2" \
    "$IMAGE_ROOT/disk-5.qcow2"
do
    if [[ ! -r "$required" ]]; then
        echo "Missing or unreadable VM asset: $required" >&2
        exit 1
    fi
done

QEMU_ARGS=(
    -name "Sun Solaris 9 (SS-5)"
    -uuid A13333B7-E836-4030-B24A-ABA359A422F3
    -machine SS-5,graphics=off
    -accel tcg,tb-size=64
    -smp cpus=1,sockets=1,cores=1,threads=1
    -m 256
    -rtc base=localtime
    -bios "$IMAGE_ROOT/ss5.bin"

    # OpenBoot-style configuration supplied to the emulated NVRAM each launch.
    -prom-env "auto-boot?=true"
    -prom-env "boot-device=disk0"
    -prom-env "input-device=ttya"
    -prom-env "output-device=ttya"

    -net nic,model=lance,macaddr=4E:B0:83:C6:5F:67,netdev=net0
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${TELNET_HOST_PORT}-:23"
    -device scsi-hd,bus=scsi.0,channel=0,scsi-id=0,drive=drive1,bootindex=0
    -drive "if=none,media=disk,id=drive1,format=qcow2,file.driver=file,file.filename=$IMAGE_ROOT/disk-0.qcow2,file.locking=off,discard=unmap,detect-zeroes=unmap"
    -device scsi-hd,bus=scsi.0,channel=0,scsi-id=1,drive=drive0,bootindex=1
    -drive "if=none,media=disk,id=drive0,format=qcow2,file.driver=file,file.filename=$IMAGE_ROOT/disk-1.qcow2,file.locking=off,discard=unmap,detect-zeroes=unmap"
    -device scsi-hd,bus=scsi.0,channel=0,scsi-id=2,drive=drive3,bootindex=2
    -drive "if=none,media=disk,id=drive3,format=qcow2,file.driver=file,file.filename=$IMAGE_ROOT/disk-2.qcow2,file.locking=off,discard=unmap,detect-zeroes=unmap"
    -device scsi-hd,bus=scsi.0,channel=0,scsi-id=3,drive=drive4,bootindex=3
    -drive "if=none,media=disk,id=drive4,format=qcow2,file.driver=file,file.filename=$IMAGE_ROOT/disk-3.qcow2,file.locking=off,discard=unmap,detect-zeroes=unmap"
    -device scsi-hd,bus=scsi.0,channel=0,scsi-id=4,drive=drive5,bootindex=4
    -drive "if=none,media=disk,id=drive5,format=qcow2,file.driver=file,file.filename=$IMAGE_ROOT/disk-4.qcow2,file.locking=off,discard=unmap,detect-zeroes=unmap"
    -device scsi-hd,bus=scsi.0,channel=0,scsi-id=5,drive=drive6,bootindex=5
    -drive "if=none,media=disk,id=drive6,format=qcow2,file.driver=file,file.filename=$IMAGE_ROOT/disk-5.qcow2,file.locking=off,discard=unmap,detect-zeroes=unmap"
    -device scsi-cd,bus=scsi.0,channel=0,scsi-id=6,drive=drive7,bootindex=6
    -drive if=none,media=cdrom,id=drive7,readonly=on
)

case "$PERSISTENT_NVRAM" in
0)
    ;;
1)
    QEMU_ARGS+=( -global "sysbus-m48t08.filename=$NVRAM_FILE" )
    ;;
*)
    echo "PERSISTENT_NVRAM must be 0 or 1" >&2
    exit 2
    ;;
esac

case "$CONSOLE_MODE" in
socket)
    # The UTM VM used TCX; restore these two commented lines when graphical
    # output is wanted, and remove the active -display none.
    QEMU_ARGS+=(
        -display none
        # -vga tcx
        # -display gtk
        -serial "unix:$RUN_DIR/console.sock,server=on,wait=off"
        -monitor "unix:$RUN_DIR/monitor.sock,server=on,wait=off"
        -qmp "unix:$RUN_DIR/qmp.sock,server=on,wait=off"
    )
    ;;
stdio)
    QEMU_ARGS+=(
        -nographic
        -qmp "unix:$RUN_DIR/qmp.sock,server=on,wait=off"
    )
    ;;
*)
    echo "CONSOLE_MODE must be socket or stdio" >&2
    exit 2
    ;;
esac

echo "Run directory:  $RUN_DIR"
echo "QMP:           $RUN_DIR/qmp.sock"
echo "Telnet:        127.0.0.1:$TELNET_HOST_PORT -> guest :23"

if [[ "$CONSOLE_MODE" == stdio ]]; then
    echo "Console:       tmux stdio (-nographic)"
    exec "$QEMU" "${QEMU_ARGS[@]}"
else
    echo "Serial socket: $RUN_DIR/console.sock"
    echo "Monitor:       $RUN_DIR/monitor.sock"
    exec "$QEMU" "${QEMU_ARGS[@]}" \
        >"$RUN_DIR/qemu.stdout.log" \
        2>"$RUN_DIR/qemu.stderr.log"
fi
