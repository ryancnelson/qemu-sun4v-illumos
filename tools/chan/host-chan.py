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

import os, re, stat, struct, sys, time, pathlib, subprocess

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
# Preserve the Solaris 10 image layout by default, but allow another guest image
# to place the same protocol in a different raw slice.  Tribblix uses c1d0s7 and
# therefore has a different absolute host-file offset even though chan.h's frame
# layout is unchanged.  int(..., 0) accepts decimal and 0x-prefixed values.
BASE = int(os.environ.get("NIAG_CHAN_HOST_BYTE", str(C["CHAN_HOST_BYTE"])), 0)
SEQ_END = C["CHAN_SEQ_END_OFF"]
DATA_BYTES = C["CHAN_DATA_BYTES"]


def image():
    """Resolve the image path.

    NIAGARA_IMG wins and is a PLAIN PATH, for hosts with no ZFS at all -- the
    portable target (Ubuntu on arm64) keeps the image on XFS, and the ZFS
    resolver below fails there with "no such ZFS filesystem", which is what
    stopped the channel bridges the first time this ran off biggie.
    """
    direct = os.environ.get("NIAGARA_IMG", "").strip()
    if direct:
        if not os.path.exists(direct):
            sys.exit(f"NIAGARA_IMG={direct} does not exist")
        p = direct
    else:
        r = subprocess.run(["bash", "-c",
                            f'source {PROJ}/tools/lib/image.sh; '
                            f'img_require "${{NIAGARA_IMAGES:-datapool/niagara/images}}"'],
                           capture_output=True, text=True)
        p = r.stdout.strip()
        if not p:
            sys.exit("cannot resolve image: " + r.stderr.strip()
                     + "\n(no ZFS here? set NIAGARA_IMG=/path/to/primary.img)")

    # Never let a stale layout constant silently extend a regular image. This
    # caught a Tribblix run that reused the larger primary-image offset and
    # wrote a sparse tail beyond EOF instead of the real channel slice.
    st = os.stat(p)
    required = BASE + NCHAN * STRIDE * BLK
    if stat.S_ISREG(st.st_mode) and (BASE < 0 or required > st.st_size):
        sys.exit(f"channel region [{BASE}, {required}) is outside {p} "
                 f"({st.st_size} bytes); set NIAG_CHAN_HOST_BYTE correctly")
    return p


STRIDE = C["CHAN_STRIDE_BLKS"]
NCHAN = C["CHAN_COUNT"]
DATA_BLKS = C["CHAN_DATA_BLKS"]


def off(blk):
    return BASE + blk * BLK


def cbase(ch):
    return ch * STRIDE


def h2g_ctrl(ch): return cbase(ch) + 0
def g2h_ctrl(ch): return cbase(ch) + 1
def h2g_data(ch): return cbase(ch) + 2
def g2h_data(ch): return cbase(ch) + 2 + DATA_BLKS


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


def cmd_init(ch=None):
    fd = os.open(image(), os.O_RDWR)
    chans = range(NCHAN) if ch is None else [ch]
    for c in chans:
        for blk in (h2g_ctrl(c), g2h_ctrl(c)):
            ctrl_write(fd, blk, 0, 0, 0)
    os.close(fd)
    print(f"initialised {len(list(chans))} channel(s) at image byte {BASE}")


def cmd_status(ch=None):
    fd = os.open(image(), os.O_RDONLY)
    for c in (range(NCHAN) if ch is None else [ch]):
        rows = []
        for name, blk in (("h2g", h2g_ctrl(c)), ("g2h", g2h_ctrl(c))):
            magic, seq, ln, ack, torn = ctrl_read(fd, blk)
            rows.append(f"{name} seq={seq} len={ln} ack={ack}"
                        f"{' TORN' if torn else ''}")
            live = magic == MAGIC
        print(f"  ch{c:<2d} {'init' if live else 'ZERO':4s}  " + " | ".join(rows))
    os.close(fd)


