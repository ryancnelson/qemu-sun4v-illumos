#!/usr/bin/bash

set -euo pipefail
umask 077

QEMU_SOURCE=/tink/builds/qemu-sun4v-879fee-tribblix
QEMU=${QEMU_SOURCE}/build/qemu-system-sparc64
QEMU_IMG=/usr/bin/qemu-img

RUN_ROOT=/tink/runs
UNIT100_RAM_ROOT=${UNIT100_RAM_ROOT:-/tmp}
CONSOLE_WAIT=${CONSOLE_WAIT:-off}
SMP_CPUS=${SMP_CPUS:-1}
GDB_STUB=${GDB_STUB:-off}
BASE_RUN=${RUN_ROOT}/ec2-tribblix-smoke-20260827-01
FIRMWARE_SOURCE=${FIRMWARE_SOURCE:-${BASE_RUN}/firmware}
CARRIER_BASE=${BASE_RUN}/proven-lineage-exact/carrier-unit100.img
CARRIER_CHANNEL_BYTE=327680
CARRIER_GUEST_DEV=/dev/rdsk/c1d0s2
CARRIER_GUEST_BLOCK=640
INSTALLER_BASE=/tink/disk-images/workstation-multiuser-raw-20260827T010500Z/artifacts/installer-unit103.img
NVRAM_SOURCE=/tink/vm-state/oi-basecamp/nvram1

TARGET_DISK=${1:-/tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/baselines/unit104-login-proven-20260826T210446Z.raw}
TARGET_BYTES=64424509440
TARGET_POOL_GUID=18135893029031842473
TARGET_BASE_SHA256=964d10a2f0bba82bffb940db4e30c7fb111f27b6acd3400d0da6fe826ecc3fbd

die()
{
    echo "run-sun4v-login-raw-trial: $*" >&2
    exit 1
}

case "$CONSOLE_WAIT" in
on|off)
    ;;
*)
    die "CONSOLE_WAIT must be on or off: $CONSOLE_WAIT"
    ;;
esac

case "$GDB_STUB" in
on|off)
    ;;
*)
    die "GDB_STUB must be on or off: $GDB_STUB"
    ;;
esac

[[ "$SMP_CPUS" =~ ^[1-8]$ ]] || \
    die "SMP_CPUS must be an integer from 1 through 8: $SMP_CPUS"

if (( SMP_CPUS > 1 )); then
    GUEST_MD_PP=${FIRMWARE_SOURCE}/2c8t_guest.pp.bak
    HV_MD_PP=${FIRMWARE_SOURCE}/2c8t_hv.pp.bak
    [[ -r "$GUEST_MD_PP" ]] || \
        die "preprocessed guest MD evidence is missing: $GUEST_MD_PP"
    [[ -r "$HV_MD_PP" ]] || \
        die "preprocessed hypervisor MD evidence is missing: $HV_MD_PP"

    GUEST_MD_CPUS=$(awk '$1 == "node" && $2 == "cpu" { count++ } END { print count + 0 }' \
        "$GUEST_MD_PP")
    HV_MD_CPUS=$(awk '$1 == "node" && $2 == "cpu" { count++ } END { print count + 0 }' \
        "$HV_MD_PP")
    [[ "$GUEST_MD_CPUS" = "$SMP_CPUS" ]] || \
        die "guest MD describes $GUEST_MD_CPUS CPUs; expected $SMP_CPUS"
    [[ "$HV_MD_CPUS" = "$SMP_CPUS" ]] || \
        die "hypervisor MD describes $HV_MD_CPUS CPUs; expected $SMP_CPUS"
fi

for required in \
    "$QEMU" \
    "$QEMU_IMG" \
    "$FIRMWARE_SOURCE/q.bin" \
    "$CARRIER_BASE" \
    "$INSTALLER_BASE" \
    "$NVRAM_SOURCE" \
    "$TARGET_DISK"
do
    [[ -e "$required" ]] || die "required artifact is missing: $required"
done

[[ -f "$TARGET_DISK" ]] || die "unit104 target is not a regular file: $TARGET_DISK"
[[ -w "$TARGET_DISK" ]] || die "unit104 target is not writable: $TARGET_DISK"

TARGET_ACTUAL_BYTES=$(wc -c < "$TARGET_DISK" | tr -d ' ')
[[ "$TARGET_ACTUAL_BYTES" = "$TARGET_BYTES" ]] || \
    die "unit104 target is $TARGET_ACTUAL_BYTES bytes; expected $TARGET_BYTES"

NVRAM_BYTES=$(wc -c < "$NVRAM_SOURCE" | tr -d ' ')
[[ "$NVRAM_BYTES" = 8192 ]] || \
    die "NVRAM source is $NVRAM_BYTES bytes; expected 8192: $NVRAM_SOURCE"

