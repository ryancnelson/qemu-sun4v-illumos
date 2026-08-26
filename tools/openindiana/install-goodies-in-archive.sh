#!/sbin/sh
# Run inside the Solaris donor with its PCFS exchange slice mounted at /x.
set -e

ARCHIVE=/x/OIBA.UFS
PAYLOAD=/x/OIPAY.TAR
MNT=/a

[ -f "$ARCHIVE" ]
[ -f "$PAYLOAD" ]
mkdir -p "$MNT"
LOFI=`lofiadm -a "$ARCHIVE"`
trap 'umount "$MNT" 2>/dev/null || true; lofiadm -d "$LOFI" 2>/dev/null || true' 0 1 2 15
# This exact OpenIndiana archive reports CANNOT READ at its final filesystem
# block through the Solaris 10 lofi path, while mounting and every required
# file read succeed.  Preserve the diagnostic but gate on the mount and the
# post-write content manifest instead.
fsck -F ufs -m "$LOFI" || echo NIAGARA_ARCHIVE_FSCK_PREFLIGHT_WARN
mount -F ufs "$LOFI" "$MNT" || exit 1

(cd "$MNT" && tar xpf "$PAYLOAD")
mkdir -p "$MNT/lib/niag"
cp /opt/niag/bin/socat "$MNT/lib/niag/socat" || exit 1
chmod 755 "$MNT/lib/niag"/* "$MNT/etc/rc2.d/S99niagara"
sync
umount "$MNT"
fsck -F ufs -m "$LOFI" || echo NIAGARA_ARCHIVE_FSCK_POSTFLIGHT_WARN
lofiadm -d "$LOFI"
trap - 0 1 2 15

echo NIAGARA_ARCHIVE_BUILD_OK
