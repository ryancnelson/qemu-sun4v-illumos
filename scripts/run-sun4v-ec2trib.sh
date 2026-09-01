#!/usr/bin/bash

set -euo pipefail
umask 077

QEMU_SOURCE=/tink/builds/qemu-sun4v-879fee-tribblix
QEMU=${QEMU_SOURCE}/build/qemu-system-sparc64
QEMU_IMG=/usr/bin/qemu-img

RUN_ROOT=/tink/runs
STATE_ROOT=/tink/vm-state/oi-basecamp
LATEST_LINK=${RUN_ROOT}/oi-basecamp-latest

BASE_RUN=${RUN_ROOT}/ec2-tribblix-smoke-20260827-01
FIRMWARE_SOURCE=${BASE_RUN}/firmware
TARGET_BASE=${BASE_RUN}/proven-lineage-exact/root-unit104.qcow2
CARRIER_BASE=${BASE_RUN}/proven-lineage-exact/carrier-unit100.img
INSTALLER_BASE=/tink/disk-images/workstation-multiuser-raw-20260827T010500Z/artifacts/installer-unit103.img
NVRAM_FACTORY=${FIRMWARE_SOURCE}/nvram1
NVRAM_STATE=${STATE_ROOT}/nvram1

die()
{
    echo "run-sun4v: $*" >&2
    exit 1
}

for required in \
    "$QEMU" \
    "$QEMU_IMG" \
    "$FIRMWARE_SOURCE/q.bin" \
    "$TARGET_BASE" \
    "$CARRIER_BASE" \
    "$INSTALLER_BASE" \
    "$NVRAM_FACTORY"
do
    [[ -e "$required" ]] || die "required artifact is missing: $required"
done

if pgrep -f "$QEMU" >/dev/null 2>&1; then
    echo "A sun4v QEMU process already appears to be running:" >&2
    pgrep -lf "$QEMU" >&2 || true
    exit 1
fi

mkdir -p "$RUN_ROOT" "$STATE_ROOT"

# NVRAM is machine state, not a disposable run artifact. Seed it once from the
# known-good firmware and then let QEMU update the same 8 KiB file on every run.
if [[ ! -f "$NVRAM_STATE" ]]; then
    NVRAM_TEMP=${NVRAM_STATE}.new.$$
    cp -p "$NVRAM_FACTORY" "$NVRAM_TEMP"
    chmod 600 "$NVRAM_TEMP"
    mv -f "$NVRAM_TEMP" "$NVRAM_STATE"
fi

NVRAM_BYTES=$(wc -c < "$NVRAM_STATE" | tr -d ' ')
[[ "$NVRAM_BYTES" = 8192 ]] || die "persistent NVRAM is $NVRAM_BYTES bytes; expected 8192: $NVRAM_STATE"

RUN_ID=oi-basecamp-$(date -u +%Y%m%dT%H%M%SZ)-$$
RUN_DIR=${RUN_ROOT}/${RUN_ID}
mkdir -p "$RUN_DIR/disks" "$RUN_DIR/firmware"

# Each boot gets fresh writable overlays. The previous successful disk state is
# retained as an immutable backing image, so experiments remain reversible.
"$QEMU_IMG" create -q -f qcow2 -F qcow2 -b "$TARGET_BASE" \
    "$RUN_DIR/disks/root-unit104.qcow2"
"$QEMU_IMG" create -q -f qcow2 -F raw -b "$CARRIER_BASE" \
    "$RUN_DIR/disks/carrier-unit100.qcow2"

cp -Rp "$FIRMWARE_SOURCE/." "$RUN_DIR/firmware/"
cp -p "$NVRAM_STATE" "$RUN_DIR/nvram.before.bin"

