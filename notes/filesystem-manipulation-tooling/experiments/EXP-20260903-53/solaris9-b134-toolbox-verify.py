#!/usr/bin/env python3

import select
import socket
import sys
import time


if len(sys.argv) != 4:
    raise SystemExit("usage: solaris9-b134-toolbox-verify.py SOCKET LOG TIMEOUT")

socket_path, log_path, timeout_text = sys.argv[1:]
deadline = time.monotonic() + int(timeout_text)
commands = [
    "/etc/init.d/volmgt stop",
    "umount /mnt/b134 2>/dev/null; true",
    "/usr/sbin/lofiadm -d /dev/lofi/1 2>/dev/null; true",
    "umount /mnt/bootdisk 2>/dev/null; true",
    "mount -F ufs -o ro /dev/dsk/c0t5d0s0 /mnt/bootdisk",
    "INNER=`/usr/sbin/lofiadm -a /mnt/bootdisk/platform/sun4v/boot_archive`; test -n \"$INNER\"; echo INNER=$INNER",
    "mount -F ufs -o ro $INNER /mnt/b134",
    "cmp /usr/bin/awk /mnt/b134/usr/bin/awk",
    "cmp /usr/bin/dd /mnt/b134/usr/bin/dd",
    "cmp /usr/bin/od /mnt/b134/usr/bin/od",
    "cmp /usr/bin/head /mnt/b134/usr/bin/head",
    "cmp /usr/bin/sum /mnt/b134/usr/bin/sum",
    "cmp /usr/bin/cksum /mnt/b134/usr/bin/cksum",
    "head -1 /mnt/b134/usr/bin/hostname",
    "cmp /usr/bin/uname /mnt/b134/bin/uname",
    "cmp /usr/bin/gettext /mnt/b134/usr/bin/gettext",
    "cmp /usr/sbin/fstyp /mnt/b134/usr/sbin/fstyp",
    "cmp /usr/lib/fs/ufs/fstyp /mnt/b134/usr/lib/fs/ufs/fstyp",
    "cmp /usr/lib/fs/hsfs/fstyp /mnt/b134/usr/lib/fs/hsfs/fstyp",
    "cmp /usr/lib/ld.so.1 /mnt/b134/usr/lib/ld.so.1",
    "cmp /usr/lib/libc.so.1 /mnt/b134/usr/lib/libc.so.1",
    "cmp /usr/lib/libdl.so.1 /mnt/b134/usr/lib/libdl.so.1",
    "cmp /usr/lib/libm.so.1 /mnt/b134/usr/lib/libm.so.1",
    "cat /mnt/b134/etc/boot-toolbox.manifest",
    "cksum /mnt/b134/usr/bin/hostname /mnt/b134/usr/bin/hexdump /mnt/b134/etc/boot-toolbox.manifest",
    "ls -l /mnt/b134/usr/bin/awk /mnt/b134/usr/bin/dd /mnt/b134/usr/bin/od /mnt/b134/usr/bin/head",
    "ls -l /mnt/b134/usr/bin/hexdump /mnt/b134/usr/bin/sum /mnt/b134/usr/bin/cksum /mnt/b134/usr/bin/hostname",
    "ls -l /mnt/b134/bin/uname /mnt/b134/usr/sbin/fstyp /mnt/b134/usr/lib/ld.so.1",
    "umount /mnt/b134",
    "/usr/sbin/lofiadm -d $INNER",
    "umount /mnt/bootdisk",
    "echo SOLARIS9_B134_TOOLBOX_REOPEN=PASS",
]

console = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
console.connect(socket_path)
console.setblocking(False)
captured = bytearray()
command_index = 0
logged_in = False
boot_sent = False
console.sendall(b"\x03\r")

with open(log_path, "wb") as transcript:
    while time.monotonic() < deadline:
        readable, _, _ = select.select([console], [], [], 1)
        if not readable:
            continue
        chunk = console.recv(4096)
        if not chunk:
            raise SystemExit("SOLARIS9_B134_TOOLBOX_REOPEN=FAIL reason=console-closed")
        transcript.write(chunk)
        transcript.flush()
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
        captured.extend(chunk)
        normalized = bytes(captured).replace(b"\r", b"")

        if normalized.endswith(b"ok ") and not boot_sent:
            console.sendall(b"boot disk0\r")
            boot_sent = True
            captured.clear()
            continue

        if b"login:" in normalized and not logged_in:
            console.sendall(b"root\r")
            logged_in = True
            captured.clear()
            continue

        if not normalized.endswith(b"\n# "):
            continue

        if command_index:
            expected = f"V{command_index}:0".encode()
            if expected not in {line.strip() for line in normalized.splitlines()}:
                raise SystemExit(
                    f"SOLARIS9_B134_TOOLBOX_REOPEN=FAIL reason=step-{command_index}"
                )
            if command_index == len(commands):
                raise SystemExit(0)

        command = commands[command_index]
        print(f"\nSOLARIS9_B134_TOOLBOX_VERIFY_ACTION={command_index + 1}:{command}", flush=True)
        console.sendall(
            f"{command}; r=$?; echo V{command_index + 1}:$r\r".encode("ascii")
        )
        command_index += 1
        captured.clear()

raise SystemExit("SOLARIS9_B134_TOOLBOX_REOPEN=FAIL reason=deadline")
