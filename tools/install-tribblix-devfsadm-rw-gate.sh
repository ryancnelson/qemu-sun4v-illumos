#!/bin/ksh
# Install the Niagara devfsadm RW gate into a mounted SPARC Solaris/Tribblix
# root, including a boot archive mounted through lofi.
set -u

usage()
{
        echo "usage: $0 altroot wrapper" >&2
        exit 2
}

[ $# -eq 2 ] || usage
ALTROOT=$1
WRAPPER=$2

case "$ALTROOT" in
/|""|/a/../*|*/../*)
        echo "ERROR: unsafe alternate root: $ALTROOT" >&2
        exit 1
        ;;
esac

DEST=$ALTROOT/usr/sbin/devfsadm
REAL=$ALTROOT/usr/sbin/devfsadm.niagara-real

[ -f "$WRAPPER" ] || { echo "ERROR: missing wrapper: $WRAPPER" >&2; exit 1; }
[ -d "$ALTROOT/etc/dev" ] || { echo "ERROR: missing $ALTROOT/etc/dev" >&2; exit 1; }
[ -d "$ALTROOT/usr/sbin" ] || { echo "ERROR: missing $ALTROOT/usr/sbin" >&2; exit 1; }

if [ -f "$REAL" ]; then
        /usr/bin/grep 'NIAGARA_DEVFSADM_RW_GATE_OK' "$DEST" >/dev/null 2>&1 || {
                echo "ERROR: preserved binary exists but wrapper is not installed" >&2
                exit 1
        }
        echo "PRESENT devfsadm RW gate"
else
        [ -x "$DEST" ] || { echo "ERROR: missing original devfsadm: $DEST" >&2; exit 1; }
        /usr/bin/grep 'NIAGARA_DEVFSADM_RW_GATE_OK' "$DEST" >/dev/null 2>&1 && {
                echo "ERROR: wrapper present but preserved real devfsadm is missing" >&2
                exit 1
        }
        /usr/bin/mv "$DEST" "$REAL" || exit 1
        /usr/bin/cp "$WRAPPER" "$DEST" || exit 1
fi

/usr/bin/chown root:bin "$DEST" "$REAL" || exit 1
/usr/bin/chmod 755 "$DEST" "$REAL" || exit 1
/usr/bin/grep 'NIAGARA_DEVFSADM_RW_GATE_OK' "$DEST" >/dev/null 2>&1 || exit 1
[ -x "$REAL" ] || exit 1

echo "INSTALL_DEVFSADM_RW_GATE_OK $ALTROOT"
