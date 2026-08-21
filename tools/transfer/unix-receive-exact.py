#!/usr/bin/env python3
"""Receive an exact byte count from an AF_UNIX stream into a file."""

import os
import socket
import sys


if len(sys.argv) != 4:
    raise SystemExit(f"usage: {sys.argv[0]} SOCKET BYTE_COUNT OUTPUT")

socket_path, byte_count, output_path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
if byte_count < 0:
    raise SystemExit("BYTE_COUNT must be non-negative")

received = 0
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as stream:
    stream.connect(socket_path)
    with open(output_path, "wb") as output:
        while received < byte_count:
            chunk = stream.recv(min(1024 * 1024, byte_count - received))
            if not chunk:
                raise SystemExit(
                    f"short stream: received {received} of {byte_count} bytes"
                )
            output.write(chunk)
            received += len(chunk)
        output.flush()
        os.fsync(output.fileno())

print(f"{received} bytes received")
