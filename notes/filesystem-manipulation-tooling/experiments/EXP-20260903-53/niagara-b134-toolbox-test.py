#!/usr/bin/env python3

import select
import socket
import sys
import time


if len(sys.argv) != 4:
    raise SystemExit("usage: niagara-b134-toolbox-test.py SOCKET LOG TIMEOUT")

socket_path, log_path, timeout_text = sys.argv[1:]
deadline = time.monotonic() + int(timeout_text)
commands = [
    "echo RUN010_TOOLBOX_START",
    "cat /etc/boot-toolbox.manifest",
    "/usr/bin/hostname",
    "/bin/uname -a",
    "echo alpha beta > /tmp/toolbox-canary",
    "/usr/bin/awk '{print $2}' /tmp/toolbox-canary",
    "/usr/bin/head -1 /tmp/toolbox-canary",
    "/usr/bin/od -An -tx1 /tmp/toolbox-canary",
    "/usr/bin/hexdump -C /tmp/toolbox-canary",
    "/usr/bin/sum /tmp/toolbox-canary",
    "/usr/bin/cksum /tmp/toolbox-canary",
    "/usr/bin/dd if=/tmp/toolbox-canary of=/tmp/toolbox-copy bs=1 count=11",
    "/usr/bin/cksum /tmp/toolbox-copy",
    "/usr/sbin/fstyp /dev/null 2>&1; echo FSTYP_RC=$?; true",
    "ls -ld /usr/lib/fs /usr/lib/fs/ufs /usr/lib/fs/hsfs",
    "ls -l /usr/lib/fs/ufs/fstyp /usr/lib/fs/hsfs/fstyp",
    "echo DETECTORS=/usr/lib/fs/*/fstyp",
    "/usr/lib/fs/ufs/fstyp /dev/null 2>&1; echo UFS_FSTYP_RC=$?; true",
    "test -x /usr/bin/gettext; echo GETTEXT_PRESENT=$?; true",
    "/usr/sbin/devfsadm -v -i hsimd",
    "ls -l /dev/dsk/c2d0s0 /dev/dsk/c2d6s0 /dev/dsk/c2d7s0",
    "rm -f /tmp/toolbox-canary /tmp/toolbox-copy",
    "echo RUN010_TOOLBOX_PASS",
]

console = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
console.connect(socket_path)
console.setblocking(False)
captured = bytearray()
command_index = 0
logged_in = False
password_sent = False
console.sendall(b"\r")

with open(log_path, "wb") as transcript:
    while time.monotonic() < deadline:
        readable, _, _ = select.select([console], [], [], 1)
        if not readable:
            continue
        chunk = console.recv(4096)
        if not chunk:
            raise SystemExit("RUN010_TOOLBOX=FAIL reason=console-closed")
        transcript.write(chunk)
        transcript.flush()
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
        captured.extend(chunk)
        normalized = bytes(captured).replace(b"\r", b"")

        if b"Enter user name for system maintenance" in normalized and not logged_in:
            console.sendall(b"root\r")
            logged_in = True
            captured.clear()
            continue

        if b"Enter root password" in normalized and not password_sent:
            console.sendall(b"\r")
            password_sent = True
            captured.clear()
            continue

        if not normalized.endswith(b"# "):
            continue

        if command_index:
            expected = f"T{command_index}:0".encode()
            if expected not in {line.strip() for line in normalized.splitlines()}:
                raise SystemExit(f"RUN010_TOOLBOX=FAIL reason=step-{command_index}")
            if command_index == len(commands):
                raise SystemExit(0)

        command = commands[command_index]
        print(f"\nRUN010_TOOLBOX_ACTION={command_index + 1}:{command}", flush=True)
        console.sendall(
            f"{command}; r=$?; echo T{command_index + 1}:$r\r".encode("ascii")
        )
        command_index += 1
        captured.clear()

raise SystemExit("RUN010_TOOLBOX=FAIL reason=deadline")