def cmd_bridge(ch=0, sockpath=None, idle_ms=20, idle_max_ms=60):
    """Mirror of guest-chand: bridge an AF_UNIX socket to the shared region.

        host$  sudo tools/chan/host-chan.py bridge
        host$  nc -U /run/niag0

    Same invariants as the guest side, for the same reasons:
      - one writer per direction, so no locking
      - one frame in flight; reuse the data area only once the peer's ack_seq
        catches up
      - an ack MUST re-publish this side's seq AND len unchanged, or it destroys
        an outbound frame the peer has not consumed (the ack and the frame share
        one control block)
    """
    import socket

    if sockpath is None:
        sockpath = f"/run/niag{ch}"
    img = os.open(image(), os.O_RDWR)
    _, my_seq, my_len, _, _ = ctrl_read(img, h2g_ctrl(ch))
    _, seen_seq, _, _, _ = ctrl_read(img, g2h_ctrl(ch))
    # ACK the adopted seq immediately -- see the long note in guest-chand.c. Adopting
    # without acking deadlocks whenever a frame was already in flight, because the
    # peer's send gate waits on an ack we would never publish.
    ctrl_write(img, h2g_ctrl(ch), my_seq, my_len, seen_seq)

    try: os.unlink(sockpath)
    except FileNotFoundError: pass
    pathlib.Path(sockpath).parent.mkdir(parents=True, exist_ok=True)
    lsock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    lsock.bind(sockpath)
    os.chmod(sockpath, 0o666)
    lsock.listen(1)
    print(f"host bridge: {sockpath}  image byte {BASE}  "
          f"my_seq={my_seq} peer_seq={seen_seq}", flush=True)

    try:
      while True:
        conn, _ = lsock.accept()
        conn.setblocking(False)
        print(f"host bridge: ch{ch} client connected", flush=True)

        pending = b""      # socket -> region
        sendbuf = b""      # region -> socket, drained incrementally (see below)
        eof = False
        # Idle backoff, same reasoning as the guest: 16 flat-rate pollers would
        # spend a fifth of the measured disk bandwidth on empty status reads.
        wait = idle_ms
        while True:
            did = False

            # outbound: socket -> h2g
            if not pending and not eof:
                try:
                    b = conn.recv(DATA_BYTES)
                    if b: pending = b
                    else: eof = True
                except BlockingIOError:
                    pass
                except OSError:
                    eof = True
            if pending:
                _, pseq, _, pack, torn = ctrl_read(img, g2h_ctrl(ch))
                if not torn and pack >= my_seq:
                    padded = pending + b"\0" * (-len(pending) % BLK)
                    os.pwrite(img, padded, off(h2g_data(ch)))
                    my_seq += 1
                    my_len = len(pending)
                    ctrl_write(img, h2g_ctrl(ch), my_seq, my_len, seen_seq)
                    if os.environ.get("CHAN_TRACE"):
                        print(f"  OUT seq={my_seq} len={my_len}", flush=True)
                    pending = b""
                    did = True

            # inbound: g2h -> socket
            magic, gseq, glen, gack, torn = ctrl_read(img, g2h_ctrl(ch))
            if (not sendbuf and magic == MAGIC and not torn
                    and gseq != seen_seq and 0 < glen <= DATA_BYTES):
                want = gseq
                os.lseek(img, off(g2h_data(ch)), os.SEEK_SET)
                data = os.read(img, (glen + BLK - 1) // BLK * BLK)[:glen]
                _, again, _, _, torn2 = ctrl_read(img, g2h_ctrl(ch))
                if not torn2 and again == want:
                    # Stage, do not sendall(): a blocking send here starves the
                    # outbound direction and deadlocks any transfer larger than
                    # the socket buffers. Same bug as the guest's old write loop.
                    sendbuf = data
                    seen_seq = want
                    if os.environ.get("CHAN_TRACE"):
                        print(f"  IN  seq={want} len={glen}", flush=True)
                    # re-publish seq AND len; see docstring
                    ctrl_write(img, h2g_ctrl(ch), my_seq, my_len, seen_seq)
                    did = True

            if sendbuf:
                try:
                    n = conn.send(sendbuf)
                    if n > 0:
                        sendbuf = sendbuf[n:]
                        did = True
                except BlockingIOError:
                    pass
                except OSError:
                    eof = True

            if eof and not pending and not sendbuf:
                break
            if did:
                wait = idle_ms
            else:
                time.sleep(wait / 1000.0)
                wait = min(wait * 1.5, idle_max_ms)

        print(f"host bridge: ch{ch} client gone", flush=True)
        conn.close()
    finally:
        lsock.close(); os.close(img)
        try: os.unlink(sockpath)
        except FileNotFoundError: pass
        print("host bridge: closed", flush=True)


def cmd_tear(seq_head, seq_tail, ch=0):
    """Write a DELIBERATELY torn h2g control block: seq at the head disagrees with
    the copy at the tail, exactly as a reader would observe mid-write.

    Exists because "the tear check does not false-positive" is not the same claim
    as "the tear check works". Without this the branch was never executed.
    """
    fd = os.open(image(), os.O_RDWR)
    b = bytearray(BLK)
    struct.pack_into(">IIII", b, 0, MAGIC, seq_head, DATA_BYTES // 2, 0)
    struct.pack_into(">I", b, SEQ_END, seq_tail)     # deliberately different
    os.pwrite(fd, bytes(b), off(h2g_ctrl(ch)))
    os.fsync(fd)
    os.close(fd)
    print(f"wrote TORN h2g ctrl: head seq={seq_head} tail seq={seq_tail}")


def cmd_send(path, timeout=120, ch=0):
    payload = pathlib.Path(path).read_bytes()
    if not payload or len(payload) > DATA_BYTES:
        sys.exit(f"payload must be 1..{DATA_BYTES} bytes, got {len(payload)}")
    # pad to a whole block: the guest's raw device has no partial-block support
    padded = payload + b"\0" * (-len(payload) % BLK)

    fd = os.open(image(), os.O_RDWR)
    _, cur_seq, _, _, _ = ctrl_read(fd, h2g_ctrl(ch))
    seq = cur_seq + 1

    # DATA FIRST, then publish the control block. Reversing this lets the guest
    # read a frame that does not exist yet.
    os.pwrite(fd, padded, off(h2g_data(ch)))
    os.fsync(fd)
    ctrl_write(fd, h2g_ctrl(ch), seq, len(payload), 0)
    print(f"sent seq={seq} len={len(payload)} (padded {len(padded)})")

    deadline = time.time() + timeout
    while time.time() < deadline:
        magic, gseq, glen, gack, torn = ctrl_read(fd, g2h_ctrl(ch))
        if magic == MAGIC and not torn and gseq == seq and glen > 0:
            os.lseek(fd, off(g2h_data(ch)), os.SEEK_SET)
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
    if a[0] == "init":     cmd_init(int(a[1]) if len(a) > 1 else None)
    elif a[0] == "status": cmd_status(int(a[1]) if len(a) > 1 else None)
    elif a[0] == "send":   cmd_send(a[1], int(a[2]) if len(a) > 2 else 120)
    elif a[0] == "tear":   cmd_tear(int(a[1]), int(a[2]))
    elif a[0] == "bridge": cmd_bridge(int(a[1]) if len(a) > 1 else 0,
                                      a[2] if len(a) > 2 else None)
    else:                  sys.exit(__doc__)
