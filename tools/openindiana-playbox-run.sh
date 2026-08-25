#!/usr/bin/env bash
# Run a disposable OpenIndiana SPARC smoke test on niagara-playbox.
#
# The imported ISO is an immutable parent.  Every run opens a fresh XFS
# reflink child because Niagara's vdisk is MAP_SHARED and QEMU therefore opens
# the backing file writable even when the guest media is conceptually a CD.
# Killing the test is safe: discard the child and run this script again.
set -euo pipefail

H="${HOME}"
PROJECT="${NIAGARA_PROJECT:-$H/niag-proj}"
QEMU="${QEMU_BIN:-$PROJECT/qemu/build/qemu-system-sparc64}"
FW="${NIAGARA_FW:-$H/sun4v/firmware/base-1gib}"
SOURCE="${OPENINDIANA_SOURCE:-$H/sun4v/images/OpenIndiana_Text_SPARC_12_2025.iso.clean}"
WORK="${OPENINDIANA_WORK:-$H/sun4v/images/OpenIndiana_Text_SPARC_12_2025.test.iso}"
MONITOR="${OPENINDIANA_MONITOR:-/tmp/openindiana-niagara-monitor.sock}"
EXPECTED_SIZE=644198400
EXPECTED_SHA256=173ade54c7f390ab0ba86500b0340f03aa92160a1805cb2d0ed7dd4e0bd85f04

die() {
    printf 'openindiana-playbox-run: %s\n' "$*" >&2
    exit 1
}

[[ -x "$QEMU" ]] || die "QEMU missing or not executable: $QEMU"
[[ -d "$FW" ]] || die "firmware directory missing: $FW"
[[ -f "$SOURCE" ]] || die "immutable ISO missing: $SOURCE"
[[ "$WORK" != "$SOURCE" ]] || die "working image must differ from immutable source"

actual_size=$(stat -c %s "$SOURCE")
[[ "$actual_size" = "$EXPECTED_SIZE" ]] ||
    die "source size $actual_size, expected $EXPECTED_SIZE"

actual_sha256=$(sha256sum "$SOURCE" | awk '{print $1}')
[[ "$actual_sha256" = "$EXPECTED_SHA256" ]] ||
    die "source SHA-256 $actual_sha256, expected $EXPECTED_SHA256"

if pgrep -f 'qemu-system-sparc64 -M niagara' >/dev/null; then
    die "a Niagara QEMU is already running"
fi

case "$WORK" in
    "$H"/sun4v/images/*.test.iso) ;;
    *) die "refusing to replace unexpected working path: $WORK" ;;
esac

rm -f -- "$WORK"
cp --reflink=always -- "$SOURCE" "$WORK"
cmp -s -- "$SOURCE" "$WORK" || die "reflink child differs immediately after copy"
rm -f -- "$MONITOR"

cat <<EOF
OpenIndiana source verified:
  $SOURCE
Disposable test image:
  $WORK

At the OBP prompt, start with:
  boot disk -v

If OBP cannot find the archive, retry from a fresh run with:
  boot disk:d -v

The QEMU monitor is available at:
  $MONITOR
EOF

exec "$QEMU" -M niagara -L "$FW" -m 1024 -nographic \
    -monitor "unix:$MONITOR,server,nowait" \
    -drive "if=pflash,file=$WORK,format=raw"