if pgrep -f "$QEMU" >/dev/null 2>&1; then
    echo "A sun4v QEMU process already appears to be running:" >&2
    pgrep -lf "$QEMU" >&2 || true
    exit 1
fi

if zpool list -H -o guid 2>/dev/null | grep -Fx "$TARGET_POOL_GUID" >/dev/null; then
    die "inner pool $TARGET_POOL_GUID is still imported on the Tribblix host"
fi

if lofiadm 2>/dev/null | grep -F "$TARGET_DISK" >/dev/null; then
    die "unit104 target still has a Tribblix lofi attachment"
fi

RUN_ID=${RUN_ID:-oi-login-raw-$(date -u +%Y%m%dT%H%M%SZ)-$$}
[[ "$RUN_ID" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || \
    die "run ID contains unsafe characters: $RUN_ID"
RUN_DIR=${RUN_ROOT}/${RUN_ID}
[[ ! -e "$RUN_DIR" ]] || die "run directory already exists: $RUN_DIR"
mkdir -p "$RUN_DIR/firmware"

UNIT100_FS=$(/usr/sbin/df -n "$UNIT100_RAM_ROOT" 2>/dev/null | awk '{ print $NF }')
[[ "$UNIT100_FS" = tmpfs ]] || \
    die "unit100 RAM root is not tmpfs: $UNIT100_RAM_ROOT ($UNIT100_FS)"

UNIT100_REQUIRED_KIB=$((($(wc -c < "$CARRIER_BASE") + 1023) / 1024))
UNIT100_AVAILABLE_KIB=$(/usr/sbin/df -k "$UNIT100_RAM_ROOT" | awk 'NR == 2 { print $4 }')
[[ "$UNIT100_AVAILABLE_KIB" -ge "$UNIT100_REQUIRED_KIB" ]] || \
    die "unit100 needs ${UNIT100_REQUIRED_KIB} KiB in tmpfs; only ${UNIT100_AVAILABLE_KIB} KiB available"

UNIT100_DIR=${UNIT100_RAM_ROOT%/}/${RUN_ID}
UNIT100_PATH=$UNIT100_DIR/carrier-unit100.raw
mkdir "$UNIT100_DIR"

cleanup_unit100()
{
    if [[ -n "${UNIT100_PATH:-}" && -e "$UNIT100_PATH" ]]; then
        rm -f -- "$UNIT100_PATH"
    fi
    if [[ -n "${UNIT100_DIR:-}" && -d "$UNIT100_DIR" ]]; then
        rmdir -- "$UNIT100_DIR" 2>/dev/null || true
    fi
}
trap cleanup_unit100 EXIT

# Unit 100 is the carrier/channel object.  The host mailbox bridge performs
# direct pread/pwrite against the same plain image QEMU presents to the guest;
# a qcow2 overlay would split guest writes from host reads.  Give every trial a
# writable raw copy in confirmed tmpfs and never substitute it for a boot or
# root disk.  Tribblix tmpfs charges the full apparent size even when the source
# is sparse, so capacity is checked above and the copy is removed on exit.
"$QEMU_IMG" convert -q -f raw -O raw -S 4096 "$CARRIER_BASE" \
    "$UNIT100_PATH"

CARRIER_BASE_SHA256=$(/usr/bin/digest -a sha256 "$CARRIER_BASE")
UNIT100_SHA256=$(/usr/bin/digest -a sha256 "$UNIT100_PATH")
[[ "$UNIT100_SHA256" = "$CARRIER_BASE_SHA256" ]] || \
    die "tmpfs unit100 copy does not match its accepted source"

cp -Rp "$FIRMWARE_SOURCE/." "$RUN_DIR/firmware/"
cp -p "$NVRAM_SOURCE" "$RUN_DIR/nvram.before.bin"
cp -p "$NVRAM_SOURCE" "$RUN_DIR/nvram.bin"

QEMU_COMMIT=$(git -C "$QEMU_SOURCE" rev-parse HEAD 2>/dev/null || echo unknown)
QEMU_SHA256=$(/usr/bin/digest -a sha256 "$QEMU")
QBIN_SHA256=$(/usr/bin/digest -a sha256 "$RUN_DIR/firmware/q.bin")
MD_SHA256=$(/usr/bin/digest -a sha256 "$RUN_DIR/firmware/md.bin")
HV_SHA256=$(/usr/bin/digest -a sha256 "$RUN_DIR/firmware/hv.bin")
NVRAM_SHA256_BEFORE=$(/usr/bin/digest -a sha256 "$RUN_DIR/nvram.before.bin")

cat > "$RUN_DIR/manifest.txt" <<EOF
run_id=$RUN_ID
created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
qemu=$QEMU
qemu_commit=$QEMU_COMMIT
qemu_sha256=$QEMU_SHA256
q_bin_sha256=$QBIN_SHA256
smp_cpus=$SMP_CPUS
firmware_source=$FIRMWARE_SOURCE
md_sha256=$MD_SHA256
hv_sha256=$HV_SHA256
unit100_role=carrier/channel
unit100_backing=$CARRIER_BASE
unit100_backing_sha256=$CARRIER_BASE_SHA256
unit100_storage=tmpfs
unit100_path=$UNIT100_PATH
unit100_initial_sha256=$UNIT100_SHA256
unit100_channel_host_byte=$CARRIER_CHANNEL_BYTE
unit100_channel_guest_dev=$CARRIER_GUEST_DEV
unit100_channel_guest_block=$CARRIER_GUEST_BLOCK
unit103_role=installer/boot-media
unit103_path=$INSTALLER_BASE
unit104_role=writable-login-trial-root
unit104_path=$TARGET_DISK
unit104_bytes=$TARGET_ACTUAL_BYTES
unit104_inner_pool_guid=$TARGET_POOL_GUID
unit104_accepted_base_sha256=$TARGET_BASE_SHA256
nvram_source=$NVRAM_SOURCE
nvram_sha256_before=$NVRAM_SHA256_BEFORE
openboot_command=boot /virtual-devices@100/disk@4:a -k -v
console_wait=$CONSOLE_WAIT
serial_socket=$RUN_DIR/console.sock
qmp_socket=$RUN_DIR/qmp.sock
gdb_stub=$GDB_STUB
gdb_socket=$RUN_DIR/gdb.sock
EOF

QEMU_ARGS=(
    -name oi-login-raw
    -D "$RUN_DIR/qemu-debug.log"
    -d guest_errors
    -M "niagara,nvram-file=$RUN_DIR/nvram.bin"
    -L "$RUN_DIR/firmware"
    -m 3072
    -smp "$SMP_CPUS"
    -display none
    -monitor none
    -qmp "unix:$RUN_DIR/qmp.sock,server=on,wait=off"
    -serial "file:$RUN_DIR/serial0.log"
    -chardev "socket,id=guestconsole,path=$RUN_DIR/console.sock,server=on,wait=$CONSOLE_WAIT,logfile=$RUN_DIR/console.log,logappend=on"
    -serial chardev:guestconsole
    -drive "id=carrier100,format=raw,if=none,bus=0,unit=100,readonly=off,cache=writeback,file.locking=off,file=$UNIT100_PATH"
    -drive "id=installer103,format=raw,if=none,bus=0,unit=103,readonly=on,cache=none,file.locking=off,file=$INSTALLER_BASE"
    -drive "id=target104,format=raw,if=none,bus=0,unit=104,readonly=off,cache=none,file.locking=off,file=$TARGET_DISK"
)

if [[ "$GDB_STUB" = on ]]; then
    QEMU_ARGS+=(
        -gdb "unix:$RUN_DIR/gdb.sock,server=on,wait=off"
    )
fi

printf '%q ' "$QEMU" "${QEMU_ARGS[@]}" > "$RUN_DIR/qemu-command.sh"
printf '\n' >> "$RUN_DIR/qemu-command.sh"
chmod 600 "$RUN_DIR/qemu-command.sh"

echo "$RUN_DIR" > /tink/runs/oi-login-raw-latest.path
echo "Run directory:   $RUN_DIR"
echo "Serial socket:  $RUN_DIR/console.sock"
echo "QMP socket:     $RUN_DIR/qmp.sock"
if [[ "$GDB_STUB" = on ]]; then
    echo "GDB socket:     $RUN_DIR/gdb.sock"
fi
echo "Writable unit104: $TARGET_DISK"
echo "OpenBoot command: boot /virtual-devices@100/disk@4:a -k -v"

"$QEMU" "${QEMU_ARGS[@]}" \
    > "$RUN_DIR/qemu.stdout.log" \
    2> "$RUN_DIR/qemu.stderr.log" &
QEMU_PID=$!
echo "$QEMU_PID" > "$RUN_DIR/qemu.pid"

forward_term()
{
    kill -TERM "$QEMU_PID" 2>/dev/null || true
}
trap forward_term HUP TERM

set +e
wait "$QEMU_PID"
QEMU_STATUS=$?
set -e

trap - HUP TERM
cp -p "$RUN_DIR/nvram.bin" "$RUN_DIR/nvram.after.bin"
NVRAM_SHA256_AFTER=$(/usr/bin/digest -a sha256 "$RUN_DIR/nvram.after.bin")
{
    echo "finished_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "qemu_exit_status=$QEMU_STATUS"
    echo "nvram_sha256_after=$NVRAM_SHA256_AFTER"
} >> "$RUN_DIR/manifest.txt"

cleanup_unit100
trap - EXIT
echo "unit100_removed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$RUN_DIR/manifest.txt"

echo "QEMU exited with status $QEMU_STATUS; artifacts remain in $RUN_DIR"
exit "$QEMU_STATUS"
