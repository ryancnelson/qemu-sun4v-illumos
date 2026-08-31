#!/usr/bin/bash

set -euo pipefail

QEMU_SOURCE=${QEMU_SOURCE:-/tink/builds/qemu-sun4v-879fee-tribblix}
QEMU=${QEMU:-${QEMU_SOURCE}/build/qemu-system-sparc64}
QEMU_IMG=${QEMU_IMG:-/usr/bin/qemu-img}
UNIT100_RAM_ROOT=${UNIT100_RAM_ROOT:-/tmp}
UNIT100_SOURCE=${UNIT100_SOURCE:-/tink/runs/ec2-tribblix-smoke-20260827-01/proven-lineage-exact/carrier-unit100.img}
UNIT100_BYTES=1073741824
UNIT100_SHA256=70d436dab85c3fc9444c2df0cf47075c11e27fab4cc2fbe72929b2ead37fd735
UNIT103_SOURCE=${UNIT103_SOURCE:-/tink/disk-images/workstation-multiuser-raw-20260827T010500Z/artifacts/installer-unit103.img}
UNIT104_SOURCE_DATASET=tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe
UNIT104_SOURCE_SNAPSHOT=pre-boot-unit104-login-trial-0001
UNIT104_SOURCE_SNAPSHOT_GUID=370532935438843004
UNIT104_RELATIVE_PATH=baselines/unit104-login-proven-20260826T210446Z.raw
UNIT104_BYTES=64424509440
UNIT104_INNER_POOL_GUID=18135893029031842473
NVRAM_SOURCE=${NVRAM_SOURCE:-/tink/vm-state/oi-basecamp/nvram1}
LAUNCHER=${1:-}
BOOT_HELPER=${2:-}

die()
{
    echo "NIAGARA_LOGIN_PREFLIGHT=FAIL reason=$*" >&2
    exit 1
}

for tool in "$QEMU" "$QEMU_IMG" /usr/bin/digest /usr/bin/python3 /usr/sbin/zfs \
    /usr/sbin/zpool /usr/sbin/lofiadm
do
    [[ -x "$tool" ]] || die "required executable is missing: $tool"
done

for artifact in "$UNIT100_SOURCE" "$UNIT103_SOURCE" "$NVRAM_SOURCE"
do
    [[ -r "$artifact" ]] || die "required artifact is unreadable: $artifact"
done

[[ -n "$LAUNCHER" && -r "$LAUNCHER" ]] || \
    die "usage: $0 PATH_TO_STAGED_LAUNCHER PATH_TO_BOOT_HELPER"
/usr/bin/bash -n "$LAUNCHER" || die "staged launcher failed bash -n: $LAUNCHER"
[[ -n "$BOOT_HELPER" && -r "$BOOT_HELPER" ]] || \
    die "OpenBoot helper is unreadable: $BOOT_HELPER"
/usr/bin/python3 -m py_compile "$BOOT_HELPER" || \
    die "OpenBoot helper failed Python compilation: $BOOT_HELPER"

if pgrep -f "$QEMU" >/dev/null 2>&1; then
    pgrep -lf "$QEMU" >&2 || true
    die "the selected sun4v QEMU is already running"
fi

UNIT100_FS=$(df -n "$UNIT100_RAM_ROOT" 2>/dev/null | awk '{ print $NF }')
[[ "$UNIT100_FS" = tmpfs ]] || \
    die "unit100 RAM root is not tmpfs: $UNIT100_RAM_ROOT ($UNIT100_FS)"
UNIT100_AVAILABLE_KIB=$(df -k "$UNIT100_RAM_ROOT" | awk 'NR == 2 { print $4 }')
UNIT100_REQUIRED_KIB=$(((UNIT100_BYTES + 1023) / 1024))
[[ "$UNIT100_AVAILABLE_KIB" -ge "$UNIT100_REQUIRED_KIB" ]] || \
    die "unit100 needs ${UNIT100_REQUIRED_KIB} KiB; tmpfs has ${UNIT100_AVAILABLE_KIB} KiB"

