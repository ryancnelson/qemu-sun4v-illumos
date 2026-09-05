#!/usr/bin/env bash
# Build one cleanly shut-down guest payload, then gate it on AMD64 and ARM64.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PIPELINE_ID=${CI_PIPELINE_NUMBER:?CI_PIPELINE_NUMBER is required}
COMMIT=${CI_COMMIT_SHA:?CI_COMMIT_SHA is required}
ARCH=${GOLDEN_ARCH:?GOLDEN_ARCH must be amd64 or arm64}
[[ $PIPELINE_ID =~ ^[0-9]+$ && $COMMIT =~ ^[0-9a-f]{40}$ ]]
[[ $ARCH == amd64 || $ARCH == arm64 ]]

case "$(uname -m):$ARCH" in
    x86_64:amd64|amd64:amd64|aarch64:arm64) ;;
    *) echo "GOLDEN_HOST_ARCH=FAIL host=$(uname -m) expected=$ARCH" >&2; exit 2 ;;
esac

RUN_ID=golden-${ARCH}-${PIPELINE_ID}
SEED_IMAGE=sparc64-qemu-openindiana-20g:${RUN_ID}-seed
GOLDEN_IMAGE=sparc64-qemu-openindiana-20g:${RUN_ID}
GOLDEN_CONTAINER=$RUN_ID
GOLDEN_VOLUME=golden-${ARCH}-${PIPELINE_ID}-state
SEED_CONTAINER=${RUN_ID}-seed
SEED_VOLUME=${SEED_CONTAINER}-state
BUNDLE=sparc64-qemu-openindiana-20g-beta-20260901.tar.zst
PREFIX=sparc64-qemu-openindiana-20g-beta
GOLDEN_DIR=$ROOT/state/golden
phase=${1:?phase required}

export APPLIANCE_ROOT=$ROOT
export IMAGE=sparc64-qemu-illumos-guest:${RUN_ID}
export OPENSPARC_CACHE=$ROOT/state/opensparc
export TMPDIR=$ROOT/state/tmp
mkdir -p "$TMPDIR"
exec 9>"$ROOT/state/golden-phase.lock"
flock -n 9

if [[ -f $ROOT/state/golden-commit ]]; then
    [[ $(<"$ROOT/state/golden-commit") == "$COMMIT" ]]
else
    printf '%s\n' "$COMMIT" >"$ROOT/state/golden-commit"
fi

use_seed_identity() {
    export SELF_IMAGE=$SEED_IMAGE SELF_CONTAINER=$SEED_CONTAINER SELF_VOLUME=$SEED_VOLUME
}

use_golden_identity() {
    export SELF_IMAGE=$GOLDEN_IMAGE SELF_CONTAINER=$GOLDEN_CONTAINER SELF_VOLUME=$GOLDEN_VOLUME
}

run_runtime_gates() {
    bash ./appliance self-smp
    bash ./appliance self-network
    bash ./appliance self-inventory
    bash ./appliance self-release-ready
}

assert_clean_boot_log() {
    local transcript=$1 status=0
    docker exec "$SELF_CONTAINER" grep -a -E -i \
        'svccfg apply .*generic\.xml failed|dependency cycle|NIAGARA_DEVFSADM_RW_GATE_FAIL|Performing full ZFS device scan|maintenance mode' \
        "$transcript" || status=$?
    case $status in
        0) echo "GOLDEN_BOOT_CLEAN=FAIL arch=$ARCH transcript=$transcript" >&2; exit 1 ;;
        1) echo "GOLDEN_BOOT_CLEAN=PASS arch=$ARCH transcript=$transcript" ;;
        *) echo "GOLDEN_BOOT_CLEAN=FAIL unreadable=$transcript status=$status" >&2; exit 1 ;;
    esac
}

