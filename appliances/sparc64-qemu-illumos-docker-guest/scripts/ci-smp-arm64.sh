#!/usr/bin/env bash
# Native ARM preview lane; every mutable resource belongs to one CI run.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PIPELINE_ID=${CI_PIPELINE_NUMBER:?}
COMMIT=${CI_COMMIT_SHA:?}
[[ $PIPELINE_ID =~ ^[0-9]+$ && $COMMIT =~ ^[0-9a-f]{40}$ ]]
RUN_ID=niagara-smp-arm64-$PIPELINE_ID
[[ $ROOT == /mnt/disk-images/woodpecker/$RUN_ID ]]
[[ $(uname -m) == aarch64 ]]
export APPLIANCE_ROOT=$ROOT
export IMAGE=sparc64-qemu-illumos-guest:$RUN_ID
export SELF_IMAGE=sparc64-qemu-openindiana-20g:$RUN_ID
export SELF_CONTAINER=$RUN_ID
export SELF_VOLUME=$RUN_ID-state
export TMPDIR=$ROOT/state/tmp
mkdir -p "$TMPDIR"
exec 9>"$ROOT/state/phase.lock"
flock -n 9
cd "$ROOT"
if [[ -f state/commit ]]; then
    [[ $(<state/commit) == "$COMMIT" ]]
else
    printf '%s\n' "$COMMIT" >state/commit
fi
REPOSITORY=ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g
AMD64=sha256:343d2a755d03352645d0c3ea63b3f687468a8390d2710e941b34feafac6663bc
BUNDLE=sparc64-qemu-openindiana-20g-beta-20260901.tar.zst
phase=${1:?phase required}
echo "ARM64_CI pipeline=$PIPELINE_ID commit=$COMMIT phase=$phase host=$(hostname) root=$ROOT"
case $phase in
prepare)
    # Preserve all historical files; replace ONLY proven duplicate bundles with
    # XFS reflinks. No volume, image, guest disk, transcript or partial is pruned.
    baseline=/mnt/disk-images/woodpecker/niagara-arm64-30/release/$BUNDLE
    for old in 32 34 35 36 37 38 46 47; do
        target=/mnt/disk-images/woodpecker/niagara-arm64-$old/release/$BUNDLE
        source=$baseline
        [[ $old -lt 46 ]] || source=/mnt/disk-images/woodpecker/cache/$BUNDLE
        [[ -f $source && -f $target && ! -L $target ]]
        cmp --silent "$source" "$target"
        if fuser "$target"; then
            echo "SPACE_PREP=FAIL file is in use: $target" >&2; exit 1
        else
            [[ $? == 1 ]] # unavailable tool or invalid invocation is not safe
        fi
        replacement=$(mktemp "${target}.reflink.XXXXXX")
        cp --reflink=always --preserve=all "$source" "$replacement"
        cmp --silent "$target" "$replacement"
        mv -f -- "$replacement" "$target"
        echo "SPACE_REFLINK=PASS bytes_preserved=$target"
    done
    # Regenerable package downloads, not logs or guest assets.
    apt-get clean
    df -h / "$ROOT"
    [[ $(df -Pk "$ROOT" | awk 'NR==2 {print $4}') -ge 14680064 ]]
    [[ $(df -Pk / | awk 'NR==2 {print $4}') -ge 262144 ]]
    mkdir -p sources release
    cp --reflink=always /mnt/disk-images/woodpecker/niagara-arm64-47/sources/qemu-049affb20df67162cf58deeaf74d5ad4b83cbdc3.tar.gz sources/
    cp --reflink=always /mnt/disk-images/woodpecker/cache/"$BUNDLE" release/
    (cd sources && sha256sum -c SHA256SUMS)
    (cd release && sha256sum -c ../RELEASE-ARCHIVE.SHA256SUMS)
    (cd assets/firmware && sha256sum -c ../../firmware.SHA256SUMS)
    test -c /dev/ppp
    touch state/prepared
    ;;
build)
    test -f state/prepared
    REBUILD_RELEASE_FIRMWARE=0 REBUILD_GUEST_RELEASE=2 \
        timeout --signal=TERM --kill-after=30s 2400 bash scripts/ci-self-contained-oci.sh build
    docker image inspect "$SELF_IMAGE" >state/image.json
    python3 - <<'PY'
