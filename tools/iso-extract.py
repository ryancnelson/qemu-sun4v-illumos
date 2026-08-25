#!/usr/bin/env python3
"""
List or extract paths from an iso9660 image WITHOUT downloading all of it.

    tools/iso-extract.py ls   <iso-url-or-path> [/path/inside]
    tools/iso-extract.py get  <iso-url-or-path> /path/inside <outdir>

Reads only the sectors it needs via HTTP range requests (or seeks, for a local
file). Solaris install media is ~672MB but SUNWhea is a few MB, so pulling one
package costs seconds instead of a 20-minute full download.

iso9660 essentials used here:
  - 2048-byte sectors
  - Primary Volume Descriptor at sector 16; root directory record at offset 156
  - Directory record: extent LBA at +2 (LE32), data length at +10 (LE32),
    flags at +25 (bit 1 = directory), name length at +32, name at +33
  - Names may carry a ";1" version suffix
"""
import sys, os, struct, urllib.request

SECTOR = 2048


class Reader:
    def __init__(self, src):
        self.src = src
        self.is_url = src.startswith(("http://", "https://"))
        if self.is_url:
            # Resolve redirects once; archive.org 302s to a CDN node.
            req = urllib.request.Request(src, method="HEAD")
            with urllib.request.urlopen(req) as r:
                self.src = r.url
        else:
            self.fh = open(src, "rb")

    def read(self, offset, length):
        if not self.is_url:
            self.fh.seek(offset)
            return self.fh.read(length)
        req = urllib.request.Request(
            self.src, headers={"Range": f"bytes={offset}-{offset+length-1}"})
        with urllib.request.urlopen(req) as r:
            return r.read()

    def sectors(self, lba, nbytes):
        n = ((nbytes + SECTOR - 1) // SECTOR) * SECTOR
        return self.read(lba * SECTOR, n)


def parse_dir(data):
    """Yield (name, lba, size, is_dir) from raw directory extent bytes."""
    out, i = [], 0
    while i < len(data):
        rlen = data[i]
        if rlen == 0:
            # advance to next sector boundary; records never span sectors
            i = ((i // SECTOR) + 1) * SECTOR
            if i >= len(data):
                break
            continue
        lba  = struct.unpack_from("<I", data, i + 2)[0]
        size = struct.unpack_from("<I", data, i + 10)[0]
        flags = data[i + 25]
        nlen = data[i + 32]
        name = data[i + 33:i + 33 + nlen]
        if nlen == 1 and name in (b"\x00", b"\x01"):
            name = b"." if name == b"\x00" else b".."
        name = name.decode("latin-1").split(";")[0]
        out.append((name, lba, size, bool(flags & 2)))
        i += rlen
    return out


def root_dir(rd):
    pvd = rd.read(16 * SECTOR, SECTOR)
    if pvd[1:6] != b"CD001":
        raise SystemExit("not an iso9660 image (no CD001 at sector 16)")
    rec = pvd[156:156 + 34]
    lba = struct.unpack_from("<I", rec, 2)[0]
    size = struct.unpack_from("<I", rec, 10)[0]
    return lba, size


def walk_to(rd, path):
    lba, size = root_dir(rd)
    if path.strip("/") == "":
        return lba, size, True
    for part in path.strip("/").split("/"):
        entries = parse_dir(rd.sectors(lba, size))
        for name, l, s, isdir in entries:
            if name.upper() == part.upper():
                lba, size, found_dir = l, s, isdir
                break
        else:
            raise SystemExit(f"not found in image: {path} (missing '{part}')")
    return lba, size, found_dir


def cmd_ls(src, path="/"):
    rd = Reader(src)
    lba, size, isdir = walk_to(rd, path)
    if not isdir:
        print(f"{path}  ({size} bytes)")
        return
    for name, l, s, d in sorted(parse_dir(rd.sectors(lba, size))):
        if name in (".", ".."):
            continue
        print(f"{'d' if d else '-'} {s:>10}  {name}")


def cmd_get(src, path, outdir):
    rd = Reader(src)
    total = [0]

    def grab(lba, size, isdir, rel):
        dest = os.path.join(outdir, rel)
        if isdir:
            os.makedirs(dest, exist_ok=True)
            for name, l, s, d in parse_dir(rd.sectors(lba, size)):
                if name in (".", ".."):
                    continue
                grab(l, s, d, os.path.join(rel, name))
        else:
            os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
            data = rd.sectors(lba, size)[:size] if size else b""
            with open(dest, "wb") as f:
                f.write(data)
            total[0] += size

    lba, size, isdir = walk_to(rd, path)
    base = path.strip("/").split("/")[-1] or "root"
    grab(lba, size, isdir, base)
    print(f"extracted {base} -> {outdir}  ({total[0]/2**20:.1f}MB)")


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) >= 2 and a[0] == "ls":
        cmd_ls(a[1], a[2] if len(a) > 2 else "/")
    elif len(a) == 4 and a[0] == "get":
        cmd_get(a[1], a[2], a[3])
    else:
        sys.exit(__doc__)
