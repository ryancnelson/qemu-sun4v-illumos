#!/usr/bin/env bash
# Run only in the fresh directory staged by .woodpecker/niagara-smp.yml.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PIPELINE_ID=${CI_PIPELINE_NUMBER:?CI_PIPELINE_NUMBER is required}
COMMIT=${CI_COMMIT_SHA:?CI_COMMIT_SHA is required}
[[ $PIPELINE_ID =~ ^[0-9]+$ && $COMMIT =~ ^[0-9a-f]{40}$ ]] || {
    echo 'CI_IDENTITY=FAIL invalid pipeline number or commit' >&2
    exit 2
}
RUN_ID=niagara-lab-$PIPELINE_ID
[[ ${ROOT##*/} == "$RUN_ID" ]] || {
    echo "CI_ISOLATION=FAIL expected a fresh directory named $RUN_ID, got $ROOT" >&2
    exit 2
}
export APPLIANCE_ROOT=$ROOT
export IMAGE=sparc64-qemu-illumos-guest:niagara-smp-$RUN_ID
export SELF_IMAGE=sparc64-qemu-openindiana-20g:niagara-smp-$RUN_ID
export SELF_CONTAINER=niagara-smp-$RUN_ID
export SELF_VOLUME=$SELF_CONTAINER-state
export OPENSPARC_CACHE=$ROOT/state/opensparc
BUNDLE=sparc64-qemu-openindiana-20g-beta-20260901.tar.zst
PREFIX=sparc64-qemu-openindiana-20g-beta
SOURCE_IMAGE=ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g@sha256:29cadb0eb0f103fecb5f22ab0707d71e66986724a49d10f3b213b4f9ae7819fe
phase=${1:-identity}
echo "CI_LANE=niagara-smp pipeline=$PIPELINE_ID commit=$COMMIT phase=$phase host=$(hostname)"
echo "CI_RESOURCES root=$ROOT base=$IMAGE image=$SELF_IMAGE container=$SELF_CONTAINER volume=$SELF_VOLUME"
[[ $phase != identity ]] || exit 0

# A restarted/duplicate phase may not run concurrently or change source identity.
mkdir -p "$ROOT/state"
exec 9>"$ROOT/state/phase.lock"
flock -n 9 || { echo 'CI_ISOLATION=FAIL another phase owns this run' >&2; exit 1; }
if [[ -e $ROOT/state/commit ]]; then
    [[ $(<"$ROOT/state/commit") == "$COMMIT" ]] || {
        echo 'CI_ISOLATION=FAIL run directory belongs to another commit' >&2
        exit 1
    }
else
    printf '%s\n' "$COMMIT" >"$ROOT/state/commit"
fi
cd "$ROOT"

case $phase in
prepare)
    minimum_gib=${CI_MIN_FREE_GIB:-20}
    [[ $minimum_gib =~ ^[0-9]+$ ]] || exit 2
    available_kib=$(df -Pk "$ROOT" | awk 'NR == 2 {print $4}')
    echo "CI_DISK_SPACE available_kib=$available_kib required_gib=$minimum_gib"
    if (( available_kib < minimum_gib * 1024 * 1024 )); then
        echo 'CI_PREFLIGHT=FAIL reason=insufficient-disk-space; no guest or build started' >&2
        exit 1
    fi
    [[ ! -e state/prepared ]] || { echo 'CI_PREPARE=FAIL already prepared' >&2; exit 1; }
    mkdir -p sources release assets "$OPENSPARC_CACHE"
    # Only read original source archives; no mutable outputs or guest disks are shared.
    cp --reflink=auto --sparse=always \
        /root/devel/sparc64-qemu-illumos-docker-guest/sources/qemu-049affb20df67162cf58deeaf74d5ad4b83cbdc3.tar.gz sources/
    (cd sources && sha256sum -c SHA256SUMS)
    cp --reflink=auto --sparse=always \
        /root/devel/.cache/opensparc/OpenSPARCT1_Arch.1.5.tar.bz2 "$OPENSPARC_CACHE/"
    source_container=niagara-smp-$RUN_ID-source
    trap 'docker rm -f "$source_container" >/dev/null 2>&1 || true' EXIT
    docker create --name "$source_container" "$SOURCE_IMAGE" >/dev/null
    docker cp "$source_container:/opt/illumos-appliance/beta.tar.zst" "release/$BUNDLE"
    (cd release && sha256sum -c ../RELEASE-ARCHIVE.SHA256SUMS)
    mkdir -p state/seed
    tar -I zstd -xf "release/$BUNDLE" -C state/seed "$PREFIX/assets/firmware"
    cp -a "state/seed/$PREFIX/assets/firmware" assets/
    printf '%s\n' "$SOURCE_IMAGE" >state/prepared
    echo CI_INPUTS=PASS
    ;;
build)
    test -s state/prepared
    REBUILD_GUEST_RELEASE=2 bash scripts/ci-self-contained-oci.sh build
    ;;
interactive)
    timeout --signal=TERM --kill-after=30s 300 bash scripts/ci-self-contained-oci.sh interactive
    ;;
boot)
    # Never stop another run or erase an existing test to get a clean start.
    if docker container inspect "$SELF_CONTAINER" >/dev/null 2>&1 ||
       docker volume inspect "$SELF_VOLUME" >/dev/null 2>&1; then
        echo 'CI_BOOT=FAIL run resources already exist; use a fresh pipeline' >&2
        exit 1
    fi
    timeout --signal=TERM --kill-after=30s 600 bash ./appliance self-smoke | tee state/boot.log
    ;;
cpus)
    timeout --signal=TERM --kill-after=30s 360 bash ./appliance self-smp | tee state/cpus.log
    ;;
network)
    timeout --signal=TERM --kill-after=30s 900 bash ./appliance self-network | tee state/network.log
    ;;
inventory)
    timeout --signal=TERM --kill-after=30s 300 bash ./appliance self-inventory | tee state/inventory.log
    bash ./appliance self-inspect | tee state/inspect.log
    ;;
cleanup)
    # Evidence is under this run's ROOT. Cleanup names only this run's resources.
    if docker container inspect "$SELF_CONTAINER" >/dev/null 2>&1; then
        bash ./appliance self-evidence
        docker inspect "$SELF_CONTAINER" >state/container.inspect.json
    fi
    bash ./appliance self-stop
    docker rm -f "$SELF_CONTAINER-interactive" "$SELF_CONTAINER-source" >/dev/null 2>&1 || true
    echo "CI_CLEANUP=PASS evidence=$ROOT/state"
    ;;
*)
    echo "unknown phase: $phase" >&2
    exit 2
    ;;
esac
echo "CI_PHASE=PASS phase=$phase pipeline=$PIPELINE_ID commit=$COMMIT"

