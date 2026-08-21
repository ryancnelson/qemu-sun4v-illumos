#!/usr/bin/env python3
"""
Read and edit a Sun VTOC (SPARC disk label) in sector 0 of a raw device/image.

    tools/vtoc.py show    DEV
    tools/vtoc.py set     DEV SLICE START_CYL NBLKS
    tools/vtoc.py set-ncyl DEV NCYL
    tools/vtoc.py verify  DEV

Why this exists: the label carries a 16-bit checksum at offset 0x1fe. OBP
VALIDATES it and refuses the disk with "Bad checksum in disk label" if it is
wrong, while QEMU's VTOC reader does NOT check it. So a hand-edited label
appears to work right up until OBP rejects it. Every write here recomputes the
checksum.

Layout facts used (Sun dk_label, big-endian):
    0x1bc   dk_map[0]      partition map: 8 entries of {uint32 cyl, uint32 nblk}
    0x1d0   dk_map[2].nblk  <- q.bin reads THIS as the disk size
                               (DISK_S2NBLK_OFFSET in vdev_simdisk.h)
    0x1fc   dk_magic (0xDABE)
    0x1fe   dk_cksum        XOR of all 256 big-endian uint16s == 0

Slice 2 is the conventional whole-disk "backup" slice; q.bin uses its nblk as
the served disk size, so slice 2 must cover everything you want reachable.
"""
import struct, sys

DK_MAP     = 0x1bc
DK_NCYL    = 0x1b0
DK_ACYL    = 0x1b2
DK_NHEAD   = 0x1b4
DK_NSECT   = 0x1b6
DK_MAGIC   = 0x1fc
DK_CKSUM   = 0x1fe
MAGIC      = 0xDABE
SECTOR     = 512


def read_label(dev):
    with open(dev, "rb") as f:
        return bytearray(f.read(SECTOR))


def checksum(label):
    """XOR of all 256 big-endian uint16s. A valid label XORs to 0."""
    x = 0
    for i in range(0, SECTOR, 2):
        x ^= struct.unpack_from(">H", label, i)[0]
    return x


def fix_checksum(label):
    struct.pack_into(">H", label, DK_CKSUM, 0)
    struct.pack_into(">H", label, DK_CKSUM, checksum(label))


def slices(label):
    out = []
    for i in range(8):
        cyl, nblk = struct.unpack_from(">II", label, DK_MAP + i * 8)
        out.append((i, cyl, nblk))
    return out


def geometry(label):
    return struct.unpack_from(">HHHH", label, DK_NCYL)


def cmd_show(dev):
    label = read_label(dev)
    magic = struct.unpack_from(">H", label, DK_MAGIC)[0]
    print(f"device : {dev}")
    print(f"magic  : 0x{magic:04X} {'(ok)' if magic == MAGIC else '(BAD, expected 0xDABE)'}")
    print(f"cksum  : XOR=0x{checksum(label):04X} {'(valid)' if checksum(label) == 0 else '(INVALID)'}")
    print(f"ascii  : {label[:60].split(bytes([0]))[0].decode('ascii', 'replace')}")
    ncyl, acyl, nhead, nsect = geometry(label)
    spc = nhead * nsect
    print(f"geom   : ncyl={ncyl} acyl={acyl} nhead={nhead} nsect={nsect} "
          f"({spc} sectors/cylinder)")
    print()
    print("  slice  start_cyl  start_sector      nblks         size   note")
    for i, cyl, nblk in slices(label):
        if nblk == 0:
            print(f"  s{i}     {'-':>9}  {'-':>12}  {'-':>9}     {'(unused)':>9}")
            continue
        note = "<- q.bin reads this as disk size" if i == 2 else ""
        start_sector = cyl * spc if spc else 0
        print(f"  s{i}     {cyl:>9}  {start_sector:>12}  {nblk:>9}  "
              f"{nblk*SECTOR/2**20:>8.1f}MB   {note}")


def cmd_set(dev, sl, start, nblks):
    if not 0 <= sl <= 7:
        sys.exit("slice must be 0..7")
    label = read_label(dev)
    if struct.unpack_from(">H", label, DK_MAGIC)[0] != MAGIC:
        sys.exit("refusing to edit: sector 0 has no 0xDABE magic (not a Sun label?)")
    struct.pack_into(">II", label, DK_MAP + sl * 8, start, nblks)
    fix_checksum(label)
    with open(dev, "r+b") as f:
        f.write(bytes(label))
    print(f"s{sl}: start={start} nblks={nblks} ({nblks*SECTOR/2**20:.1f}MB), checksum recomputed")


def cmd_set_ncyl(dev, ncyl):
    if not 1 <= ncyl <= 0xffff:
        sys.exit("ncyl must be 1..65535")
    label = read_label(dev)
    if struct.unpack_from(">H", label, DK_MAGIC)[0] != MAGIC:
        sys.exit("refusing to edit: sector 0 has no 0xDABE magic (not a Sun label?)")
    struct.pack_into(">H", label, DK_NCYL, ncyl)
    fix_checksum(label)
    with open(dev, "r+b") as f:
        f.write(bytes(label))
    print(f"ncyl={ncyl}, checksum recomputed")


def cmd_verify(dev):
    label = read_label(dev)
    ok = True
    if struct.unpack_from(">H", label, DK_MAGIC)[0] != MAGIC:
        print("FAIL: bad magic"); ok = False
    if checksum(label) != 0:
        print("FAIL: checksum invalid (OBP will reject this disk)"); ok = False
    ncyl, acyl, nhead, nsect = geometry(label)
    spc = nhead * nsect
    if not spc:
        print("FAIL: invalid zero sectors/cylinder geometry"); ok = False
    # dk_map starts are cylinders while lengths are sectors. Convert starts
    # before overlap/coverage checks. Slice 2 is the whole-disk backup.
    live = [(i, c, n) for i, c, n in slices(label) if n and i != 2]
    for a in range(len(live)):
        for b in range(a + 1, len(live)):
            i, ci, ni = live[a]; j, cj, nj = live[b]
            si, sj = ci * spc, cj * spc
            # Hybrid Sun boot CDs commonly publish several platform slices as
            # exact aliases of the same HSFS extent (for example s3..s6).
            if si == sj and ni == nj:
                continue
            if si < sj + nj and sj < si + ni:
                print(f"FAIL: s{i} and s{j} overlap"); ok = False
    s2 = dict((i, (c, n)) for i, c, n in slices(label)).get(2)
    if s2 and s2[1]:
        for i, c, n in live:
            end = c * spc + n
            if end > s2[1]:
                print(f"FAIL: s{i} extends past slice 2 ({end} > {s2[1]}) — "
                      f"q.bin will not serve those blocks"); ok = False
        label_sectors = (ncyl + acyl) * spc
        if label_sectors < s2[1]:
            print(f"WARN: label geometry covers {label_sectors} sectors but s2 covers "
                  f"{s2[1]} (set ncyl before boot)")
    print("OK: label valid" if ok else "INVALID")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) == 2 and a[0] == "show":     cmd_show(a[1])
    elif len(a) == 2 and a[0] == "verify": cmd_verify(a[1])
    elif len(a) == 3 and a[0] == "set-ncyl": cmd_set_ncyl(a[1], int(a[2]))
    elif len(a) == 5 and a[0] == "set":    cmd_set(a[1], int(a[2]), int(a[3]), int(a[4]))
    else:
        sys.exit(__doc__)
