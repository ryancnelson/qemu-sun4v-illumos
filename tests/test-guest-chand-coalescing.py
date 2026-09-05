#!/usr/bin/env python3
"""Exercise the real daemon against a disposable file and Unix socket."""
import importlib.util
import os
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("host_chan", ROOT / "tools/chan/host-chan.py")
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)
C = host.C
B = C["CHAN_BLK"]


def wait_for(fn):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        value = fn()
        if value:
            return value
        time.sleep(0.005)
    raise AssertionError("timed out waiting for daemon")


def run(binary, directory):
    disk = directory / "carrier"
    path = str(directory / "socket")
    with disk.open("w+b", buffering=0) as f:
        f.truncate(C["CHAN_REGION_BYTES"])

        def put(seq, ack, payload=b""):
            if payload:
                os.pwrite(f.fileno(), payload, 2 * B)
            block = bytearray(B)
            struct.pack_into("=4I", block, 0, C["CHAN_MAGIC"], seq, len(payload), ack)
            struct.pack_into("=I", block, C["CHAN_SEQ_END_OFF"], seq)
            os.pwrite(f.fileno(), block, 0)

        def control():
            block = os.pread(f.fileno(), B, B)
            value = struct.unpack_from("=4I", block)
            return value if value[1] == struct.unpack_from("=I", block, C["CHAN_SEQ_END_OFF"])[0] else (0, 0, 0, 0)

        # An unacknowledged outgoing frame keeps the publication gate closed.
        block = bytearray(B)
        struct.pack_into("=4I", block, 0, C["CHAN_MAGIC"], 1, 0, 0)
        struct.pack_into("=I", block, C["CHAN_SEQ_END_OFF"], 1)
        os.pwrite(f.fileno(), block, B)
        put(0, 0)
        env = dict(os.environ, NIAG_CHAN_DEV=str(disk), NIAG_CHAN_GUEST_BLK="0")
        proc = subprocess.Popen([str(binary), "0", path], env=env, stdout=subprocess.DEVNULL)
        try:
            wait_for(lambda: os.path.exists(path))
            with socket.socket(socket.AF_UNIX) as sock:
                sock.settimeout(5)
                sock.connect(path)
                first = b"a" * 6144
                second = b"b" * 6144
                sock.sendall(first)
                # Inbound traffic proves the daemon has serviced a loop while
                # the outbound acknowledgement is withheld.
                put(1, 0, b"ping")
                wait_for(lambda: control()[3] == 1)
                assert sock.recv(4) == b"ping"
                sock.sendall(second)
                put(2, 0, b"pong")
                wait_for(lambda: control()[3] == 2)
                assert sock.recv(4) == b"pong"
                assert control()[1] == 1, "published before peer acknowledgement"
                put(2, 1, b"pong")
                frame = wait_for(lambda: control() if control()[1] == 2 else None)
                expected = first + second
                assert frame[2] == len(expected), ("did not coalesce queued chunks", frame[2], len(expected))
                offset = (2 + C["CHAN_DATA_BLKS"]) * B
                assert os.pread(f.fileno(), frame[2], offset) == expected
                # A short final fragment must survive EOF and flush once acked.
                sock.sendall(b"tail")
                sock.shutdown(socket.SHUT_WR)
                put(2, 2, b"pong")
                frame = wait_for(lambda: control() if control()[1] == 3 else None)
                assert frame[2] == 4
                assert os.pread(f.fileno(), 4, offset) == b"tail"
            put(2, 3, b"pong")
            # More than two frames exercises the capacity bound, backpressure,
            # reconnection and exact byte ordering across frame boundaries.
            with socket.socket(socket.AF_UNIX) as sock:
                sock.settimeout(5)
                sock.connect(path)
                expected = os.urandom(2 * C["CHAN_DATA_BYTES"] + 17)
                errors = []

                def send():
                    try:
                        sock.sendall(expected)
                        sock.shutdown(socket.SHUT_WR)
                    except Exception as exc:
                        errors.append(exc)

                sender = threading.Thread(target=send)
                sender.start()
                received = bytearray()
                seq = 3
                try:
                    while len(received) < len(expected):
                        frame = wait_for(lambda: control() if control()[1] > seq else None)
                        assert frame[1] == seq + 1
                        assert 0 < frame[2] <= C["CHAN_DATA_BYTES"]
                        received.extend(os.pread(f.fileno(), frame[2], offset))
                        seq = frame[1]
                        put(2, seq, b"pong")
                    assert received == expected
                finally:
                    sender.join(timeout=6)
                assert not sender.is_alive()
                assert not errors, errors
        finally:
            proc.terminate()
            proc.wait(timeout=5)


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="chand-", dir="/tmp") as tmp:
        directory = Path(tmp)
        binary = directory / "guest-chand"
        subprocess.run([os.environ.get("CC", "cc"), "-O2", "-Wall", "-Wextra",
                        str(ROOT / "tools/chan/guest-chand.c"), "-o", str(binary)], check=True)
        run(binary, directory)
    print("PASS: coalescing, acknowledgement gate, inbound progress, EOF flush, multi-frame transfer")
