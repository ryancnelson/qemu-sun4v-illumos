#!/usr/bin/env bash
# Stage immutable inputs for the Solaris-side Tribblix root finalizer.
set -euo pipefail

usage() {
    echo "usage: $0 input-hybrid.iso input-boot_archive ppp-runtime-dir new-stage-dir" >&2
    exit 2
}

[[ $# -eq 4 ]] || usage
INPUT_ISO=$(readlink -f "$1")
INPUT_ARCHIVE=$(readlink -f "$2")
PPP_RUNTIME=$(readlink -f "$3")
STAGE=$4
PROJ=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)

[[ -f "$INPUT_ISO" ]] || { echo "missing input image: $INPUT_ISO" >&2; exit 1; }
[[ -f "$INPUT_ARCHIVE" ]] || { echo "missing boot archive: $INPUT_ARCHIVE" >&2; exit 1; }
[[ ! -e "$STAGE" ]] || { echo "stage already exists: $STAGE" >&2; exit 1; }

ISO_MNT=$(mktemp -d /tmp/niag-iso-stage.XXXXXX)
UFS_MNT=$(mktemp -d /tmp/niag-ufs-stage.XXXXXX)
iso_mounted=0
ufs_mounted=0
cleanup() {
    if [[ $ufs_mounted -eq 1 ]]; then sudo umount "$UFS_MNT"; fi
    if [[ $iso_mounted -eq 1 ]]; then sudo umount "$ISO_MNT"; fi
    rmdir "$UFS_MNT" "$ISO_MNT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p "$STAGE/pkgs" "$STAGE/pkgs-unpacked" "$STAGE/channel" "$STAGE/ppp-runtime"
cp "$PROJ/tools/tribblix-pkgadd-admin" "$STAGE/"
cp "$PROJ/tools/tribblix-m34-base.pkgs" "$STAGE/"
cp "$PROJ/tools/tribblix-m34-installed-root-extra.pkgs" "$STAGE/"
cp "$PROJ/tools/tribblix-finalize-root.sh" "$STAGE/"
cp "$PROJ/tools/tribblix-resolv.conf" "$STAGE/"
cp "$PROJ/tools/chan/guest-getty.sh" "$STAGE/channel/"
cp "$PROJ/tools/chan/guest-ttymon.sh" "$STAGE/channel/"
cp "$PROJ/tools/chan/guest-niagchan.init" "$STAGE/channel/"
cp "$PROJ/tools/chan/guest-niaggetty.init" "$STAGE/channel/"
cp "$PROJ/tools/chan/guest-ppp-chan.pl" "$STAGE/channel/"
cp "$PROJ/tools/chan/guest-ppp-supervisor.sh" "$STAGE/channel/"
cp "$PROJ/tools/chan/guest-niagppp.init" "$STAGE/channel/"
cp -a "$PPP_RUNTIME"/. "$STAGE/ppp-runtime/"

sudo mount -t iso9660 -o loop,ro "$INPUT_ISO" "$ISO_MNT"
iso_mounted=1
for list in "$STAGE/tribblix-m34-base.pkgs" \
    "$STAGE/tribblix-m34-installed-root-extra.pkgs"
do
    while read -r pkg; do
        [[ -n "$pkg" && ${pkg:0:1} != '#' ]] || continue
        matches=("$ISO_MNT/pkgs/$pkg".*.zap)
        if [[ ${#matches[@]} -eq 1 && ! -f ${matches[0]} ]]; then
            # Some base members are already part of base-iso and therefore have
            # no archive in /pkgs. The Solaris finalizer proves they are present
            # in the alternate root and fails there if that assumption is false.
            echo "NOT_ON_MEDIA $pkg"
            continue
        fi
        [[ ${#matches[@]} -eq 1 ]] || {
            echo "expected at most one media archive for $pkg, found ${#matches[@]}" >&2
            exit 1
        }
        cp "${matches[0]}" "$STAGE/pkgs/"
        unzip -q "${matches[0]}" -d "$STAGE/pkgs-unpacked"
    done < "$list"
done
sudo umount "$ISO_MNT"
iso_mounted=0

sudo mount -t ufs -o ro,ufstype=sun,loop "$INPUT_ARCHIVE" "$UFS_MNT"
ufs_mounted=1
GOOD_HSIMD="$UFS_MNT/kernel/drv/sparcv9/hsimd"
[[ -f "$GOOD_HSIMD" ]] || { echo "plain ENOTTY hsimd is absent" >&2; exit 1; }
[[ $(sha256sum "$GOOD_HSIMD" | awk '{print $1}') == \
    d6d5f292ac5a395ad0ad763784e017c81b9200105c1b62a6c0f48acdccf01205 ]] || {
    echo "plain ENOTTY hsimd hash mismatch" >&2
    exit 1
}
sudo cp "$GOOD_HSIMD" "$STAGE/hsimd-enotty.good"
sudo chown "$(id -u):$(id -g)" "$STAGE/hsimd-enotty.good"
sudo umount "$UFS_MNT"
ufs_mounted=0

(cd "$STAGE" && sha256sum \
    tribblix-pkgadd-admin \
    tribblix-m34-base.pkgs \
    tribblix-m34-installed-root-extra.pkgs \
    tribblix-finalize-root.sh \
    tribblix-resolv.conf \
    hsimd-enotty.good \
    channel/* ppp-runtime/pppd64-tribblix \
    ppp-runtime/guest-utmp-ttymon \
    ppp-runtime/kernel/drv/sppp.conf ppp-runtime/kernel/drv/sppptun.conf \
    ppp-runtime/kernel/drv/sparcv9/* ppp-runtime/kernel/strmod/sparcv9/* \
    pkgs/* > SHA256SUMS)

echo "STAGE_OK $STAGE"
du -sh "$STAGE"
