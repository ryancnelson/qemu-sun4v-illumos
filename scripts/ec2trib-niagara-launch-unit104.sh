#!/usr/bin/bash

set -euo pipefail
umask 077

TARGET_PARENT=tink/qemu-sun4v-illumos-ci
UNIT104_RELATIVE_PATH=baselines/unit104-login-proven-20260826T210446Z.raw
UNIT104_BYTES=64424509440
INNER_POOL_GUID=18135893029031842473
ORCHESTRATION_ROOT=/tink/runs/woodpecker-niagara-login
QEMU=/tink/builds/qemu-sun4v-879fee-tribblix/build/qemu-system-sparc64

MODE=${1:-}
TRIAL_ID=${2:-}
LAUNCHER=${3:-}
BOOT_HELPER=${4:-}
OPENBOOT_COMMAND='boot /virtual-devices@100/disk@4:a -k -v'
LOGIN_MARKER='oi-basecamp console login:'
LOGIN_TIMEOUT=900

die()
{
    echo "NIAGARA_UNIT104_LAUNCH=FAIL reason=$*" >&2
    exit 1
}

case "$MODE" in
--dry-run|--launch)
    ;;
*)
    die "usage: $0 --dry-run|--launch TRIAL_ID PATH_TO_STAGED_LAUNCHER PATH_TO_BOOT_HELPER"
    ;;
esac

