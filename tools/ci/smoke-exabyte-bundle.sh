#!/usr/bin/env bash
# niagara-exabyte-smoke.sh -- first Exabyte smoke boot, run ON niagara-ci-ubuntu.
# Triggers only once /var/lib/niagara-ci/bundles/current/READY exists.
# Never boots the immutable bundle files directly -- always a sparse clone
# into a fresh run dir. Never touches any existing VM.
set -euo pipefail

BUNDLE_ROOT=/var/lib/niagara-ci/bundles/current
READY="$BUNDLE_ROOT/READY"
QEMU_BIN=/var/lib/niagara-ci/runs/20260825T193410Z/qemu/build-ci/qemu-system-sparc64
QEMU_SHA256=e26ea345ccc042836607b39601266465b64b3f8066f0f6c623ea617e053416ef

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
die() { echo "EXABYTE-SMOKE-FAIL: $*" >&2; exit 1; }

[[ -f "$READY" ]] || die "bundle not ready: $READY does not exist yet"
[[ -x "$QEMU_BIN" ]] || die "provider QEMU binary not executable: $QEMU_BIN"
actual_sha=$(sha256sum "$QEMU_BIN" | awk '{print $1}')
[[ "$actual_sha" == "$QEMU_SHA256" ]] || die "QEMU SHA mismatch: expected $QEMU_SHA256 got $actual_sha"

nm_out=$(nm "$QEMU_BIN" 2>/dev/null) || die "nm failed"
grep -qE '\bT[[:space:]]+tlb_flush_range_by_mmuidx\b' <<<"$nm_out" || die "range-flush symbol missing"
grep -q 'niagara_load_vdisk' <<<"$nm_out" || die "multi-unit vdisk symbol missing"
log "gate0 OK: provider QEMU identity + static ABI gates confirmed"

RUN_TS=$(date -u +%Y%m%dT%H%M%SZ)
RUNDIR="/var/lib/niagara-ci/smoke-runs/exabyte-smoke-${RUN_TS}"
TMUX_SESSION="niagara-exabyte-smoke-${RUN_TS}"

mkdir -p "$RUNDIR/images"
cp --reflink=auto --sparse=always -- "$BUNDLE_ROOT/artifacts/root-unit100.img" "$RUNDIR/images/root-unit100.img"
cp --reflink=auto --sparse=always -- "$BUNDLE_ROOT/artifacts/channel-unit101.img" "$RUNDIR/images/channel-unit101.img"
cp --reflink=auto --sparse=always -- "$BUNDLE_ROOT/artifacts/big-disk-unit103.img" "$RUNDIR/images/big-disk-unit103.img"
chmod u+w "$RUNDIR"/images/*.img
log "sparse clones created under $RUNDIR/images (never booting immutable bundle files)"

FW_DIR="$BUNDLE_ROOT/firmware"
[[ -d "$FW_DIR" ]] || die "firmware dir missing in bundle: $FW_DIR"

LAUNCH_CMD="'$QEMU_BIN' -M niagara -L '$FW_DIR' -m 3072 -smp 1 \
    -serial file:/dev/null -serial stdio \
    -monitor unix:'$RUNDIR/monitor.sock',server=on,wait=off -nographic \
    -drive id=root,format=raw,if=none,bus=0,unit=100,readonly=off,cache=none,file='$RUNDIR/images/root-unit100.img' \
    -drive id=chan101,format=raw,if=none,bus=0,unit=101,readonly=off,cache=none,file='$RUNDIR/images/channel-unit101.img' \
    -drive id=cdrom0,format=raw,if=none,bus=0,unit=103,readonly=off,cache=none,file='$RUNDIR/images/big-disk-unit103.img' \
    2>&1 | tee '$RUNDIR/console.log'; echo QEMU_EXIT_RC=\$? >> '$RUNDIR/console.log'"

tmux new-session -d -s "$TMUX_SESSION" -n qemu "$LAUNCH_CMD"
sleep 3
tmux has-session -t "$TMUX_SESSION" 2>/dev/null || die "tmux session did not survive startup"

pane_pid=$(tmux list-panes -t "$TMUX_SESSION:qemu" -F '#{pane_pid}' | head -1)
owner_pid=""
for _ in $(seq 1 20); do
    owner_pid=$(pgrep -P "$pane_pid" -f "$(basename "$QEMU_BIN")" | head -1) || true
    [[ -n "$owner_pid" ]] && break
    for child in $(pgrep -P "$pane_pid" 2>/dev/null); do
        owner_pid=$(pgrep -P "$child" -f "$(basename "$QEMU_BIN")" | head -1) || true
        [[ -n "$owner_pid" ]] && break 2
    done
    sleep 1
done
[[ -n "$owner_pid" ]] || die "could not resolve real QEMU worker PID"
echo "$owner_pid" > "$RUNDIR/owner.pid"
log "launched: tmux=$TMUX_SESSION owner_pid=$owner_pid rundir=$RUNDIR"

# Gate 1: OBP prompt / banner
deadline=$(( $(date +%s) + 300 ))
obp=0
while (( $(date +%s) < deadline )); do
    grep -q '^ok' "$RUNDIR/console.log" 2>/dev/null && { obp=1; break; }
    kill -0 "$owner_pid" 2>/dev/null || die "QEMU exited before OBP"
    sleep 1
done
(( obp )) || die "OBP prompt not reached within 60s"
log "gate1 OK: OBP prompt reached"

tmux send-keys -t "$TMUX_SESSION" "boot /virtual-devices@100/disk@3" Enter
log "sent literal boot command"

deadline=$(( $(date +%s) + 60 ))
banner=0
while (( $(date +%s) < deadline )); do
    grep -q 'OpenIndiana Hipster' "$RUNDIR/console.log" 2>/dev/null && { banner=1; break; }
    kill -0 "$owner_pid" 2>/dev/null || die "QEMU exited during boot"
    sleep 2
done
(( banner )) || die "banner not reached within 300s"
log "gate2 OK: OpenIndiana banner reached"

# Gate 3: hsimd units 0/1/3 attach evidence. Slow is not failed; wait on
# measurable console evidence instead of using a fixed five-second guess.
deadline=$(( $(date +%s) + 300 ))
while (( $(date +%s) < deadline )); do
    grep -q 'hsimd0: hsimd_attach' "$RUNDIR/console.log" 2>/dev/null && \
    grep -q 'hsimd1: hsimd_attach' "$RUNDIR/console.log" 2>/dev/null && \
    grep -q 'hsimd3: hsimd_attach' "$RUNDIR/console.log" 2>/dev/null && break
    kill -0 "$owner_pid" 2>/dev/null || die "QEMU exited before hsimd attach gates"
    sleep 2
done
for u in hsimd0 hsimd1 hsimd3; do
    grep -q "${u}: hsimd_attach" "$RUNDIR/console.log" 2>/dev/null \
        || die "$u attach line not observed within 300s"
done
grep -E 'hsimd[013]: hsimd_attach: size' "$RUNDIR/console.log" || true
log "DONE: exabyte smoke boot evidence captured in $RUNDIR/console.log"