verify_payload_identity() {
    local expected label marker
    expected=$(<"$GOLDEN_DIR/root.sha256")
    label=$(docker image inspect "$SELF_IMAGE" --format \
        '{{index .Config.Labels "org.opencontainers.image.appliance-root-sha256"}}')
    marker=$(docker exec "$SELF_CONTAINER" awk -F= \
        '$1 == "root_sha256" { print $2 }' \
        /var/lib/illumos-appliance/materialized-v1.manifest)
    [[ ${#expected} = 64 && $label == "$expected" && $marker == "$expected" ]]
    echo "GOLDEN_PAYLOAD_IDENTITY=PASS arch=$ARCH root_sha256=$expected"
}

cd "$ROOT"
echo "GOLDEN_CI phase=$phase arch=$ARCH pipeline=$PIPELINE_ID commit=$COMMIT host=$(hostname)"

case $phase in
seed-build)
    [[ $ARCH == amd64 ]]
    use_seed_identity
    REBUILD_RELEASE_FIRMWARE=0 REBUILD_GUEST_RELEASE=2 \
        bash scripts/ci-self-contained-oci.sh build
    touch state/seed-build.pass
    ;;
seed-first)
    [[ $ARCH == amd64 && -f state/seed-build.pass ]]
    use_seed_identity
    ! docker container inspect "$SELF_CONTAINER" >/dev/null 2>&1
    ! docker volume inspect "$SELF_VOLUME" >/dev/null 2>&1
    bash ./appliance self-smoke
    bash ./appliance self-smf-inspect
    bash ./appliance self-groom-release
    run_runtime_gates
    touch state/seed-first.pass
    ;;
freeze)
    [[ $ARCH == amd64 && -f state/seed-first.pass ]]
    use_seed_identity
    bash ./appliance self-shutdown
    rm -rf "$GOLDEN_DIR"
    mkdir -p "$GOLDEN_DIR"
    docker run --rm --entrypoint /bin/bash \
        --mount "type=volume,src=$SELF_VOLUME,dst=/golden,readonly" \
        --mount "type=bind,src=$GOLDEN_DIR,dst=/output" \
        "$SELF_IMAGE" -euo pipefail -c "
            cd /golden/assets
            sha256sum carrier-unit100.img installer-unit103.img \
                root-unit105-20g.raw nvram1 firmware/q.bin \
                >/output/assets.release.SHA256SUMS
            sha256sum root-unit105-20g.raw | awk '{print \$1}' \
                >/output/root.sha256
            tar --sparse -I 'zstd -T0 -10' -cf /output/$BUNDLE \
                --transform='s|^assets|$PREFIX/assets|' -C /golden assets
        "
    sha256sum "$GOLDEN_DIR/$BUNDLE" | \
        awk -v name="$BUNDLE" '{print $1 "  " name}' \
        >"$GOLDEN_DIR/RELEASE-ARCHIVE.SHA256SUMS"
    (cd "$GOLDEN_DIR" && sha256sum -c RELEASE-ARCHIVE.SHA256SUMS)
    [[ $(wc -c <"$GOLDEN_DIR/root.sha256") = 65 ]]
    printf 'GOLDEN_GUEST_ROOT_SHA256=%s\n' "$(<"$GOLDEN_DIR/root.sha256")"
    touch state/freeze.pass
    # The verified archive now owns the payload. Release the seed's writable
    # disk before extracting another complete copy for customer acceptance.
    bash ./appliance self-evidence
    bash ./appliance self-stop
    ;;
golden-build)
    [[ -f "$GOLDEN_DIR/$BUNDLE" && -f "$GOLDEN_DIR/root.sha256" ]]
    cp -p "$GOLDEN_DIR/$BUNDLE" "release/$BUNDLE"
    cp -p "$GOLDEN_DIR/assets.release.SHA256SUMS" assets.release.SHA256SUMS
    cp -p "$GOLDEN_DIR/RELEASE-ARCHIVE.SHA256SUMS" RELEASE-ARCHIVE.SHA256SUMS
    use_golden_identity
    REBUILD_RELEASE_FIRMWARE=0 REBUILD_GUEST_RELEASE=2 \
        bash scripts/ci-self-contained-oci.sh build
    test "$(docker image inspect "$SELF_IMAGE" --format \
        '{{index .Config.Labels "org.opencontainers.image.appliance-root-sha256"}}')" \
        = "$(<"$GOLDEN_DIR/root.sha256")"
    touch state/golden-build.pass
    ;;
test-first)
    [[ -f state/golden-build.pass ]]
    use_golden_identity
    ! docker container inspect "$SELF_CONTAINER" >/dev/null 2>&1
    ! docker volume inspect "$SELF_VOLUME" >/dev/null 2>&1
    bash ./appliance self-smoke
    verify_payload_identity
    run_runtime_gates
    assert_clean_boot_log /state/self-smoke-console.log
    bash ./appliance self-shutdown
    touch state/test-first.pass
    ;;
test-second)
    [[ -f state/test-first.pass ]]
    use_golden_identity
    bash ./appliance self-restart
    verify_payload_identity
    run_runtime_gates
    assert_clean_boot_log /state/self-login-console.log
    bash ./appliance self-shutdown
    echo "GOLDEN_TWO_BOOT_ACCEPTANCE=PASS arch=$ARCH volume=$SELF_VOLUME"
    touch state/test-second.pass
    ;;
cleanup)
    use_seed_identity
    bash ./appliance self-evidence || true
    bash ./appliance self-stop
    use_golden_identity
    bash ./appliance self-evidence || true
    bash ./appliance self-stop
    echo "GOLDEN_CLEANUP=PASS arch=$ARCH pipeline=$PIPELINE_ID"
    ;;
*)
    echo "unknown phase: $phase" >&2
    exit 2
    ;;
esac

echo "GOLDEN_PHASE=PASS phase=$phase arch=$ARCH pipeline=$PIPELINE_ID"