[[ "$TRIAL_ID" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || \
    die "trial ID must match [a-z0-9][a-z0-9._-]*: $TRIAL_ID"
[[ -n "$LAUNCHER" && -r "$LAUNCHER" ]] || die "launcher is unreadable: $LAUNCHER"
/usr/bin/bash -n "$LAUNCHER" || die "launcher failed bash -n: $LAUNCHER"
[[ -n "$BOOT_HELPER" && -r "$BOOT_HELPER" ]] || \
    die "OpenBoot helper is unreadable: $BOOT_HELPER"
/usr/bin/python3 -m py_compile "$BOOT_HELPER" || \
    die "OpenBoot helper failed Python compilation: $BOOT_HELPER"

TARGET_DATASET=${TARGET_PARENT}/${TRIAL_ID}
TARGET_MOUNTPOINT=$(/usr/sbin/zfs get -H -o value mountpoint "$TARGET_DATASET" 2>/dev/null) || \
    die "assembled target dataset is missing: $TARGET_DATASET"
TARGET_FILE=${TARGET_MOUNTPOINT}/${UNIT104_RELATIVE_PATH}
[[ -f "$TARGET_FILE" && -w "$TARGET_FILE" ]] || \
    die "assembled unit104 is not writable: $TARGET_FILE"
TARGET_BYTES=$(wc -c < "$TARGET_FILE" | tr -d ' ')
[[ "$TARGET_BYTES" = "$UNIT104_BYTES" ]] || \
    die "assembled unit104 has wrong size: $TARGET_BYTES"

if pgrep -f "$QEMU" >/dev/null 2>&1; then
    pgrep -lf "$QEMU" >&2 || true
    die "the selected sun4v QEMU is already running"
fi
if /usr/sbin/zpool list -H -o guid 2>/dev/null | grep -Fx "$INNER_POOL_GUID" >/dev/null
then
    die "unit104 inner pool is imported on the Tribblix host"
fi
if /usr/sbin/lofiadm 2>/dev/null | grep -F "$TARGET_FILE" >/dev/null
then
    die "assembled unit104 has a Tribblix lofi attachment"
fi

RUN_ID=niagara-${TRIAL_ID}
RUN_DIR=/tink/runs/${RUN_ID}
ORCHESTRATION_DIR=${ORCHESTRATION_ROOT}/${TRIAL_ID}
ASSEMBLY_MANIFEST=${ORCHESTRATION_DIR}/assembly-manifest.txt
if [[ "$MODE" = --launch ]]; then
    [[ -r "$ASSEMBLY_MANIFEST" ]] || \
        die "assembly manifest is missing: $ASSEMBLY_MANIFEST"
fi
[[ ! -e "$RUN_DIR" ]] || die "QEMU run directory already exists: $RUN_DIR"

echo "NIAGARA_UNIT104_LAUNCH_MODE=${MODE#--}"
echo "trial_id=$TRIAL_ID"
echo "target_dataset=$TARGET_DATASET"
echo "unit104_path=$TARGET_FILE"
echo "run_id=$RUN_ID"
echo "run_dir=$RUN_DIR"
echo "launcher=$LAUNCHER"
echo "boot_helper=$BOOT_HELPER"
echo "openboot_command=$OPENBOOT_COMMAND"
echo "login_marker=$LOGIN_MARKER"
echo "login_timeout_seconds=$LOGIN_TIMEOUT"
echo "assembly_manifest=$ASSEMBLY_MANIFEST"

if [[ "$MODE" = --dry-run ]]; then
    echo "planned_command=RUN_ID=$RUN_ID UNIT100_RAM_ROOT=/tmp CONSOLE_WAIT=on $LAUNCHER $TARGET_FILE"
    echo "NIAGARA_UNIT104_LAUNCH=DRY_RUN_PASS"
    exit 0
fi

LAUNCH_LOG=${ORCHESTRATION_DIR}/launcher.log
LAUNCHER_PID_FILE=${ORCHESTRATION_DIR}/launcher.pid
RUN_ID="$RUN_ID" UNIT100_RAM_ROOT=/tmp CONSOLE_WAIT=on \
    nohup /usr/bin/bash "$LAUNCHER" "$TARGET_FILE" \
    > "$LAUNCH_LOG" 2>&1 < /dev/null &
LAUNCHER_PID=$!
echo "$LAUNCHER_PID" > "$LAUNCHER_PID_FILE"

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20
do
    if [[ -S "$RUN_DIR/console.sock" && -r "$RUN_DIR/qemu.pid" ]]; then
        QEMU_PID=$(cat "$RUN_DIR/qemu.pid")
        if kill -0 "$QEMU_PID" 2>/dev/null; then
            BOOT_LOG=${ORCHESTRATION_DIR}/openboot-injector.log
            if ! /usr/bin/python3 "$BOOT_HELPER" \
                --socket "$RUN_DIR/console.sock" \
                --command "$OPENBOOT_COMMAND" \
                --success-marker "$LOGIN_MARKER" \
                --timeout "$LOGIN_TIMEOUT" > "$BOOT_LOG" 2>&1
            then
                {
                    echo "login_gate=fail"
                    echo "login_gate_observed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
                } >> "$RUN_DIR/manifest.txt"
                cat "$BOOT_LOG" >&2
                die "OpenBoot/login gate failed; inspect $BOOT_LOG"
            fi
            cat "$BOOT_LOG"
            grep -F "NIAGARA_OPENBOOT_COMMAND=PASS" "$BOOT_LOG" >/dev/null || \
                die "OpenBoot helper omitted its PASS marker: $BOOT_LOG"
            grep -F "NIAGARA_LOGIN_GATE=PASS" "$BOOT_LOG" >/dev/null || \
                die "OpenBoot helper omitted its login PASS marker: $BOOT_LOG"
            {
                echo "login_gate=pass"
                echo "login_marker=$LOGIN_MARKER"
                echo "login_gate_observed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            } >> "$RUN_DIR/manifest.txt"
            echo "launcher_pid=$LAUNCHER_PID"
            echo "qemu_pid=$QEMU_PID"
            echo "console_socket=$RUN_DIR/console.sock"
            echo "qmp_socket=$RUN_DIR/qmp.sock"
            echo "launch_log=$LAUNCH_LOG"
            echo "openboot_log=$BOOT_LOG"
            echo "NIAGARA_OPENBOOT_COMMAND=PASS"
            echo "NIAGARA_LOGIN_GATE=PASS"
            echo "NIAGARA_UNIT104_LAUNCH=PASS"
            exit 0
        fi
    fi
    kill -0 "$LAUNCHER_PID" 2>/dev/null || \
        die "launcher exited before a live QEMU console appeared; inspect $LAUNCH_LOG"
    sleep 1
done

die "live QEMU console did not appear within 20 seconds; inspect $LAUNCH_LOG"
