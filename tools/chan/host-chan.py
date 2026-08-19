#!/usr/bin/env python3
"""Host side of the P2-014 channel.

    tools/chan/host-chan.py init                 zero both control blocks
    tools/chan/host-chan.py send  <file>         publish a frame, wait for echo
    tools/chan/host-chan.py status               show both control blocks

Layout constants are PARSED OUT OF chan.h rather than restated here, so the two
ends cannot drift. That drift is not hypothetical: a literal 2668003328, wrong by
832 blocks, was once copied into niagara.c from a stale note and survived because
it happened to stay inside the region.

Since P2-012 the host reaches the guest's disk by plain file I/O on the image --
the same pages the guest sees through MAP_SHARED. No msync, no monitor, no signal.
"""

import os, re, struct, sys, time, pathlib, subprocess

PROJ = pathlib.Path(__file__).resolve().parents[2]
HDR = PROJ / "tools" / "chan" / "chan.h"


def consts():
    """Pull CHAN_* integer defines out of chan.h. Single source of truth."""
    txt = HDR.read_text()
    out = {}
    # [ \t]+ NOT \s+: \s matches newlines, so the `#define CHAN_H` include guard
    # swallowed the next line and CHAN_MAGIC vanished. Values only, same line.
    for m in re.finditer(r'#define[ \t]+(CHAN_\w+)[ \t]+([^/\n]+)', txt):
        name, val = m.group(1), m.group(2).strip()
        if not val:
            continue
        val = re.sub(r'\b(CHAN_\w+)\b',
                     lambda g: str(out[g.group(1)]) if g.group(1) in out else g.group(1),
                     val)
        # strip C integer suffixes only where they terminate a numeric literal
        val = re.sub(r'(0[xX][0-9a-fA-F]+|\d+)[uUlL]+', r'\1', val)
        try:
            out[name] = int(eval(val, {}, {}))
        except Exception:
            pass
    return out


C = consts()
MAGIC = C["CHAN_MAGIC"]
BLK = C["CHAN_BLK"]
BASE = C["CHAN_HOST_BYTE"]
SEQ_END = C["CHAN_SEQ_END_OFF"]
DATA_BYTES = C["CHAN_DATA_BYTES"]


def image():
    """Resolve the image path through the one authority, exchange.sh/img_require."""
    r = subprocess.run(["bash", "-c",
                        f'source {PROJ}/tools/lib/image.sh; '
                        f'img_require "${{NIAGARA_IMAGES:-datapool/niagara/images}}"'],
                       capture_output=True, text=True)
    p = r.stdout.strip()
    if not p:
        sys.exit("cannot resolve image: " + r.stderr.strip())
    return p


def off(blk):
    return BASE + blk * BLK


def ctrl_read(fd, blk):
    """Return (magic, seq, len, ack, torn).

    BIG-ENDIAN: the guest writes `struct chan_ctrl` in native order and the guest
    is SPARC. Getting this wrong would make every field garbage while the transfer
    itself worked -- a confusing failure worth naming.
    """
    os.lseek(fd, off(blk), os.SEEK_SET)
    b = os.read(fd, BLK)
    if len(b) < BLK:
        return (0, 0, 0, 0, True)
    magic, seq, ln, ack = struct.unpack_from(">IIII", b, 0)
    (seq_end,) = struct.unpack_from(">I", b, SEQ_END)
    return (magic, seq, ln, ack, seq != seq_end)


def ctrl_write(fd, blk, seq, ln, ack):
    b = bytearray(BLK)
    struct.pack_into(">IIII", b, 0, MAGIC, seq, ln, ack)
    struct.pack_into(">I", b, SEQ_END, seq)   # written last within the block
    os.pwrite(fd, bytes(b), off(blk))
    os.fsync(fd)


def cmd_init():
    fd = os.open(image(), os.O_RDWR)
    for blk in (C["CHAN_H2G_CTRL_BLK"], C["CHAN_G2H_CTRL_BLK"]):
        ctrl_write(fd, blk, 0, 0, 0)
    os.close(fd)
    print(f"initialised control blocks at image byte {BASE}")


def cmd_status():
    fd = os.open(image(), os.O_RDONLY)
    for name, blk in (("h2g", C["CHAN_H2G_CTRL_BLK"]),
                      ("g2h", C["CHAN_G2H_CTRL_BLK"])):
        magic, seq, ln, ack, torn = ctrl_read(fd, blk)
        print(f"  {name}: magic={magic:08x} seq={seq} len={ln} ack={ack}"
              f"{'  TORN' if torn else ''}")
    os.close(fd)


def cmd_tear(seq_head, seq_tail):
    """Write a DELIBERATELY torn h2g control block: seq at the head disagrees with
    the copy at the tail, exactly as a reader would observe mid-write.

    Exists because "the tear check does not false-positive" is not the same claim
    as "the tear check works". Without this the branch was never executed.
    """
    fd = os.open(image(), os.O_RDWR)
    b = bytearray(BLK)
    struct.pack_into(">IIII", b, 0, MAGIC, seq_head, DATA_BYTES // 2, 0)
    struct.pack_into(">I", b, SEQ_END, seq_tail)     # deliberately different
    os.pwrite(fd, bytes(b), off(C["CHAN_H2G_CTRL_BLK"]))
    os.fsync(fd)
    os.close(fd)
    print(f"wrote TORN h2g ctrl: head seq={seq_head} tail seq={seq_tail}")


def cmd_send(path, timeout=120):
    payload = pathlib.Path(path).read_bytes()
    if not payload or len(payload) > DATA_BYTES:
        sys.exit(f"payload must be 1..{DATA_BYTES} bytes, got {len(payload)}")
    # pad to a whole block: the guest's raw device has no partial-block support
    padded = payload + b"\0" * (-len(payload) % BLK)

    fd = os.open(image(), os.O_RDWR)
    _, cur_seq, _, _, _ = ctrl_read(fd, C["CHAN_H2G_CTRL_BLK"])
    seq = cur_seq + 1

    # DATA FIRST, then publish the control block. Reversing this lets the guest
    # read a frame that does not exist yet.
    os.pwrite(fd, padded, off(C["CHAN_H2G_DATA_BLK"]))
    os.fsync(fd)
    ctrl_write(fd, C["CHAN_H2G_CTRL_BLK"], seq, len(payload), 0)
    print(f"sent seq={seq} len={len(payload)} (padded {len(padded)})")

    deadline = time.time() + timeout
    while time.time() < deadline:
        magic, gseq, glen, gack, torn = ctrl_read(fd, C["CHAN_G2H_CTRL_BLK"])
        if magic == MAGIC and not torn and gseq == seq and glen > 0:
            os.lseek(fd, off(C["CHAN_G2H_DATA_BLK"]), os.SEEK_SET)
            got = os.read(fd, (glen + BLK - 1) // BLK * BLK)[:glen]
            ok = got == payload
            print(f"echo seq={gseq} len={glen} ack={gack} -> "
                  f"{'MATCH' if ok else 'MISMATCH'}")
            os.close(fd)
            sys.exit(0 if ok else 1)
        time.sleep(0.5)
    os.close(fd)
    sys.exit(f"timed out after {timeout}s waiting for echo of seq={seq}")


if __name__ == "__main__":
    a = sys.argv[1:] or ["status"]
    if a[0] == "init":     cmd_init()
    elif a[0] == "status": cmd_status()
    elif a[0] == "send":   cmd_send(a[1], int(a[2]) if len(a) > 2 else 120)
    elif a[0] == "tear":   cmd_tear(int(a[1]), int(a[2]))
    else:                  sys.exit(__doc__)
