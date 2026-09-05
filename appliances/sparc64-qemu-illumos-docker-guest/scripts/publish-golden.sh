#!/usr/bin/env bash
# Run by Woodpecker only after the matching architecture acceptance tests.
set -euo pipefail
cd "$(dirname "$0")/.."
run=${CI_PIPELINE_NUMBER:?}
commit=${CI_COMMIT_SHA:?}
arch=${GOLDEN_ARCH:?}
[[ $run =~ ^[0-9]+$ && $commit =~ ^[0-9a-f]{40}$ ]]
[[ $arch = amd64 || $arch = arm64 ]]
test -f state/test-first.pass
test -f state/test-second.pass
test "$(cat state/golden-commit)" = "$commit"
repo=ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g
image=sparc64-qemu-openindiana-20g:golden-$arch-$run
tag=release-$run-$arch-${commit:0:12}
test "$(docker image inspect "$image" --format '{{.Architecture}}')" = "$arch"
test "$(docker image inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.appliance-root-sha256"}}')" = "$(cat state/golden/root.sha256)"
test "$(docker image inspect "$image" --format '{{index .Config.Labels "io.niagara.qemu.contract"}}')" = sparc-tlb-range-flush-v1
auth=$(mktemp -d "$PWD/state/registry-auth.XXXXXX")
trap 'docker --config "$auth" logout ghcr.io >/dev/null 2>&1 || true; rm -rf -- "$auth"' EXIT
export DOCKER_CONFIG=$auth
docker login ghcr.io -u ryancnelson --password-stdin
docker tag "$image" "$repo:$tag"
docker push "$repo:$tag"
docker manifest inspect --verbose "$repo:$tag" >"state/golden/published-$arch.json"
python3 - "$arch" <<'PY' >"state/golden/published-$arch.digest"
import json, sys
arch = sys.argv[1]
d = json.load(open("state/golden/published-" + arch + ".json"))["Descriptor"]
assert d["platform"] == {"architecture": arch, "os": "linux"}, d
print(d["digest"])
PY
if [[ $arch = arm64 ]]; then
    amd=$(cat state/golden/published-amd64.digest)
    arm=$(cat state/golden/published-arm64.digest)
    [[ $amd =~ ^sha256:[0-9a-f]{64}$ && $arm =~ ^sha256:[0-9a-f]{64}$ ]]
    for index in "release-$run-${commit:0:12}" latest; do
        docker manifest create "$repo:$index" "$repo@$amd" "$repo@$arm"
        docker manifest push --purge "$repo:$index"
        docker manifest inspect "$repo:$index" >"state/golden/published-$index.json"
        python3 - "state/golden/published-$index.json" "$amd" "$arm" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1]))["manifests"]
assert len(entries) == 2
assert {e["platform"]["architecture"]: e["digest"] for e in entries} == {
    "amd64": sys.argv[2], "arm64": sys.argv[3]}
assert all(e["platform"]["os"] == "linux" for e in entries)
print("RELEASE_MULTIARCH_VERIFIED=PASS")
PY
    done
fi
touch "state/publish-$arch.pass"
