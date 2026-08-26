#!/bin/ksh
# Niagara live-media safety gate for devfsadm.
#
# The boot archive installer preserves the original binary as
# /usr/sbin/devfsadm.niagara-real and installs this file as devfsadm.  The
# mount table is checked immediately before every invocation, including the
# early svc:/system/device/local call.

set -u

REAL=/usr/sbin/devfsadm.niagara-real
MOUNT=/sbin/mount
AWK=/usr/bin/awk
TABLE=/tmp/niagara-devfsadm-mounts.$$
RO=/tmp/niagara-devfsadm-ro.$$
PROBE=/etc/dev/.niagara-devfsadm-rw.$$

cleanup()
{
        /usr/bin/rm -f "$TABLE" "$RO" "$PROBE"
}
trap cleanup 0 1 2 3 15

fail()
{
        echo "NIAGARA_DEVFSADM_RW_GATE_FAIL: $*" >&2
        exit 1
}

[ -x "$REAL" ] || fail "missing preserved devfsadm binary: $REAL"
[ -x "$MOUNT" ] || fail "missing mount command: $MOUNT"

# Solaris mount -p fields are:
# special fsckdev mountpoint fstype fsckpass mount-at-boot options
list_ro_mounts()
{
        "$MOUNT" -p > "$TABLE" || fail "cannot read mount table"
        "$AWK" '
        NF >= 7 {
                n = split($7, option, ",")
                for (i = 1; i <= n; i++) {
                        if (option[i] == "ro") {
                                print $1 "|" $3 "|" $4
                                break
                        }
                }
        }' "$TABLE" > "$RO" || fail "cannot parse mount table"
}

list_ro_mounts
while IFS='|' read special mountpoint fstype
do
        [ -n "$special" ] || continue
        echo "NIAGARA_DEVFSADM_REMOUNT_RW: $mountpoint ($fstype on $special)" >&2
        # Solaris remounts an existing filesystem by mountpoint.  Supplying
        # both the special device and mountpoint can incorrectly require a
        # matching /etc/vfstab entry during early boot.
        "$MOUNT" -o remount,rw "$mountpoint" ||
            fail "cannot remount $mountpoint read-write"
done < "$RO"

# Do not trust the remount command's exit status alone.  Re-read the kernel's
# mount table and reject even one remaining read-only filesystem.
list_ro_mounts
if [ -s "$RO" ]; then
        while IFS='|' read special mountpoint fstype
        do
                [ -n "$special" ] || continue
                echo "NIAGARA_DEVFSADM_STILL_RO: $mountpoint ($fstype on $special)" >&2
        done < "$RO"
        fail "one or more mounted filesystems remain read-only"
fi

# devfsadm's first write is its lock in /etc/dev.  Exercise that exact parent
# directory before handing control to the preserved binary.
: > "$PROBE" || fail "/etc/dev is not writable"
/usr/bin/rm -f "$PROBE" || fail "cannot remove /etc/dev write probe"

echo "NIAGARA_DEVFSADM_RW_GATE_OK" >&2
trap - 0 1 2 3 15
/usr/bin/rm -f "$TABLE" "$RO"
exec "$REAL" "$@"
