#!/usr/bin/env bash
set -euo pipefail

ROOT=${APPLIANCE_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
ROOT_IMAGE=$ROOT/assets/root-unit105-20g.raw
BACKUP_DIR=${RELEASE_BACKUP_DIR:-/root/devel/.cache/niagara-release-bases}
BACKUP=$BACKUP_DIR/root-unit105-20g.before-guest-ux.raw
BUNDLE_NAME=${SELF_BUNDLE:-sparc64-qemu-openindiana-20g-beta-20260901.tar.zst}
BUNDLE=$ROOT/release/$BUNDLE_NAME
PREFIX=sparc64-qemu-openindiana-20g-beta
CONTAINER=${ASSEMBLY_CONTAINER:-sparc64-qemu-guest-ux-assembly}

cleanup() {
    CONTAINER=$CONTAINER bash "$ROOT/appliance" stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

test -f "$ROOT_IMAGE"
mkdir -p "$BACKUP_DIR" "$ROOT/release" "$ROOT/state/guest-ux-install"
if [[ ! -f $BACKUP ]]; then
    cp --sparse=always "$ROOT_IMAGE" "$BACKUP.tmp"
    mv "$BACKUP.tmp" "$BACKUP"
    chmod 0444 "$BACKUP"
    echo "GUEST_UX_BASE_BACKUP=PASS path=$BACKUP"
fi

CONTAINER=$CONTAINER bash "$ROOT/appliance" stop
CONTAINER=$CONTAINER ROOT_IMAGE=root-unit105-20g.raw ROOT_BYTES=21474836480 \
    ROOT_UNIT=105 ATTACH_MIGRATION_TARGET=0 bash "$ROOT/appliance" up
CONSOLE_SOCKET=$ROOT/state/console.sock AUTO_BOOT_REQUIRED=1 \
    EVIDENCE_PATH=$ROOT/state/guest-ux-install/boot.log \
    python3 "$ROOT/scripts/smoke-login.py"
python3 "$ROOT/scripts/install-guest-ux.py" \
    --socket "$ROOT/state/console.sock" \
    --guest-command "$ROOT/scripts/guest-command.py" \
    --source-dir "$ROOT/guest-assets" \
    --transcript-dir "$ROOT/state/guest-ux-install"
python3 "$ROOT/scripts/guest-command.py" \
    --socket "$ROOT/state/console.sock" \
    --transcript "$ROOT/state/guest-ux-install/shutdown.log" \
    --command "nohup /sbin/sh -c 'sleep 3; /usr/sbin/sync; /usr/sbin/init 5' </dev/null >/tmp/release-shutdown.log 2>&1 &"

for _ in $(seq 1 180); do
    [[ $(docker inspect -f '{{.State.Running}}' "$CONTAINER") = false ]] && break
    sleep 1
done
[[ $(docker inspect -f '{{.State.Running}}' "$CONTAINER") = false ]] || {
    echo "GUEST_UX_SHUTDOWN=FAIL" >&2
    exit 1
}
docker rm "$CONTAINER" >/dev/null
echo GUEST_UX_SHUTDOWN=PASS

manifest_tmp=$ROOT/assets.release.SHA256SUMS.tmp
(
    cd "$ROOT/assets"
    sha256sum carrier-unit100.img installer-unit103.img \
        root-unit105-20g.raw nvram1 firmware/q.bin
) >"$manifest_tmp"
mv "$manifest_tmp" "$ROOT/assets.release.SHA256SUMS"
root_sha=$(awk '$2 == "root-unit105-20g.raw" { print $1 }' \
    "$ROOT/assets.release.SHA256SUMS")

bundle_tmp=$BUNDLE.tmp
rm -f "$bundle_tmp"
(
    cd "$ROOT"
    tar --sparse --transform "s,^assets/,$PREFIX/assets/," \
        -I 'zstd -T0 -10' -cf "$bundle_tmp" \
        assets/carrier-unit100.img assets/installer-unit103.img \
        assets/root-unit105-20g.raw assets/nvram1 assets/firmware/q.bin
)
mv "$bundle_tmp" "$BUNDLE"
bundle_sha=$(sha256sum "$BUNDLE" | cut -d ' ' -f 1)
printf '%s  %s\n' "$bundle_sha" "$BUNDLE_NAME" \
    >"$ROOT/RELEASE-ARCHIVE.SHA256SUMS"
echo "GUEST_RELEASE_ASSEMBLY=PASS root_sha256=$root_sha bundle_sha256=$bundle_sha"