UNIT100_ACTUAL_BYTES=$(wc -c < "$UNIT100_SOURCE" | tr -d ' ')
[[ "$UNIT100_ACTUAL_BYTES" = "$UNIT100_BYTES" ]] || \
    die "unit100 source size changed: $UNIT100_ACTUAL_BYTES"
UNIT100_ACTUAL_SHA256=$(/usr/bin/digest -a sha256 "$UNIT100_SOURCE")
[[ "$UNIT100_ACTUAL_SHA256" = "$UNIT100_SHA256" ]] || \
    die "unit100 source SHA-256 changed: $UNIT100_ACTUAL_SHA256"

UNIT104_SNAPSHOT=${UNIT104_SOURCE_DATASET}@${UNIT104_SOURCE_SNAPSHOT}
UNIT104_ACTUAL_SNAPSHOT_GUID=$(/usr/sbin/zfs get -H -o value guid "$UNIT104_SNAPSHOT" 2>/dev/null) || \
    die "unit104 source snapshot is missing: $UNIT104_SNAPSHOT"
[[ "$UNIT104_ACTUAL_SNAPSHOT_GUID" = "$UNIT104_SOURCE_SNAPSHOT_GUID" ]] || \
    die "unit104 source snapshot GUID changed: $UNIT104_ACTUAL_SNAPSHOT_GUID"
/usr/sbin/zfs holds -H "$UNIT104_SNAPSHOT" | awk '$2 == "trial-input" { found = 1 } END { exit !found }' || \
    die "unit104 source snapshot lacks the trial-input hold"

UNIT104_MOUNTPOINT=$(/usr/sbin/zfs get -H -o value mountpoint "$UNIT104_SOURCE_DATASET")
UNIT104_SNAPSHOT_FILE=${UNIT104_MOUNTPOINT}/.zfs/snapshot/${UNIT104_SOURCE_SNAPSHOT}/${UNIT104_RELATIVE_PATH}
[[ -r "$UNIT104_SNAPSHOT_FILE" ]] || \
    die "unit104 snapshot file is unreadable: $UNIT104_SNAPSHOT_FILE"
UNIT104_ACTUAL_BYTES=$(wc -c < "$UNIT104_SNAPSHOT_FILE" | tr -d ' ')
[[ "$UNIT104_ACTUAL_BYTES" = "$UNIT104_BYTES" ]] || \
    die "unit104 snapshot file size changed: $UNIT104_ACTUAL_BYTES"

if /usr/sbin/zpool list -H -o guid 2>/dev/null | \
    grep -Fx "$UNIT104_INNER_POOL_GUID" >/dev/null
then
    die "unit104 inner pool is imported on the Tribblix host"
fi

if /usr/sbin/lofiadm 2>/dev/null | grep -F "$UNIT104_SNAPSHOT_FILE" >/dev/null
then
    die "unit104 snapshot file has a Tribblix lofi attachment"
fi

echo "NIAGARA_LOGIN_PREFLIGHT=PASS"
echo "qemu=$QEMU"
echo "qemu_commit=$(git -C "$QEMU_SOURCE" rev-parse HEAD 2>/dev/null || echo unknown)"
echo "unit100_fs=$UNIT100_FS"
echo "unit100_available_kib=$UNIT100_AVAILABLE_KIB"
echo "unit100_sha256=$UNIT100_ACTUAL_SHA256"
echo "unit103_path=$UNIT103_SOURCE"
echo "unit104_source_snapshot=$UNIT104_SNAPSHOT"
echo "unit104_source_snapshot_guid=$UNIT104_ACTUAL_SNAPSHOT_GUID"
echo "unit104_snapshot_file=$UNIT104_SNAPSHOT_FILE"
echo "unit104_bytes=$UNIT104_ACTUAL_BYTES"
echo "unit104_inner_pool_guid=$UNIT104_INNER_POOL_GUID"
echo "launcher=$LAUNCHER"
echo "launcher_sha256=$(/usr/bin/digest -a sha256 "$LAUNCHER")"
echo "boot_helper=$BOOT_HELPER"
echo "boot_helper_sha256=$(/usr/bin/digest -a sha256 "$BOOT_HELPER")"
