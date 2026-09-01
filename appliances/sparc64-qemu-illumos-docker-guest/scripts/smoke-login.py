#!/usr/bin/env python3

import os
import selectors
import socket
import sys
import time


socket_path = os.environ.get("CONSOLE_SOCKET", "state/console.sock")
timeout = int(os.environ.get("LOGIN_TIMEOUT_SECONDS", "1200"))
evidence_path = os.environ.get("EVIDENCE_PATH", "state/smoke-console.log")
boot_command = (
    os.environ.get(
        "OPENBOOT_COMMAND", "boot /virtual-devices@100/disk@4:a -k -v"
    ).encode("utf-8")
    + b"\r"
)
deadline = time.monotonic() + timeout
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)

while True:
    try:
        sock.connect(socket_path)
        break
    except (FileNotFoundError, ConnectionRefusedError):
        if time.monotonic() >= deadline:
            raise SystemExit("APPLIANCE_LOGIN_SMOKE=FAIL reason=console unavailable")
        time.sleep(1)

sock.setblocking(False)
selector = selectors.DefaultSelector()
selector.register(sock, selectors.EVENT_READ)
# Repaint an OpenBoot prompt that may have appeared during the short interval
# between QEMU creating the socket and this client connecting.
sock.sendall(b"\r")
transcript = bytearray()
boot_sent = False

evidence_dir = os.path.dirname(evidence_path)
if evidence_dir:
    os.makedirs(evidence_dir, exist_ok=True)

with open(evidence_path, "wb", buffering=0) as evidence:
    while time.monotonic() < deadline:
        for key, _ in selector.select(timeout=1):
            chunk = key.fileobj.recv(65536)
            if not chunk:
                raise SystemExit("APPLIANCE_LOGIN_SMOKE=FAIL reason=console disconnected")
            evidence.write(chunk)
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
            transcript.extend(chunk)
            if len(transcript) > 262144:
                del transcript[:-131072]

        visible = bytes(transcript).replace(b"\x08", b"")
        if b" console login: " in visible or visible.rstrip().endswith(b"console login:"):
            print("\nAPPLIANCE_LOGIN_SMOKE=PASS")
            raise SystemExit(0)

        if not boot_sent and (visible.endswith(b"ok ") or b"\nok " in visible[-4096:]):
            sock.sendall(boot_command)
            boot_sent = True
            print("\nAPPLIANCE_OPENBOOT_COMMAND_SENT=PASS", flush=True)

raise SystemExit("APPLIANCE_LOGIN_SMOKE=FAIL reason=login timeout")
