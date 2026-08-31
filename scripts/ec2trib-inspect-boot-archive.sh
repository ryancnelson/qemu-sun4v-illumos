#!/usr/bin/bash

set -euo pipefail

ARCHIVE=${1:-}

fail()
{
    echo "NIAGARA_BOOT_ARCHIVE_INSPECT=FAIL reason=$*" >&2
    exit 1
}

[[ -n "$ARCHIVE" ]] || fail "usage: $0 PATH_TO_BOOT_ARCHIVE"
[[ -r "$ARCHIVE" ]] || fail "archive is unreadable: $ARCHIVE"

for tool in /usr/bin/mktemp /usr/bin/wc /usr/bin/digest /usr/bin/grep \
    /usr/bin/find /usr/bin/ls /usr/bin/rmdir /usr/bin/tr \
    /usr/sbin/lofiadm /usr/sbin/fstyp /usr/sbin/mount /usr/sbin/umount
do
    [[ -x "$tool" ]] || fail "required executable is missing: $tool"
done

MOUNT_DIR=$(/usr/bin/mktemp -d /tmp/niagara-boot-archive.XXXXXX)
LOFI=
RAW_LOFI=
MOUNTED=false

cleanup()
{
    rc=$?
    if [[ "$MOUNTED" = true ]]; then
        /usr/sbin/umount "$MOUNT_DIR" >/dev/null 2>&1 || true
    fi
    if [[ -n "$LOFI" ]]; then
        /usr/sbin/lofiadm -d "$LOFI" >/dev/null 2>&1 || true
    fi
    /usr/bin/rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
    exit "$rc"
}
trap cleanup EXIT HUP INT TERM

ARCHIVE_BYTES=$(/usr/bin/wc -c < "$ARCHIVE" | /usr/bin/tr -d ' ')
ARCHIVE_SHA256=$(/usr/bin/digest -a sha256 "$ARCHIVE")
LOFI=$(/usr/sbin/lofiadm -r -a "$ARCHIVE") || \
    fail "read-only lofi attachment failed"
RAW_LOFI=/dev/rlofi/${LOFI##*/}
echo "archive=$ARCHIVE"
echo "archive_bytes=$ARCHIVE_BYTES"
echo "archive_sha256=$ARCHIVE_SHA256"
echo "lofi=$LOFI"
echo "raw_lofi=$RAW_LOFI"

if ! FILESYSTEM=$(/usr/sbin/fstyp "$RAW_LOFI"); then
    echo "NIAGARA_BOOT_ARCHIVE_INSPECT=BLOCKED reason=Tribblix fstyp did not recognize the SPARC UFS archive"
    exit 20
fi
echo "filesystem=$FILESYSTEM"

if ! /usr/sbin/mount -F ufs -o ro "$LOFI" "$MOUNT_DIR"; then
    echo "NIAGARA_BOOT_ARCHIVE_INSPECT=BLOCKED reason=Tribblix could not mount the UFS archive read-only"
    exit 20
fi
MOUNTED=true

echo "mount_dir=$MOUNT_DIR"
for path in \
    etc/name_to_major \
    etc/driver_aliases \
    etc/path_to_inst \
    platform/sun4v/kernel/drv/sparcv9/hsimd
do
    if [[ -e "$MOUNT_DIR/$path" ]]; then
        /usr/bin/ls -l "$MOUNT_DIR/$path"
    else
        echo "missing=$path"
    fi
done

for registration in etc/name_to_major etc/driver_aliases etc/path_to_inst
do
    if [[ -r "$MOUNT_DIR/$registration" ]]; then
        /usr/bin/grep hsimd "$MOUNT_DIR/$registration" || true
    fi
done

echo "NIAGARA_BOOT_ARCHIVE_INSPECT=PASS"
