#!/usr/bin/bash

set -euo pipefail
umask 077

SOURCE_DATASET=tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe
SOURCE_SNAPSHOT=pre-boot-unit104-login-trial-0001
SOURCE_SNAPSHOT_GUID=370532935438843004
UNIT104_RELATIVE_PATH=baselines/unit104-login-proven-20260826T210446Z.raw
UNIT104_BYTES=64424509440
INNER_POOL_GUID=18135893029031842473
TARGET_PARENT=tink/qemu-sun4v-illumos-ci
RUN_ROOT=/tink/runs/woodpecker-niagara-login
LOCK_DIR=/tmp/niagara-unit104-assembly.lock
QEMU=/tink/builds/qemu-sun4v-879fee-tribblix/build/qemu-system-sparc64

MODE=${1:-}
TRIAL_ID=${2:-}

die()
{
    echo "NIAGARA_UNIT104_ASSEMBLY=FAIL reason=$*" >&2
    exit 1
}

case "$MODE" in
--dry-run|--create)
    ;;
*)
    die "usage: $0 --dry-run|--create TRIAL_ID"
    ;;
esac

[[ "$TRIAL_ID" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || \
    die "trial ID must match [a-z0-9][a-z0-9._-]*: $TRIAL_ID"

SOURCE=${SOURCE_DATASET}@${SOURCE_SNAPSHOT}
TARGET_DATASET=${TARGET_PARENT}/${TRIAL_ID}
RUN_DIR=${RUN_ROOT}/${TRIAL_ID}

for tool in /usr/sbin/zfs /usr/sbin/zpool /usr/sbin/lofiadm
do
    [[ -x "$tool" ]] || die "required executable is missing: $tool"
done

if pgrep -f "$QEMU" >/dev/null 2>&1; then
    pgrep -lf "$QEMU" >&2 || true
    die "the selected sun4v QEMU is already running"
fi

ACTUAL_SOURCE_GUID=$(/usr/sbin/zfs get -H -o value guid "$SOURCE" 2>/dev/null) || \
    die "source snapshot is missing: $SOURCE"
[[ "$ACTUAL_SOURCE_GUID" = "$SOURCE_SNAPSHOT_GUID" ]] || \
    die "source snapshot GUID changed: $ACTUAL_SOURCE_GUID"
/usr/sbin/zfs holds -H "$SOURCE" | awk '$2 == "trial-input" { found = 1 } END { exit !found }' || \
    die "source snapshot lacks the trial-input hold"

if /usr/sbin/zfs list -H -o name "$TARGET_DATASET" >/dev/null 2>&1; then
    die "target dataset already exists: $TARGET_DATASET"
fi
[[ ! -e "$RUN_DIR" ]] || die "run directory already exists: $RUN_DIR"

if /usr/sbin/zpool list -H -o guid 2>/dev/null | grep -Fx "$INNER_POOL_GUID" >/dev/null
then
    die "unit104 inner pool is imported on the Tribblix host"
fi

SOURCE_MOUNTPOINT=$(/usr/sbin/zfs get -H -o value mountpoint "$SOURCE_DATASET")
SOURCE_FILE=${SOURCE_MOUNTPOINT}/.zfs/snapshot/${SOURCE_SNAPSHOT}/${UNIT104_RELATIVE_PATH}
[[ -r "$SOURCE_FILE" ]] || die "source raw file is unreadable: $SOURCE_FILE"
ACTUAL_BYTES=$(wc -c < "$SOURCE_FILE" | tr -d ' ')
[[ "$ACTUAL_BYTES" = "$UNIT104_BYTES" ]] || \
    die "source raw file size changed: $ACTUAL_BYTES"

if /usr/sbin/lofiadm 2>/dev/null | grep -F "$SOURCE_FILE" >/dev/null
then
    die "source raw file has a Tribblix lofi attachment"
fi

echo "NIAGARA_UNIT104_ASSEMBLY_MODE=${MODE#--}"
echo "source_snapshot=$SOURCE"
echo "source_snapshot_guid=$ACTUAL_SOURCE_GUID"
echo "target_dataset=$TARGET_DATASET"
echo "expected_target_file=${TARGET_PARENT/#tink/\/tink}/${TRIAL_ID}/${UNIT104_RELATIVE_PATH}"
echo "unit104_bytes=$ACTUAL_BYTES"
echo "inner_pool_guid=$INNER_POOL_GUID"

if [[ "$MODE" = --dry-run ]]; then
    echo "planned_command=zfs clone $SOURCE $TARGET_DATASET"
    echo "NIAGARA_UNIT104_ASSEMBLY=DRY_RUN_PASS"
    exit 0
fi

mkdir "$LOCK_DIR" 2>/dev/null || \
    die "assembly lock is held or stale: $LOCK_DIR"
release_lock()
{
    rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap release_lock EXIT HUP INT TERM

# Recheck mutable ownership and target state after acquiring the writer lock.
if pgrep -f "$QEMU" >/dev/null 2>&1; then
    die "the selected sun4v QEMU started while acquiring the assembly lock"
fi
if /usr/sbin/zpool list -H -o guid 2>/dev/null | grep -Fx "$INNER_POOL_GUID" >/dev/null
then
    die "unit104 inner pool was imported while acquiring the assembly lock"
fi
if /usr/sbin/zfs list -H -o name "$TARGET_DATASET" >/dev/null 2>&1; then
    die "target dataset appeared while acquiring the assembly lock: $TARGET_DATASET"
fi

/usr/sbin/zfs clone "$SOURCE" "$TARGET_DATASET"

TARGET_MOUNTPOINT=$(/usr/sbin/zfs get -H -o value mountpoint "$TARGET_DATASET")
TARGET_FILE=${TARGET_MOUNTPOINT}/${UNIT104_RELATIVE_PATH}
TARGET_ORIGIN=$(/usr/sbin/zfs get -H -o value origin "$TARGET_DATASET")
TARGET_GUID=$(/usr/sbin/zfs get -H -o value guid "$TARGET_DATASET")
[[ "$TARGET_ORIGIN" = "$SOURCE" ]] || die "created clone has wrong origin: $TARGET_ORIGIN"
[[ -f "$TARGET_FILE" && -w "$TARGET_FILE" ]] || \
    die "created unit104 file is not writable: $TARGET_FILE"
TARGET_BYTES=$(wc -c < "$TARGET_FILE" | tr -d ' ')
[[ "$TARGET_BYTES" = "$UNIT104_BYTES" ]] || \
    die "created unit104 file has wrong size: $TARGET_BYTES"

mkdir -p "$RUN_DIR"
cat > "$RUN_DIR/assembly-manifest.txt" <<EOF
trial_id=$TRIAL_ID
created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
source_snapshot=$SOURCE
source_snapshot_guid=$ACTUAL_SOURCE_GUID
target_dataset=$TARGET_DATASET
target_dataset_guid=$TARGET_GUID
target_dataset_origin=$TARGET_ORIGIN
unit104_path=$TARGET_FILE
unit104_bytes=$TARGET_BYTES
unit104_inner_pool_guid=$INNER_POOL_GUID
EOF

echo "target_dataset_guid=$TARGET_GUID"
echo "unit104_path=$TARGET_FILE"
echo "assembly_manifest=$RUN_DIR/assembly-manifest.txt"
echo "NIAGARA_UNIT104_ASSEMBLY=PASS"
