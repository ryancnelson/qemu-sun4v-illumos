#!/usr/bin/env python3
"""Add the Niagara hsimd-media fallback to OpenIndiana's media-fs-root."""

from pathlib import Path
import sys


MARKER = "# NIAGARA_HSIMD_MEDIA_FALLBACK_V2"
LEGACY_MARKER = "# NIAGARA_HSIMD_MEDIA_FALLBACK"
ANCHOR = "# ... else try network (NFS)"
NETWORK_GUARD = 'if [ ! $MOUNT | grep -q "^/.cdrom" ] || [ ! -f /.liveusb ]; then'
NO_NETWORK_GUARD = r'''# Niagara has no Ethernet device.  Networking is exclusively channel -> PPP;
# DHCP/NFS discovery is therefore a known-dead branch for this archive.
if false; then'''
FALLBACK = r'''# NIAGARA_HSIMD_MEDIA_FALLBACK_V2
# QEMU's Niagara machine exposes the boot ISO as an ordinary hsimd disk, not
# as CD hardware.  Accept an already-mounted verified medium.  Otherwise try
# slice zero first (the proven unit-103 mapping), then whole-disk s2 aliases.
# Require HSFS and the install media's volume-set identifier.
if [ -f "$SOLARIS_ZLIB" -a -f /.cdrom/.volsetid ]; then
	echo "Niagara hsimd install media already mounted" >/dev/msglog
else
	for niag_dev in /dev/dsk/*s0 /dev/dsk/*s2
	do
		[ -b "$niag_dev" ] || continue
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
    if ANCHOR not in source:
        print(f"anchor not found: {ANCHOR}", file=sys.stderr)
        return 1
    if MARKER in source:
        result = source
    elif LEGACY_MARKER in source:
        start = source.index(LEGACY_MARKER)
        end = source.index(ANCHOR, start)
        result = source[:start] + FALLBACK + source[end:]
    else:
        result = source.replace(ANCHOR, FALLBACK + ANCHOR, 1)
    if NETWORK_GUARD not in result:
        if NO_NETWORK_GUARD not in result:
            print("stock network guard not found", file=sys.stderr)
            return 1
    else:
        result = result.replace(NETWORK_GUARD, NO_NETWORK_GUARD, 1)
    Path(sys.argv[2]).write_text(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
