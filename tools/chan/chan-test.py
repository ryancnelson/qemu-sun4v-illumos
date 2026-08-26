#!/usr/bin/env python3
"""Round-trip a channel against a guest echo client.

    sudo python3 tools/chan/chan-test.py [ch] [size]

Requires an echo client connected on the guest side:
    guest#  /opt/niag/bin/guest-echocli /tmp/niag<ch> &

Socket path defaults to /run/niag<ch> but is overridable via NIAG_CHAN_SOCK
-- e.g. a scoped rehearsal run dir's socket -- so a caller never has to
create a global /run/niag<ch> symlink just to point this at a non-default
bridge socket.

Uses a CONCURRENT reader: a blocking sendall() of more than the socket buffer
would stall before it ever read, which is a property of this test client and not
of the channel.
"""
import os, socket, sys, threading, time

ch = int(sys.argv[1]) if len(sys.argv) > 1 else 0
sz = int(sys.argv[2]) if len(sys.argv) > 2 else 262144
path = os.environ.get("NIAG_CHAN_SOCK") or f"/run/niag{ch}"

payload = os.urandom(sz)
got = bytearray()
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(45)
try:
    s.connect(path)
except OSError as e:
    sys.exit(f"cannot connect {path}: {e}  (is the bridge up?)")

def reader():
    while len(got) < sz:
        try:
            b = s.recv(65536)
        except Exception:
            return
        if not b:
            return
        got.extend(b)

t = threading.Thread(target=reader, daemon=True)
t.start()
t0 = time.time()
s.sendall(payload)
t.join(timeout=45)
dt = time.time() - t0
s.close()

ok = len(got) == sz and bytes(got) == payload
print(f"ch{ch}: {sz} B  {dt:.2f}s  {sz*2/dt/1024:.0f} KB/s round-trip  "
      f"{'MATCH' if ok else f'FAIL (got {len(got)})'}")
sys.exit(0 if ok else 1)
