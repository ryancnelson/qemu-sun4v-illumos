#!/usr/bin/env bash
set -euo pipefail

ROOT=${APPLIANCE_ROOT:-$HOME/devel/sparc64-qemu-illumos-docker-guest}
PIPELINE_ID=${CI_PIPELINE_NUMBER:-manual}
SELF_IMAGE=${SELF_IMAGE:-sparc64-qemu-openindiana-20g:self-contained}
GHCR_IMAGE=${GHCR_IMAGE:-ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g}
LATEST_TAG=${LATEST_TAG:-latest}

case "$PIPELINE_ID" in
    *[!A-Za-z0-9._-]*|'')
        echo "invalid pipeline identity: $PIPELINE_ID" >&2
        exit 2
        ;;
esac

export SELF_CONTAINER="sparc64-qemu-openindiana-20g-ci-$PIPELINE_ID"
EVIDENCE="$ROOT/state/self-contained/woodpecker-$PIPELINE_ID"

capture_and_stop() {
    if docker container inspect "$SELF_CONTAINER" >/dev/null 2>&1; then
        "$ROOT/appliance" self-evidence || true
        mkdir -p "$EVIDENCE"
        cp -a "$ROOT/state/self-contained/container-state/." "$EVIDENCE/" \
            2>/dev/null || true
        docker inspect "$SELF_CONTAINER" >"$EVIDENCE/container.inspect.json" \
            2>/dev/null || true
        "$ROOT/appliance" self-stop || true
    fi
}

case "${1:-}" in
build)
    cd "$ROOT"
    for stale_volume in $(docker volume ls -q \
        --filter label=io.niagara.appliance-ci=1); do
        docker volume rm "$stale_volume" >/dev/null 2>&1 || true
    done
    bash -n appliance scripts/container-entrypoint.sh \
        scripts/container-network.sh \
        scripts/ci-self-contained-oci.sh
    python3 -m py_compile scripts/guest-command.py scripts/smoke-login.py \
        scripts/edit-release-md.py \
        scripts/smoke-interactive-console.py \
        scripts/test-console-mode-policy.py \
        scripts/test-network-helper-policy.py \
        scripts/test-drive-cache-policy.py \
        scripts/test-openboot-policy.py
    python3 scripts/test-console-mode-policy.py
    python3 scripts/test-network-helper-policy.py
    python3 scripts/test-drive-cache-policy.py
    python3 scripts/test-openboot-policy.py
    ./scripts/prepare-release-firmware.sh
    ./appliance self-build
    docker image inspect "$SELF_IMAGE" --format \
        'OCI_BUILD=PASS id={{.Id}} bytes={{.Size}}'
    ;;
interactive)
    cd "$ROOT"
    interactive_container="${SELF_CONTAINER}-interactive"
    trap 'docker rm -f "$interactive_container" >/dev/null 2>&1 || true' EXIT
    python3 scripts/smoke-interactive-console.py \
        --image "$SELF_IMAGE" \
        --name "$interactive_container" \
        --transcript "$EVIDENCE/interactive-console.log"
    ;;
test)
    cd "$ROOT"
    trap capture_and_stop EXIT
    "$ROOT/appliance" self-stop
    if docker container inspect "$SELF_CONTAINER" >/dev/null 2>&1; then
        echo "refusing to reuse existing CI container: $SELF_CONTAINER" >&2
        exit 1
    fi
    ./appliance self-smoke | tee "state/self-contained/woodpecker-$PIPELINE_ID-smoke.txt"
    ./appliance self-network | tee "state/self-contained/woodpecker-$PIPELINE_ID-network.txt"
    ./appliance self-inspect | tee "state/self-contained/woodpecker-$PIPELINE_ID-inspect.txt"
    ./appliance self-inventory | tee "state/self-contained/woodpecker-$PIPELINE_ID-inventory.txt"
    docker inspect --format '{{json .Mounts}}' "$SELF_CONTAINER" |
        python3 -c 'import json,sys
m=json.load(sys.stdin)
assert not [x for x in m if x["Type"] == "bind"], m
assert len(m) == 1 and m[0]["Type"] == "volume", m
assert m[0]["Destination"] == "/var/lib/illumos-appliance", m
print("OCI_NO_BIND_MOUNTS=PASS")'
    if docker cp "$SELF_CONTAINER:/state/console.log" - 2>/dev/null |
        tar -xOf - 2>/dev/null |
        grep -E 'panic|Performing full ZFS device scan|NIAGARA_DEVFSADM_RW_GATE_FAIL'
    then
        echo "known boot failure signature found" >&2
        exit 1
    fi
    echo "OCI_BOOT_FAILURE_SIGNATURES=ABSENT"
    echo "OCI_COLD_BOOT_TEST=PASS"
    ;;
release)
    tag=${RELEASE_TAG:-}
    case "$tag" in
        *[!A-Za-z0-9._-]*|'')
            echo "RELEASE_TAG must be a non-empty Docker tag" >&2
            exit 2
            ;;
    esac
    case "$LATEST_TAG" in
        *[!A-Za-z0-9._-]*|'')
            echo "LATEST_TAG must be a non-empty Docker tag" >&2
            exit 2
            ;;
    esac
    docker tag "$SELF_IMAGE" "$GHCR_IMAGE:$tag"
    docker tag "$SELF_IMAGE" "$GHCR_IMAGE:$LATEST_TAG"
    docker push "$GHCR_IMAGE:$tag"
    docker push "$GHCR_IMAGE:$LATEST_TAG"
    dated_digest=$(docker image inspect "$GHCR_IMAGE:$tag" --format '{{.Id}}')
    latest_digest=$(docker image inspect "$GHCR_IMAGE:$LATEST_TAG" --format '{{.Id}}')
    test "$dated_digest" = "$latest_digest"
    echo "OCI_RELEASE=PASS tag=$tag moving_tag=$LATEST_TAG image_id=$dated_digest"
    ;;
*)
    echo "usage: $0 build|interactive|test|release" >&2
    exit 2
    ;;
esac
