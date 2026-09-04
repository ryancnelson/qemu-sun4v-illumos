#!/usr/bin/env bash
# Ryan explicitly requested publication despite the known resolver gate failure.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE=sha256:343d2a755d03352645d0c3ea63b3f687468a8390d2710e941b34feafac6663bc
REPOSITORY=ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g
VERSION=20260904-smp-preview-343d2a755d03
PREVIEW=smp-preview

docker image inspect "$SOURCE" >"$ROOT/source-image.json"
python3 - "$ROOT/source-image.json" "$SOURCE" <<'PY'
import json, sys
image, = json.load(open(sys.argv[1]))
assert image["Id"] == sys.argv[2]
assert (image["Os"], image["Architecture"]) == ("linux", "amd64")
labels = image["Config"]["Labels"]
assert labels["io.niagara.guest.cpus"] == "2"
assert labels["io.niagara.guest.kmdb"] == "disabled"
assert labels["io.niagara.qemu.patchset"] == "0004-strand-id,0005-interrupt-dump,0006-mondo-deferral"
assert "SMP_CPUS=2" in image["Config"]["Env"]
print("SMP_PREVIEW_SOURCE=PASS image=" + image["Id"] + " host_arch=amd64 guest_cpus=2 kmdb=disabled")
PY
echo 'PRIOR_WOODPECKER_EVIDENCE=65,66 login=PASS smp=PASS resolver-gate=FAIL'
echo 'PUBLICATION_SCOPE=preview-only; existing latest and architecture release tags are unchanged'

auth_dir=$(mktemp -d)
anonymous_dir=$(mktemp -d)
trap 'rm -rf -- "$auth_dir" "$anonymous_dir"' EXIT
export DOCKER_CONFIG=$auth_dir
# Credential arrives only via stdin from Woodpecker's existing ghcr_token secret.
docker login ghcr.io --username ryancnelson --password-stdin
for tag in "$VERSION" "$PREVIEW"; do
    docker tag "$SOURCE" "$REPOSITORY:$tag"
    docker push "$REPOSITORY:$tag" | tee "$ROOT/push-$tag.log"
done

# Empty Docker configuration proves the existing public package is pullable
# anonymously. Docker 29's containerd store identifies this image by its OCI
# manifest digest. Compare that descriptor, not the different config digest.
for tag in "$VERSION" "$PREVIEW"; do
    docker --config "$anonymous_dir" manifest inspect --verbose "$REPOSITORY:$tag" >"$ROOT/manifest-$tag.json"
    python3 - "$ROOT/manifest-$tag.json" "$SOURCE" "$tag" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
def digests(value):
    if isinstance(value, dict):
        if isinstance(value.get("digest"), str):
            yield value["digest"]
        for child in value.values():
            yield from digests(child)
    elif isinstance(value, list):
        for child in value:
            yield from digests(child)
assert sys.argv[2] in set(digests(data)), "remote manifest does not match tested image"
print("SMP_PREVIEW_ANONYMOUS_VERIFY=PASS tag=" + sys.argv[3] + " image=" + sys.argv[2])
PY
done
echo "SMP_PREVIEW_PUBLISHED=$REPOSITORY:$PREVIEW"
echo "SMP_PREVIEW_VERSION=$REPOSITORY:$VERSION"
