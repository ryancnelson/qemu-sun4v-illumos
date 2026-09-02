#!/usr/bin/env bash
set -euo pipefail

ROOT=${APPLIANCE_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FIRMWARE=${FIRMWARE_DIR:-$ROOT/assets/firmware}
OPENSPARC_CACHE=${OPENSPARC_CACHE:-/root/devel/.cache/opensparc}
ARCHIVE=$OPENSPARC_CACHE/OpenSPARCT1_Arch.1.5.tar.bz2
OPENSPARC=$OPENSPARC_CACHE/extracted
MDGEN=$OPENSPARC_CACHE/mdgen-linux/mdgen
BUILD_MDGEN=$ROOT/build-tools/tools/build-mdgen.sh

ARCHIVE_SHA256=833b086196e29eca296dd4722b1a2e853c2c8228634106ce71d59b48192518e9
BASE_MD_SHA256=b5d160f6f55a30d2ed56b5e24f9b1158180bb6a84d71fe222b4476945bd5b823
RELEASE_MD_SHA256=561859faa18066b8e9b5c408eb7cd7a5f2576d3208c4cfb3c07d77dcf468167c

die() {
    echo "prepare-release-firmware: $*" >&2
    exit 1
}

[[ -f $ARCHIVE ]] || die "missing cached official OpenSPARC archive: $ARCHIVE"
echo "$ARCHIVE_SHA256  $ARCHIVE" | sha256sum -c -
[[ -f $FIRMWARE/2c8t_guest.pp.bak ]] || die "missing accepted MD source"
[[ -x $BUILD_MDGEN ]] || die "missing staged mdgen build helper: $BUILD_MDGEN"

mkdir -p "$OPENSPARC"
if [[ ! -f $OPENSPARC/hypervisor/src/md/mdgen/mdmain.c ||
      ! -f $OPENSPARC/hypervisor/src/include/md/md_impl.h ]]; then
    tar -xjf "$ARCHIVE" -C "$OPENSPARC" \
        ./hypervisor/src/md/mdgen ./hypervisor/src/include
fi

OPENSPARC=$OPENSPARC "$BUILD_MDGEN" "$OPENSPARC_CACHE/mdgen-linux"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

"$MDGEN" --binary --outfile "$work/baseline.md" \
    "$FIRMWARE/2c8t_guest.pp.bak"
echo "$BASE_MD_SHA256  $work/baseline.md" | sha256sum -c -
echo MD_BASELINE_ROUNDTRIP=PASS

python3 "$ROOT/scripts/edit-release-md.py" \
    "$FIRMWARE/2c8t_guest.pp.bak" "$work/release.pp"
"$MDGEN" --binary --outfile "$work/release.md" "$work/release.pp"
echo "MD_RELEASE_CANDIDATE_SHA256=$(sha256sum "$work/release.md" | cut -d ' ' -f 1)"
echo "$RELEASE_MD_SHA256  $work/release.md" | sha256sum -c -

cp -p "$work/baseline.md" "$FIRMWARE/md.bin.manual"
cp -p "$work/release.md" "$FIRMWARE/2c8t_guest.md"
cp -p "$work/release.md" "$FIRMWARE/md.bin"
cp -p "$ROOT/firmware-policy/how-to-edit-nvram.txt" \
    "$FIRMWARE/how-to-edit-nvram.txt"

echo "MD_RELEASE_BUILD=PASS sha256=$RELEASE_MD_SHA256 bytes=$(stat -c %s "$FIRMWARE/md.bin")"
