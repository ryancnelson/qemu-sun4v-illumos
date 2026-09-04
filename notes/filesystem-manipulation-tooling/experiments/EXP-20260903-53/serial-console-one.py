#!/usr/bin/env python3

import select
import socket
import sys
import time


if len(sys.argv) != 6:
    raise SystemExit("usage: serial-console-one.py SOCKET LOG TIMEOUT MARKER COMMAND")

socket_path, log_path, timeout_text, marker, command = sys.argv[1:]
deadline = time.monotonic() + int(timeout_text)
console = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
console.connect(socket_path)
console.setblocking(False)
captured = bytearray()
sent = False
console.sendall(b"\x03\r")

with open(log_path, "ab") as transcript:
    while time.monotonic() < deadline:
        readable, _, _ = select.select([console], [], [], 1)
        if not readable:
            continue
        chunk = console.recv(4096)
        if not chunk:
            raise SystemExit("SERIAL_ONE=FAIL reason=console-closed")
        transcript.write(chunk)
        transcript.flush()
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
        captured.extend(chunk)
        normalized = bytes(captured).replace(b"\r", b"")
        if not normalized.endswith(b"# "):
            continue
        if sent:
            expected = f"{marker}:0".encode()
            if expected not in {line.strip() for line in normalized.splitlines()}:
                raise SystemExit(f"SERIAL_ONE=FAIL marker={marker}")
            raise SystemExit(0)
        console.sendall(f"{command}; r=$?; echo {marker}:$r\r".encode("ascii"))
        captured.clear()
        sent = True

raise SystemExit("SERIAL_ONE=FAIL reason=deadline")
