#!/usr/bin/env bash
set -euo pipefail

ROOT=${APPLIANCE_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
FIRMWARE=${FIRMWARE_DIR:-$ROOT/assets/firmware}
SMP_FIRMWARE=${SMP_FIRMWARE_DIR:-$ROOT/firmware-smp}
OPENSPARC_CACHE=${OPENSPARC_CACHE:-/root/devel/.cache/opensparc}
ARCHIVE=$OPENSPARC_CACHE/OpenSPARCT1_Arch.1.5.tar.bz2
OPENSPARC=$OPENSPARC_CACHE/extracted
MDGEN=$OPENSPARC_CACHE/mdgen-linux/mdgen
BUILD_MDGEN=$ROOT/build-tools/tools/build-mdgen.sh

ARCHIVE_SHA256=833b086196e29eca296dd4722b1a2e853c2c8228634106ce71d59b48192518e9
BASE_MD_SHA256=e5d0dfa0cef98daef762ed48a19ace9c372e4bc46342bc03200eb1cf219379ac
HV_SHA256=e9b63c8084a5a124253659c200709dc9de8281e66d3c8c349bef2faa4b065099

die() {
    echo "prepare-release-firmware: $*" >&2
    exit 1
}

[[ -f $ARCHIVE ]] || die "missing cached official OpenSPARC archive: $ARCHIVE"
echo "$ARCHIVE_SHA256  $ARCHIVE" | sha256sum -c -
[[ -r $SMP_FIRMWARE/SHA256SUMS ]] || die "missing SMP firmware manifest"
(cd "$SMP_FIRMWARE" && sha256sum -c SHA256SUMS)
[[ -x $BUILD_MDGEN ]] || die "missing staged mdgen build helper: $BUILD_MDGEN"

mkdir -p "$FIRMWARE"
cp -p "$SMP_FIRMWARE/2c8t_guest.pp.bak" "$FIRMWARE/2c8t_guest.pp.bak"

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
RELEASE_MD_SHA256=$(sha256sum "$work/release.md" | cut -d ' ' -f 1)
[[ ${#RELEASE_MD_SHA256} = 64 ]] || die "could not hash release guest MD"
echo "MD_RELEASE_CANDIDATE_SHA256=$RELEASE_MD_SHA256"

cp -p "$work/baseline.md" "$FIRMWARE/md.bin.manual"
cp -p "$work/release.md" "$FIRMWARE/2c8t_guest.md"
cp -p "$work/release.md" "$FIRMWARE/md.bin"
cp -p "$SMP_FIRMWARE/hv.bin" "$FIRMWARE/hv.bin"
cp -p "$ROOT/firmware-policy/how-to-edit-nvram.txt" \
    "$FIRMWARE/how-to-edit-nvram.txt"

echo "$HV_SHA256  $FIRMWARE/hv.bin" | sha256sum -c -
echo "MD_RELEASE_BUILD=PASS sha256=$RELEASE_MD_SHA256 bytes=$(stat -c %s "$FIRMWARE/md.bin")"
echo "HV_SMP_INSTALL=PASS sha256=$HV_SHA256 bytes=$(stat -c %s "$FIRMWARE/hv.bin")"
