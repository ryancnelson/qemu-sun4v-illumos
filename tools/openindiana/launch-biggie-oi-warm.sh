#!/usr/bin/env bash
# Launch the legacy shared-carrier OpenIndiana warm-network topology on Biggie.
# QEMU has no controlling terminal; use only the serial and monitor sockets.
set -euo pipefail

SESSION=${SESSION:-oi-warm-network-biggie-$(date -u +%Y%m%dT%H%M%SZ)}
PROJECT=${PROJECT:-/home/ryan/devel/qemu-sun4v-illumos}
MASA=${MASA:-/home/ryan/devel/masa-sun4v}
RUN_ROOT=${RUN_ROOT:-$MASA/ci/runs}
RUN=$RUN_ROOT/$SESSION
QEMU_SRC=${QEMU_SRC:-$MASA/qemu-tlb-integration/build/qemu-system-sparc64}
FW_SRC=${FW_SRC:-$MASA/ci/nvram-fw/openindiana-20260826T052200Z}
CARRIER_SRC=${CARRIER_SRC:-$MASA/ci/builds/oi-bounded-25g-exa-01/builder-carrier-unit100.img}
MEDIA=${MEDIA:-/home/ryan/devel/niagara-ci/artifacts/releases/ppp-injected-v2-20260825/big-disk.img}
OWNER_SRC=${OWNER_SRC:-$MASA/ci/candidates/tribblix-hsimd-v1-20260825T2255Z/qemu-owner.sh}
CHANNEL_BYTE=${CHANNEL_BYTE:-327680}

die() { echo "FAIL: $*" >&2; exit 1; }
: "${ALLOW_LEGACY_SHARED_CARRIER:?set ALLOW_LEGACY_SHARED_CARRIER=1 after reviewing the unit-100 channel topology}"
[[ $ALLOW_LEGACY_SHARED_CARRIER == 1 ]] || die "legacy shared-carrier topology was not acknowledged"
command -v tmux >/dev/null || die "tmux missing"
command -v socat >/dev/null || die "socat missing"
command -v pppd >/dev/null || die "pppd missing"
[[ -x $QEMU_SRC ]] || die "QEMU missing: $QEMU_SRC"
[[ -f $FW_SRC/openboot.bin && -f $FW_SRC/nvram1 ]] || die "firmware incomplete: $FW_SRC"
[[ -x $OWNER_SRC ]] || die "qemu-owner missing: $OWNER_SRC"
[[ $(stat -c %s "$CARRIER_SRC") == 1073741824 ]] || die "carrier is not exactly 1 GiB"
[[ $(stat -c %s "$MEDIA") == 2791702528 ]] || die "unexpected installer size"
[[ ! -e $RUN ]] || die "run directory already exists: $RUN"
! tmux has-session -t "$SESSION" 2>/dev/null || die "tmux session already exists: $SESSION"
! pgrep -af qemu-system-sparc64 | grep -F "$RUN" >/dev/null || die "QEMU already references run directory"

mkdir -p "$RUN"
cp --reflink=auto --sparse=always "$CARRIER_SRC" "$RUN/carrier-unit100.img"
cp --reflink=auto --sparse=always "$MEDIA" "$RUN/installer-unit103-rw.img"
cp --reflink=auto "$QEMU_SRC" "$RUN/qemu-system-sparc64"
cp "$OWNER_SRC" "$RUN/qemu-owner.sh"
cp -a "$FW_SRC" "$RUN/firmware"
chmod 755 "$RUN/qemu-system-sparc64" "$RUN/qemu-owner.sh"

cat >"$RUN/run.manifest" <<EOF
trial=OI-WARM-NET-BIGGIE
created_utc=$(date -u +%FT%TZ)
session=$SESSION
run=$RUN
qemu=$RUN/qemu-system-sparc64
carrier=$RUN/carrier-unit100.img
channel_byte=$CHANNEL_BYTE
media_source=$MEDIA
media=$RUN/installer-unit103-rw.img
firmware=$RUN/firmware
EOF

NIAGARA_IMG="$RUN/carrier-unit100.img" NIAG_CHAN_HOST_BYTE="$CHANNEL_BYTE" \
  "$PROJECT/tools/chan/host-chan.py" init 0
printf '%s launch-requested\n' "$(date -u +%FT%TZ)" >"$RUN/timestamps.log"

tmux new-session -d -s "$SESSION" -n qemu \
  "$RUN/qemu-owner.sh \"$RUN\" -- \"$RUN/qemu-system-sparc64\" -M niagara -L \"$RUN/firmware\" -m 3072 -smp 1 -serial file:/dev/null -serial unix:\"$RUN/console.sock\",server=on,wait=off -monitor unix:\"$RUN/monitor.sock\",server=on,wait=off -nographic -drive id=carrier100,format=raw,if=none,bus=0,unit=100,readonly=off,cache=none,file=\"$RUN/carrier-unit100.img\" -drive id=media103,format=raw,if=none,bus=0,unit=103,readonly=off,cache=none,file=\"$RUN/installer-unit103-rw.img\""
tmux new-window -d -t "$SESSION" -n console \
  "while [ ! -S \"$RUN/console.sock\" ]; do sleep 1; done; socat -,raw,echo=0 UNIX-CONNECT:\"$RUN/console.sock\""
tmux new-window -d -t "$SESSION" -n host-channel \
  "NIAGARA_IMG=\"$RUN/carrier-unit100.img\" NIAG_CHAN_HOST_BYTE=$CHANNEL_BYTE \"$PROJECT/tools/chan/host-chan.py\" bridge 0 \"$RUN/chan0.sock\" 2>&1 | tee \"$RUN/host-channel.log\""
tmux new-window -d -t "$SESSION" -n host-ppp \
  "while [ ! -S \"$RUN/chan0.sock\" ]; do sleep 1; done; sudo -n env HOST_IP=10.0.5.1 GUEST_IP=10.0.5.15 \"$PROJECT/tools/chan/host-pppd-once.sh\" \"$RUN/chan0.sock\" 2>&1 | tee \"$RUN/host-ppp.log\""
tmux new-window -d -t "$SESSION" -n shell

for _ in $(seq 1 15); do
  [[ -S $RUN/console.sock && -S $RUN/monitor.sock ]] && break
  sleep 1
done
[[ -S $RUN/console.sock && -S $RUN/monitor.sock ]] || die "QEMU sockets did not appear"
QPID=$(<"$RUN/qemu.pid")
kill -0 "$QPID" || die "QEMU is not alive"
echo "PASS: QEMU $QPID is detached in tmux session $SESSION"
echo "Attach: tmux attach -t $SESSION"
echo "At OBP boot with: boot /virtual-devices@100/disk@3:d -k -v"
