#!/usr/bin/env python3

import select
import socket
import sys
import time


if len(sys.argv) != 4:
    raise SystemExit("usage: solaris9-b134-toolbox-inject.py SOCKET LOG TIMEOUT")

socket_path, log_path, timeout_text = sys.argv[1:]
deadline = time.monotonic() + int(timeout_text)
commands = [
    "/etc/init.d/volmgt stop",
    "umount /mnt/b134 2>/dev/null; true",
    "/usr/sbin/lofiadm -d /dev/lofi/1 2>/dev/null; true",
    "umount /mnt/bootdisk 2>/dev/null; true",
    "mkdir -p /mnt/bootdisk /mnt/b134",
    "mount -F ufs /dev/dsk/c0t5d0s0 /mnt/bootdisk",
    "INNER=`/usr/sbin/lofiadm -a /mnt/bootdisk/platform/sun4v/boot_archive`; test -n \"$INNER\"; echo INNER=$INNER",
    "mount -F ufs $INNER /mnt/b134",
    "mkdir -p /mnt/b134/usr/bin /mnt/b134/usr/sbin /mnt/b134/usr/lib/fs/ufs /mnt/b134/usr/lib/fs/hsfs",
    "cp -p /usr/bin/awk /mnt/b134/usr/bin/awk",
    "cp -p /usr/bin/dd /mnt/b134/usr/bin/dd",
    "cp -p /usr/bin/od /mnt/b134/usr/bin/od",
    "cp -p /usr/bin/head /mnt/b134/usr/bin/head",
    "cp -p /usr/bin/sum /mnt/b134/usr/bin/sum",
    "cp -p /usr/bin/cksum /mnt/b134/usr/bin/cksum",
    "sed '1s,/usr/bin/sh,/sbin/sh,' /usr/bin/hostname > /mnt/b134/usr/bin/hostname",
    "chmod 555 /mnt/b134/usr/bin/hostname; chown root /mnt/b134/usr/bin/hostname; chgrp bin /mnt/b134/usr/bin/hostname",
    "cp -p /usr/bin/uname /mnt/b134/bin/uname",
    "cp -p /usr/bin/gettext /mnt/b134/usr/bin/gettext",
    "cp -p /usr/sbin/fstyp /mnt/b134/usr/sbin/fstyp",
    "rm -f /mnt/b134/usr/lib/fs/ufs/fstyp; cp -p /usr/lib/fs/ufs/fstyp /mnt/b134/usr/lib/fs/ufs/fstyp",
    "rm -f /mnt/b134/usr/lib/fs/hsfs/fstyp; cp -p /usr/lib/fs/hsfs/fstyp /mnt/b134/usr/lib/fs/hsfs/fstyp",
    "cp -p /usr/lib/ld.so.1 /mnt/b134/usr/lib/ld.so.1",
    "cp -p /usr/lib/libc.so.1 /mnt/b134/usr/lib/libc.so.1",
    "cp -p /usr/lib/libdl.so.1 /mnt/b134/usr/lib/libdl.so.1",
    "cp -p /usr/lib/libm.so.1 /mnt/b134/usr/lib/libm.so.1",
    "echo '#!/sbin/sh' > /mnt/b134/usr/bin/hexdump",
    "echo 'test x\"$1\" = x-C && shift' >> /mnt/b134/usr/bin/hexdump",
    "echo 'exec /usr/bin/od -Ax -tx1c \"$@\"' >> /mnt/b134/usr/bin/hexdump",
    "chmod 555 /mnt/b134/usr/bin/hexdump",
    "echo 'boot toolbox v1; source Solaris 9 Generic May 2002' > /mnt/b134/etc/boot-toolbox.manifest",
    "echo 'awk dd od head sum cksum hostname-shebang-adapted uname gettext fstyp hexdump-wrapper' >> /mnt/b134/etc/boot-toolbox.manifest",
    "echo TOOLBOX_SOURCE_CKSUMS; cksum /usr/bin/awk /usr/bin/dd /usr/bin/od /usr/bin/head",
    "cksum /usr/bin/sum /usr/bin/cksum /usr/bin/hostname /usr/bin/uname /usr/bin/gettext",
    "cksum /usr/sbin/fstyp /usr/lib/fs/ufs/fstyp /usr/lib/fs/hsfs/fstyp",
    "cksum /usr/lib/ld.so.1 /usr/lib/libc.so.1 /usr/lib/libdl.so.1 /usr/lib/libm.so.1",
    "echo TOOLBOX_DEST_CKSUMS; cksum /mnt/b134/usr/bin/awk /mnt/b134/usr/bin/dd /mnt/b134/usr/bin/od /mnt/b134/usr/bin/head",
    "cksum /mnt/b134/usr/bin/sum /mnt/b134/usr/bin/cksum /mnt/b134/usr/bin/hostname /mnt/b134/bin/uname /mnt/b134/usr/bin/gettext",
    "cksum /mnt/b134/usr/sbin/fstyp /mnt/b134/usr/lib/fs/ufs/fstyp /mnt/b134/usr/lib/fs/hsfs/fstyp",
    "cksum /mnt/b134/usr/lib/ld.so.1 /mnt/b134/usr/lib/libc.so.1 /mnt/b134/usr/lib/libdl.so.1 /mnt/b134/usr/lib/libm.so.1",
    "echo alpha beta > /mnt/b134/tmp/toolbox-canary",
    "chroot /mnt/b134 /usr/bin/awk '{print $2}' /tmp/toolbox-canary",
    "chroot /mnt/b134 /usr/bin/head -1 /tmp/toolbox-canary",
    "chroot /mnt/b134 /usr/bin/od -An -tx1 /tmp/toolbox-canary",
    "chroot /mnt/b134 /usr/bin/sum /tmp/toolbox-canary",
    "chroot /mnt/b134 /usr/bin/cksum /tmp/toolbox-canary",
    "chroot /mnt/b134 /usr/bin/gettext TOOLBOX_GETTEXT; echo; true",
    "rm -f /mnt/b134/tmp/toolbox-canary",
    "ls -l /mnt/b134/usr/bin/awk /mnt/b134/usr/bin/dd /mnt/b134/usr/bin/od /mnt/b134/usr/bin/head",
    "ls -l /mnt/b134/usr/bin/hexdump /mnt/b134/usr/bin/sum /mnt/b134/usr/bin/cksum /mnt/b134/usr/bin/hostname",
    "ls -l /mnt/b134/usr/sbin/fstyp /mnt/b134/usr/bin/gettext /mnt/b134/usr/lib/ld.so.1 /mnt/b134/usr/lib/libm.so.1 /mnt/b134/bin/uname",
    "sync",
    "umount /mnt/b134",
    "fsck -F ufs -m $INNER",
    "/usr/sbin/lofiadm -d $INNER",
    "umount /mnt/bootdisk",
    "fsck -F ufs -m /dev/rdsk/c0t5d0s0",
    "echo SOLARIS9_B134_TOOLBOX_INJECT=PASS",
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
            raise SystemExit("SOLARIS9_B134_TOOLBOX_INJECT=FAIL reason=console-closed")
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
            output_lines = {line.strip() for line in normalized.splitlines()}
            expected = f"Y{command_index}:0".encode()
            if expected not in output_lines:
                raise SystemExit(
                    f"SOLARIS9_B134_TOOLBOX_INJECT=FAIL reason=step-{command_index}"
                )
            if command_index == len(commands):
                raise SystemExit(0)

        command = commands[command_index]
        print(f"\nSOLARIS9_B134_TOOLBOX_ACTION={command_index + 1}:{command}", flush=True)
        wire_command = f"{command}; r=$?; echo Y{command_index + 1}:$r"
        console.sendall(wire_command.encode("ascii") + b"\r")
        command_index += 1
        captured.clear()

raise SystemExit("SOLARIS9_B134_TOOLBOX_INJECT=FAIL reason=deadline")
