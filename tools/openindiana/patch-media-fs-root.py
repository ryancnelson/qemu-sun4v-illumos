#!/usr/bin/env python3
"""Add the Niagara hsimd-media fallback to OpenIndiana's media-fs-root."""

from pathlib import Path
import sys


MARKER = "# NIAGARA_HSIMD_MEDIA_FALLBACK"
ANCHOR = "# ... else try network (NFS)"
FALLBACK = r'''# NIAGARA_HSIMD_MEDIA_FALLBACK
# QEMU's Niagara machine exposes the boot ISO as an ordinary hsimd disk, not
# as CD hardware.  Try only whole-disk s2 candidates, require HSFS, and verify
# the install media's volume-set identifier before accepting it.
if ! $MOUNT | grep -q "^/.cdrom"; then
	for niag_dev in /dev/dsk/*s2
	do
		niag_rdev=`echo "$niag_dev" | $SED 's|/dsk/|/rdsk/|'`
		/usr/lib/fs/hsfs/fstyp "$niag_rdev" >/dev/null 2>&1 || continue
		$MOUNT -F hsfs -o ro "$niag_dev" /.cdrom || continue
		niag_cdvolsetid=
		[ -f /.cdrom/.volsetid ] && niag_cdvolsetid=$( < "/.cdrom/.volsetid" )
		if [ "$volsetid" = "$niag_cdvolsetid" -a -f "$SOLARIS_ZLIB" ]; then
			echo "Niagara hsimd install media: $niag_dev" >/dev/msglog
			break
		fi
		/sbin/umount -f /.cdrom
	done
fi

'''


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} input-media-fs-root output", file=sys.stderr)
        return 2
    source = Path(sys.argv[1]).read_text()
    if MARKER in source:
        result = source
    else:
        if ANCHOR not in source:
            print(f"anchor not found: {ANCHOR}", file=sys.stderr)
            return 1
        result = source.replace(ANCHOR, FALLBACK + ANCHOR, 1)
    Path(sys.argv[2]).write_text(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