QEMU_COMMIT=$(git -C "$QEMU_SOURCE" rev-parse HEAD 2>/dev/null || echo unknown)
QEMU_SHA256=$(digest -a sha256 "$QEMU" | sed 's/^.*= //')
QBIN_SHA256=$(digest -a sha256 "$RUN_DIR/firmware/q.bin" | sed 's/^.*= //')
NVRAM_SHA256_BEFORE=$(digest -a sha256 "$RUN_DIR/nvram.before.bin" | sed 's/^.*= //')

cat > "$RUN_DIR/manifest.txt" <<EOF
run_id=$RUN_ID
created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
qemu=$QEMU
qemu_commit=$QEMU_COMMIT
qemu_sha256=$QEMU_SHA256
q_bin_sha256=$QBIN_SHA256
target_backing=$TARGET_BASE
carrier_backing=$CARRIER_BASE
installer_boot_media=$INSTALLER_BASE
persistent_nvram=$NVRAM_STATE
nvram_sha256_before=$NVRAM_SHA256_BEFORE
serial_socket=$RUN_DIR/console.sock
qmp_socket=$RUN_DIR/qmp.sock
EOF

QEMU_ARGS=(
    -name oi-basecamp
    -D "$RUN_DIR/qemu-debug.log"
    -d guest_errors
    -M "niagara,nvram-file=$NVRAM_STATE"
    -L "$RUN_DIR/firmware"
    -m 3072
    -smp 1
    -display none
    -monitor none
    -qmp "unix:$RUN_DIR/qmp.sock,server=on,wait=off"
    -serial "file:$RUN_DIR/serial0.log"
    -chardev "socket,id=guestconsole,path=$RUN_DIR/console.sock,server=on,wait=off,logfile=$RUN_DIR/console.log,logappend=on"
    -serial chardev:guestconsole
    -drive "id=carrier100,format=qcow2,if=none,bus=0,unit=100,readonly=off,cache=none,file.locking=off,backing.file.locking=off,file=$RUN_DIR/disks/carrier-unit100.qcow2"
    -drive "id=installer103,format=raw,if=none,bus=0,unit=103,readonly=on,cache=none,file.locking=off,file=$INSTALLER_BASE"
    -drive "id=target104,format=qcow2,if=none,bus=0,unit=104,readonly=off,cache=none,file.locking=off,backing.file.locking=off,backing.backing.file.locking=off,backing.backing.backing.file.locking=off,file=$RUN_DIR/disks/root-unit104.qcow2"
)

printf '%q ' "$QEMU" "${QEMU_ARGS[@]}" > "$RUN_DIR/qemu-command.sh"
printf '\n' >> "$RUN_DIR/qemu-command.sh"
chmod 600 "$RUN_DIR/qemu-command.sh"

# illumos mv(1) follows a destination symlink to a directory, unlike the GNU
# behavior this runner originally assumed. Replace only the symlink itself.
if [[ -e "$LATEST_LINK" && ! -L "$LATEST_LINK" ]]; then
    die "latest-run path exists and is not a symlink: $LATEST_LINK"
fi
rm -f "$LATEST_LINK"
ln -s "$RUN_DIR" "$LATEST_LINK"

echo "Run directory:  $RUN_DIR"
echo "Serial socket: $RUN_DIR/console.sock"
echo "QMP socket:    $RUN_DIR/qmp.sock"
echo "NVRAM state:  $NVRAM_STATE"
echo "Logs:         $RUN_DIR"
echo
echo "QEMU is starting in the foreground; its console is on the serial socket."

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
cp -p "$NVRAM_STATE" "$RUN_DIR/nvram.after.bin"
NVRAM_SHA256_AFTER=$(digest -a sha256 "$RUN_DIR/nvram.after.bin" | sed 's/^.*= //')
{
    echo "finished_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "qemu_exit_status=$QEMU_STATUS"
    echo "nvram_sha256_after=$NVRAM_SHA256_AFTER"
} >> "$RUN_DIR/manifest.txt"

echo "QEMU exited with status $QEMU_STATUS; artifacts remain in $RUN_DIR"
exit "$QEMU_STATUS"
