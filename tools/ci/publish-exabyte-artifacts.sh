#!/usr/bin/env bash
# Publish one validated Niagara boot bundle to the Exabyte cache volume.
# Run this on Biggie. The remote bundle becomes visible only after every
# source and destination hash passes; READY is created last.
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: publish-exabyte-artifacts.sh BUILD_ID

Environment overrides:
  EXB_HOST              worker address (default 10.124.62.2)
  EXB_USER              worker SSH user (default ubuntu)
  EXB_JUMP              ProxyJump target (default ryan@100.112.19.55)
  EXB_IDENTITY          worker private key
  EXB_VOLUME_ROOT       mounted cache root (default /var/lib/niagara-ci)
  PRODUCT_ID            validated product candidate timestamp
  SMOKE_ID              validated unit-101 smoke timestamp
EOF
    exit 2
}

[[ $# == 1 ]] || usage
build_id=$1
[[ "$build_id" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "unsafe build id: $build_id" >&2; exit 2; }

exb_host=${EXB_HOST:-10.124.62.2}
exb_user=${EXB_USER:-ubuntu}
exb_jump=${EXB_JUMP:-ryan@100.112.19.55}
exb_identity=${EXB_IDENTITY:-/home/ryan/.cache/niagara-ci/exb-worker.key}
exb_volume_root=${EXB_VOLUME_ROOT:-/var/lib/niagara-ci}
product_id=${PRODUCT_ID:-20260825T182833Z}
smoke_id=${SMOKE_ID:-20260825T195322Z}

release=/home/ryan/devel/niagara-ci/artifacts/releases/$build_id
product=/home/ryan/devel/masa-sun4v/ci/candidates/product-$product_id
smoke=/home/ryan/devel/masa-sun4v/ci/candidates/smoke-unit101-$smoke_id
channel=/home/ryan/devel/niagara-ci/tools/ci/channel-disk-design
firmware=/home/ryan/devel/masa-sun4v/dist-pkg/vms/vm_test/hwconf
source_iso=/home/ryan/devel/niagara-ci/sources/OpenIndiana_Text_SPARC_12_2025.iso.clean

readonly BIG_SHA=126d39eb5de6fd18d68253f50bde1bcfa2b20f44febf6677c53ff60974284d5a
readonly ARC_SHA=1851f98012407ddd088365ffa0577889829b6739999f0e5804eca480ab477467
readonly ROOT_SHA=b9f9326beaf60a765c3a44ae0ee7c7d7fc2228b7a078588832ccb7273c21bf9d
readonly CHANNEL_SHA=9cebbadd4f02a79b249f4aef4505f544d65c9432847c17f2f26cddb02838ec8c
readonly ISO_SHA=173ade54c7f390ab0ba86500b0340f03aa92160a1805cb2d0ed7dd4e0bd85f04

[[ -f "$release/READY" && -f "$release/big-disk.img" \
   && -f "$release/boot_archive.ufs" \
   && -f "$product/images/root-unit100.img" \
   && -f "$channel/channel-disk.img" \
   && -f "$smoke/EVIDENCE.md" && -d "$firmware" \
   && -f "$source_iso" && -f "$exb_identity" ]] || {
    echo "one or more required inputs are missing" >&2; exit 1; }
[[ "$(stat -c %a "$exb_identity")" == 600 ]] || {
    echo "EXB_IDENTITY must have mode 0600" >&2; exit 1; }

ssh_cmd=(ssh -i "$exb_identity" -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new -o ProxyJump="$exb_jump")
remote="$exb_user@$exb_host"
remote_root="$exb_volume_root/bundles"
final="$remote_root/releases/$build_id"
partial="$remote_root/.${build_id}.partial"

remote_run() {
    "${ssh_cmd[@]}" "$remote" "$@"
}

sparse_copy() {
    local source=$1 destination=$2
    local source_dir source_name destination_dir destination_name
    source_dir=$(dirname -- "$source")
    source_name=$(basename -- "$source")
    destination_dir=$(dirname -- "$destination")
    destination_name=$(basename -- "$destination")
    tar --sparse --format=gnu -C "$source_dir" -cf - -- "$source_name" |
        remote_run "set -eu; sudo tar --sparse -xf - -C '$partial/$destination_dir'; if test '$source_name' != '$destination_name'; then sudo mv '$partial/$destination_dir/$source_name' '$partial/$destination'; fi"
}

task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT
hashes=$task_tmp/SHA256SUMS

cat >"$hashes" <<EOF
$ARC_SHA  artifacts/boot_archive.ufs
$BIG_SHA  artifacts/big-disk-unit103.img
$ROOT_SHA  artifacts/root-unit100.img
$CHANNEL_SHA  artifacts/channel-unit101.img
$ISO_SHA  sources/OpenIndiana_Text_SPARC_12_2025.iso.clean
EOF
while IFS= read -r -d '' item; do
    rel=${item#"$firmware"/}
    printf '%s  firmware/%s\n' "$(sha256sum "$item" | awk '{print $1}')" "$rel" >>"$hashes"
done < <(find "$firmware" -type f -print0 | sort -z)

echo "[1/5] validating pinned source hashes"
printf '%s  %s\n' "$ARC_SHA" "$release/boot_archive.ufs" \
    "$BIG_SHA" "$release/big-disk.img" \
    "$ROOT_SHA" "$product/images/root-unit100.img" \
    "$CHANNEL_SHA" "$channel/channel-disk.img" \
    "$ISO_SHA" "$source_iso" | sha256sum -c -

echo "[2/5] preparing private partial bundle"
remote_run "set -eu; sudo mkdir -p '$remote_root/releases' '$partial/artifacts' '$partial/evidence' '$partial/firmware' '$partial/sources'; sudo rm -f '$partial/READY'"

echo "[3/5] streaming physical extents with GNU sparse tar"
sparse_copy "$release/boot_archive.ufs" artifacts/boot_archive.ufs
sparse_copy "$release/big-disk.img" artifacts/big-disk-unit103.img
sparse_copy "$product/images/root-unit100.img" artifacts/root-unit100.img
sparse_copy "$channel/channel-disk.img" artifacts/channel-unit101.img
sparse_copy "$source_iso" sources/OpenIndiana_Text_SPARC_12_2025.iso.clean
tar --format=gnu -C "$firmware" -cf - . |
    remote_run "sudo tar -xf - -C '$partial/firmware'"
sparse_copy "$release/manifest.json" evidence/release-manifest.json
sparse_copy "$release/smoke.env" evidence/release-smoke.env
sparse_copy "$product/manifest.env" evidence/product-manifest.env
sparse_copy "$product/console.log" evidence/product-console.log
sparse_copy "$smoke/EVIDENCE.md" evidence/unit101-smoke-EVIDENCE.md
sparse_copy "$smoke/console.log" evidence/unit101-smoke-console.log
sparse_copy "$channel/DESIGN.md" evidence/channel-disk-DESIGN.md
sparse_copy "$channel/EVIDENCE-SUCCESS-20260825T191500Z.md" evidence/channel-disk-EVIDENCE.md
sparse_copy "$hashes" SHA256SUMS

echo "[4/5] checking destination sizes and bundle shape"
remote_run "set -eu; test \"\$(sudo stat -c %s '$partial/artifacts/boot_archive.ufs')\" = 192595968; test \"\$(sudo stat -c %s '$partial/artifacts/big-disk-unit103.img')\" = 2791702528; test \"\$(sudo stat -c %s '$partial/artifacts/root-unit100.img')\" = 10737418240; test \"\$(sudo stat -c %s '$partial/artifacts/channel-unit101.img')\" = 33554432; test \"\$(sudo stat -c %s '$partial/sources/OpenIndiana_Text_SPARC_12_2025.iso.clean')\" = 644198400; test \"\$(sudo find '$partial' -type s | wc -l)\" -eq 0"

echo "[5/5] atomically promoting bundle and current pointer"
remote_run "set -eu; test ! -e '$final'; sudo touch '$partial/READY'; sudo chmod -R a-w '$partial'; sudo mv '$partial' '$final'; sudo ln -sfn 'releases/$build_id' '$remote_root/current.new'; sudo mv -Tf '$remote_root/current.new' '$remote_root/current'; test -f '$final/READY'"

echo "published $final"