import json
image, = json.load(open('state/image.json'))
assert (image['Os'], image['Architecture']) == ('linux', 'arm64')
labels = image['Config']['Labels']
assert labels['io.niagara.guest.cpus'] == '2'
assert labels['io.niagara.guest.kmdb'] == 'disabled'
assert labels['io.niagara.qemu.patchset'] == '0004-strand-id,0005-interrupt-dump,0006-mondo-deferral'
print('ARM64_IMAGE_IDENTITY=PASS id=' + image['Id'])
PY
    touch state/build.pass
    ;;
boot)
    test -f state/build.pass
    ! docker container inspect "$SELF_CONTAINER" >/dev/null 2>&1
    ! docker volume inspect "$SELF_VOLUME" >/dev/null 2>&1
    timeout --signal=TERM --kill-after=30s 900 bash ./appliance self-smoke | tee state/boot.log
    touch state/boot.pass
    ;;
cpus)
    test -f state/boot.pass
    timeout --signal=TERM --kill-after=30s 360 bash ./appliance self-smp | tee state/cpus.log
    # The existing probe prints psrinfo but its shell list can mask awk failure.
    # Require explicit CPU rows in the captured output as an independent gate.
    python3 - <<'PY'
import re
text = open('state/cpus.log').read()
online = set(re.findall(r'^\s*([0-9]+)\s+on-line\b', text, re.M))
assert online == {'0', '1'}, online
print('ARM64_TWO_CPUS=PASS cpus=0,1')
PY
    docker inspect "$SELF_CONTAINER" >state/container.inspect.json
    bash ./appliance self-evidence
    touch state/cpus.pass
    ;;
publish)
    test -f state/boot.pass
    test -f state/cpus.pass
    auth_dir=$(mktemp -d "$TMPDIR/auth.XXXXXX")
    anonymous_dir=$(mktemp -d "$TMPDIR/anonymous.XXXXXX")
    trap 'rm -rf -- "$auth_dir" "$anonymous_dir"' EXIT
    export DOCKER_CONFIG=$auth_dir
    docker login ghcr.io --username ryancnelson --password-stdin
    ARM_TAG=20260904-smp-preview-arm64-$PIPELINE_ID-${COMMIT:0:12}
    docker tag "$SELF_IMAGE" "$REPOSITORY:$ARM_TAG"
    docker push "$REPOSITORY:$ARM_TAG" | tee state/push-arm64.log
    docker manifest inspect --verbose "$REPOSITORY:$ARM_TAG" >state/arm64-manifest.json
    ARM64=$(python3 - <<'PY'
import json
image = json.load(open('state/arm64-manifest.json'))
assert image['Descriptor']['platform']['architecture'] == 'arm64'
assert image['Descriptor']['platform']['os'] == 'linux'
print(image['Descriptor']['digest'])
PY
    )
    # Verify the pushed descriptor against the exact image tested on Docker29.
    test "$ARM64" = "$(docker image inspect "$SELF_IMAGE" --format '{{.Descriptor.digest}}')"
    for tag in "20260904-smp-preview-multi-$PIPELINE_ID" smp-preview; do
        docker manifest create "$REPOSITORY:$tag" "$REPOSITORY@$AMD64" "$REPOSITORY@$ARM64"
        docker manifest push --purge "$REPOSITORY:$tag" | tee "state/push-$tag.log"
        docker --config "$anonymous_dir" manifest inspect "$REPOSITORY:$tag" >"state/manifest-$tag.json"
        python3 - "state/manifest-$tag.json" "$AMD64" "$ARM64" <<'PY'
import json, sys
index = json.load(open(sys.argv[1]))
manifests = index['manifests']
assert len(manifests) == 2
actual = {m['platform']['architecture']: m['digest'] for m in manifests}
assert set(actual) == {"amd64", "arm64"}
assert actual == {'amd64': sys.argv[2], 'arm64': sys.argv[3]}
assert all(m['platform']['os'] == 'linux' for m in manifests)
print('SMP_MULTIARCH_ANONYMOUS_VERIFY=PASS ' + str(actual))
PY
    done
    echo 'PREVIEW_CAVEAT=resolver compound test remains unresolved; no full-network certification claimed'
    touch state/publish.pass
    ;;
cleanup)
    if docker container inspect "$SELF_CONTAINER" >/dev/null 2>&1; then
        bash ./appliance self-evidence
        docker inspect "$SELF_CONTAINER" >state/container.inspect.json
    fi
    bash ./appliance self-stop
    echo "ARM64_CLEANUP=PASS evidence=$ROOT/state"
    ;;
*) echo "unknown phase: $phase" >&2; exit 2 ;;
esac
echo "ARM64_PHASE=PASS phase=$phase pipeline=$PIPELINE_ID"
