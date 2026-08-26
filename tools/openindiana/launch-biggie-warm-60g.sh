#!/usr/bin/env bash
# Launch a run-isolated Biggie copy of the proven OpenIndiana archive-builder
# topology, with an additional labelled 60 GiB hSIMD disk at unit 104.
set -euo pipefail

: "${RUN_ID:?set RUN_ID to a unique trial/session name}"
RUN_DIR=${RUN_DIR:-/home/ryan/devel/masa-sun4v/ci/runs/$RUN_ID}
SOURCE_RUN=${SOURCE_RUN:-/home/ryan/devel/masa-sun4v/ci/runs/oi-warm-network-biggie-02}
SOURCE_MEDIA=${SOURCE_MEDIA:-/home/ryan/devel/niagara-ci/artifacts/releases/ppp-injected-v2-20260825/big-disk.img}
SOURCE_MEDIA_SIZE=${SOURCE_MEDIA_SIZE:-2791702528}
EXTRA60_SOURCE=${EXTRA60_SOURCE:-}
VTOC_TOOL=${VTOC_TOOL:-/home/ryan/devel/qemu-sun4v-illumos/tools/vtoc.py}

die() { printf 'PRECHECK FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

[[ $(hostname) == biggie ]] || die "wrong host: $(hostname)"
[[ ! -e $RUN_DIR ]] || die "run directory exists: $RUN_DIR"
tmux has-session -t "$RUN_ID" 2>/dev/null && die "tmux session exists: $RUN_ID"

QEMU_SOURCE=$SOURCE_RUN/qemu-system-sparc64
FIRMWARE_SOURCE=$SOURCE_RUN/firmware
CARRIER_SOURCE=$SOURCE_RUN/carrier-unit100.img
OWNER_SOURCE=$SOURCE_RUN/qemu-owner.sh
for path in "$QEMU_SOURCE" "$FIRMWARE_SOURCE/openboot.bin" \
            "$FIRMWARE_SOURCE/q.bin" "$FIRMWARE_SOURCE/nvram1" \
            "$CARRIER_SOURCE" "$SOURCE_MEDIA" "$OWNER_SOURCE" "$VTOC_TOOL"; do
    [[ -e $path ]] || die "missing source artifact: $path"
done
[[ -x $QEMU_SOURCE ]] || die "QEMU source is not executable"
[[ $(stat -c %s "$SOURCE_MEDIA") -eq $SOURCE_MEDIA_SIZE ]] || die "unexpected installer size"
[[ $(stat -c %s "$CARRIER_SOURCE") -eq 1073741824 ]] || die "unexpected carrier size"
[[ $(stat -c %s "$FIRMWARE_SOURCE/nvram1") -eq 8192 ]] || die "bad source NVRAM size"
command -v parted >/dev/null || die "parted is required for the Sun disk label"
command -v socat >/dev/null || die "socat is required for socket console"

for path in "$QEMU_SOURCE" "$CARRIER_SOURCE" "$SOURCE_MEDIA"; do
    if command -v lsof >/dev/null && lsof "$path" 2>/dev/null | grep -q .; then
        die "source artifact is open: $path"
    fi
done

free_bytes=$(df --output=avail -B1 "$(dirname "$RUN_DIR")" | tail -1)
[[ $free_bytes -ge $((70 * 1024 * 1024 * 1024)) ]] || die "less than 70 GiB free"
pass "host, source identity, exclusivity, and capacity"

mkdir -p "$RUN_DIR/images" "$RUN_DIR/firmware"
install -m 0755 "$QEMU_SOURCE" "$RUN_DIR/qemu-system-sparc64"
cp -a "$FIRMWARE_SOURCE/." "$RUN_DIR/firmware/"
install -m 0755 "$OWNER_SOURCE" "$RUN_DIR/qemu-owner.sh"
cp --reflink=auto --sparse=always "$CARRIER_SOURCE" "$RUN_DIR/images/carrier-unit100.img"
cp --reflink=auto --sparse=always "$SOURCE_MEDIA" "$RUN_DIR/images/installer-unit103-rw.img"
chmod 0644 "$RUN_DIR/images/installer-unit103-rw.img"
[[ -w $RUN_DIR/images/installer-unit103-rw.img ]] || \
    die "run-local unit 103 is not writable"

EXTRA60=$RUN_DIR/images/extra-unit104-60g.img
if [[ -n $EXTRA60_SOURCE ]]; then
    [[ -f $EXTRA60_SOURCE ]] || die "missing preseeded 60 GiB source: $EXTRA60_SOURCE"
    [[ $(stat -c %s "$EXTRA60_SOURCE") -eq 64424509440 ]] || \
        die "preseeded source is not 60 GiB"
    cp --reflink=auto --sparse=always "$EXTRA60_SOURCE" "$EXTRA60"
else
    truncate -s 60G "$EXTRA60"
    parted -s "$EXTRA60" mklabel sun
    python3 "$VTOC_TOOL" set-geometry "$EXTRA60" 7831 2 255 63
    python3 "$VTOC_TOOL" set "$EXTRA60" 0 1 125788950
    python3 "$VTOC_TOOL" set "$EXTRA60" 2 0 125829120
fi
python3 "$VTOC_TOOL" verify "$EXTRA60"
[[ $(stat -c %s "$EXTRA60") -eq 64424509440 ]] || die "extra disk is not 60 GiB"
chmod 0664 "$EXTRA60"
[[ -w $EXTRA60 ]] || die "run-local unit 104 is not writable"
pass "run-local media and valid labelled 60 GiB unit-104 disk"

QEMU=$RUN_DIR/qemu-system-sparc64
FIRMWARE=$RUN_DIR/firmware
CARRIER=$RUN_DIR/images/carrier-unit100.img
INSTALLER=$RUN_DIR/images/installer-unit103-rw.img
CONSOLE=$RUN_DIR/console.sock
MONITOR=$RUN_DIR/monitor.sock

QEMU_ARGS=(
    "$QEMU" -M niagara -L "$FIRMWARE" -m 3072 -smp 1
    -serial file:/dev/null
    -serial "unix:$CONSOLE,server=on,wait=off"
    -monitor "unix:$MONITOR,server=on,wait=off"
    -nographic
    -drive "id=carrier100,format=raw,if=none,bus=0,unit=100,readonly=off,cache=none,file=$CARRIER"
    -drive "id=media103,format=raw,if=none,bus=0,unit=103,readonly=off,cache=none,file=$INSTALLER"
    -drive "id=extra104,format=raw,if=none,bus=0,unit=104,readonly=off,cache=none,file=$EXTRA60"
)
printf '%q ' "${QEMU_ARGS[@]}" >"$RUN_DIR/qemu.argv"
printf '\n' >>"$RUN_DIR/qemu.argv"
printf '%s\n' \
    "trial=$RUN_ID" \
    'host=biggie' \
    "session=$RUN_ID" \
    "source_media=$SOURCE_MEDIA" \
    "source_media_size=$SOURCE_MEDIA_SIZE" \
    "extra60_source=${EXTRA60_SOURCE:-new-labelled-disk}" \
    "qemu=$QEMU" \
    "firmware=$FIRMWARE" \
    "unit100=$CARRIER" \
    "unit103=$INSTALLER" \
    'unit103_writable=yes' \
    "unit104=$EXTRA60" \
    'unit104_size_bytes=64424509440' \
    'boot_command=boot /virtual-devices@100/disk@3:d -k -v' \
    >"$RUN_DIR/run.manifest"

tmux new-session -d -s "$RUN_ID" -n shell
qemu_command=$(<"$RUN_DIR/qemu.argv")
tmux new-window -t "$RUN_ID" -n owner \
    "$RUN_DIR/qemu-owner.sh '$RUN_DIR' -- $qemu_command"
tmux new-window -t "$RUN_ID" -n console \
    "while [ ! -S '$CONSOLE' ]; do sleep 1; done; exec socat STDIO,rawer,echo=0 UNIX-CONNECT:'$CONSOLE'"
tmux pipe-pane -t "$RUN_ID:console" -o "cat >>'$RUN_DIR/console.log'"

for _ in $(seq 1 60); do
    tmux capture-pane -pt "$RUN_ID:console" -S -40 2>/dev/null | grep -Eq '^ok[[:space:]]*$' && break
    sleep 1
done
tmux capture-pane -pt "$RUN_ID:console" -S -80 2>/dev/null | grep -Eq '^ok[[:space:]]*$' || \
    die "OpenBoot prompt did not appear within 60 seconds"
grep -Fq 'unit:0 slice2 size:1073741824' "$RUN_DIR/qemu.log" || \
    die "unit 100 did not enumerate at the expected size"
grep -Fq "unit:3 slice2 size:$SOURCE_MEDIA_SIZE" "$RUN_DIR/qemu.log" || \
    die "unit 103 did not enumerate at the expected size"
grep -Fq 'unit:4 slice2 size:64424509440' "$RUN_DIR/qemu.log" || \
    die "unit 104 did not enumerate at 60 GiB"
! grep -Fq 'blk_set_perm failed' "$RUN_DIR/qemu.log" || \
    die "QEMU could not acquire requested disk permissions"
pass "QEMU admitted units 100, 103, and 104 with writable backends"
tmux send-keys -t "$RUN_ID:console" \
    'boot /virtual-devices@100/disk@3:d -k -v' Enter
printf '%s boot-command-sent\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$RUN_DIR/timestamps.log"

pass "QEMU launched in persistent tmux and boot command sent"
printf 'SESSION=%s\nRUN_DIR=%s\n' "$RUN_ID" "$RUN_DIR"
