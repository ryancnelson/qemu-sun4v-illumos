#!/usr/bin/env python3

import argparse
import os
import re
import selectors
import socket
import sys
import time


parser = argparse.ArgumentParser()
parser.add_argument("--socket", default="state/console.sock")
parser.add_argument("--command", required=True)
parser.add_argument("--timeout", type=int, default=300)
parser.add_argument("--transcript", default="state/guest-command.log")
args = parser.parse_args()

deadline = time.monotonic() + args.timeout
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect(args.socket)
sock.setblocking(False)
selector = selectors.DefaultSelector()
selector.register(sock, selectors.EVENT_READ)
buf = bytearray()
state = "discover"
marker = f"__GUEST_COMMAND_DONE_{os.getpid()}__"


def send(text: str) -> None:
    sock.sendall(text.encode("utf-8") + b"\r")


send("")
with open(args.transcript, "ab", buffering=0) as evidence:
    while time.monotonic() < deadline:
        for key, _ in selector.select(timeout=1):
            chunk = key.fileobj.recv(65536)
            if not chunk:
                raise SystemExit("GUEST_COMMAND=FAIL reason=console disconnected")
            evidence.write(chunk)
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
            buf.extend(chunk)
            if len(buf) > 262144:
                del buf[:-131072]

        visible = bytes(buf).replace(b"\x08", b"")
        tail = visible[-8192:]

        if state == "discover":
            if b"console login:" in tail:
                send("root")
                state = "password"
                buf.clear()
            elif re.search(rb"root@[^\r\n]*# $", tail):
                state = "command"
            elif re.search(rb"jack@[^\r\n]*\$ $", tail):
                send("su -")
                state = "su-password"
                buf.clear()

        elif state == "password" and b"Password:" in tail:
            send("root")
            state = "root-prompt"
            buf.clear()

        elif state == "su-password" and b"Password:" in tail:
            send("root")
            state = "root-prompt"
            buf.clear()

        if state == "root-prompt" and re.search(rb"(?:root@[^\r\n]*#|#) $", tail):
            state = "command"

        if state == "command":
            send(f"{args.command}; _rc=$?; echo {marker}$_rc")
            state = "result"
            buf.clear()

        if state == "result":
            match = re.search(re.escape(marker.encode()) + rb"([0-9]+)", tail)
            if match:
                rc = int(match.group(1))
                print(f"\nGUEST_COMMAND={'PASS' if rc == 0 else 'FAIL'} rc={rc}")
                raise SystemExit(rc)

raise SystemExit(f"GUEST_COMMAND=FAIL reason=timeout state={state}")
