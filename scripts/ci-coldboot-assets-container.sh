#!/bin/bash
# Host side; accepts only the owned mktemp directory from the transport.
set -euo pipefail
work=${1:?}
[[ "$work" =~ ^/tmp/sun4u-assets\.[A-Za-z0-9]{10}$ ]] || exit 1
[[ -d "$work" && ! -L "$work" && ! -e "$work/cid" ]] || exit 1
image=ubuntu@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b
label=${work##*/}
cleanup() {
 rc=$?
 trap - EXIT
 cid="$label"
 if [[ -f "$work/cid" ]]; then
  cid=$(cat "$work/cid")
  [[ "$cid" =~ ^[a-f0-9]{64}$ ]] || exit 1
 fi
  owner=$(timeout -k 5s 20s sudo -n docker inspect --format '{{index .Config.Labels "sun4u.assets.owner"}}' "$cid") || exit 1
  [[ "$owner" == "$label" ]] || exit 1
  timeout -k 5s 20s sudo -n docker inspect --format 'ASSET_CONTAINER_EXIT={{.State.ExitCode}} OOM={{.State.OOMKilled}}' "$cid" || rc=1
  timeout -k 5s 30s sudo -n docker rm -f "$cid" >/dev/null || exit 1
 exit "$rc"
}
trap cleanup EXIT
timeout -k 5s 20s sudo -n docker image inspect "$image" --format 'ASSET_IMAGE={{.Id}}'
timeout --signal=TERM --kill-after=10s 900s sudo -n docker run --name "$label" --cidfile "$work/cid" --label "sun4u.assets.owner=$label" \
 --memory 2g --cpus 2 --entrypoint /bin/bash \
 --mount "type=bind,src=$work,dst=/src,readonly" --workdir /src \
 "$image" /src/scripts/ci-coldboot-assets-job.sh
