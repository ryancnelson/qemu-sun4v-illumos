#!/usr/bin/env python3

import select
import socket
import sys
import time


if len(sys.argv) != 4:
    raise SystemExit("usage: solaris9-b134-toolbox-inventory.py SOCKET LOG TIMEOUT")

socket_path, log_path, timeout_text = sys.argv[1:]
deadline = time.monotonic() + int(timeout_text)
commands = [
    "/etc/init.d/volmgt stop",
    "echo TOOL_SOURCE_INVENTORY",
    "for d in /usr/bin /usr/sbin /usr/xpg4/bin /usr/ucb /sbin; do test -x $d/awk && ls -l $d/awk; done",
    "for d in /usr/bin /usr/sbin /usr/xpg4/bin /usr/ucb /sbin; do test -x $d/dd && ls -l $d/dd; done",
    "for d in /usr/bin /usr/sbin /usr/xpg4/bin /usr/ucb /sbin; do test -x $d/od && ls -l $d/od; done",
    "for d in /usr/bin /usr/sbin /usr/xpg4/bin /usr/ucb /sbin; do test -x $d/head && ls -l $d/head; done",
    "for d in /usr/bin /usr/sbin /usr/xpg4/bin /usr/ucb /sbin; do test -x $d/hexdump && ls -l $d/hexdump; done",
    "for d in /usr/bin /usr/sbin /usr/xpg4/bin /usr/ucb /sbin; do test -x $d/sum && ls -l $d/sum; done",
    "for d in /usr/bin /usr/sbin /usr/xpg4/bin /usr/ucb /sbin; do test -x $d/cksum && ls -l $d/cksum; done",
    "for d in /usr/bin /usr/sbin /usr/xpg4/bin /usr/ucb /sbin; do test -x $d/hostname && ls -l $d/hostname; done",
    "for d in /usr/bin /usr/sbin /usr/xpg4/bin /usr/ucb /sbin; do test -x $d/fstyp && ls -l $d/fstyp; done",
    "echo TOOL_FILE_TYPES",
    "for p in /usr/bin/awk /usr/bin/dd /usr/bin/od /usr/bin/head; do test -f $p && file $p; done",
    "for p in /usr/bin/hexdump /usr/bin/sum /usr/bin/cksum; do test -f $p && file $p; done",
    "for p in /usr/bin/hostname /usr/sbin/fstyp; do test -f $p && file $p; done",
    "echo TOOL_RUNTIME_DEPS",
    "for p in /usr/bin/awk /usr/bin/dd /usr/bin/od /usr/bin/head; do test -f $p && echo ===$p=== && ldd $p; done",
    "for p in /usr/bin/hexdump /usr/bin/sum /usr/bin/cksum; do test -f $p && echo ===$p=== && ldd $p; done",
    "for p in /usr/bin/hostname /usr/sbin/fstyp; do test -f $p && echo ===$p=== && ldd $p; done",
    "mkdir -p /mnt/bootdisk /mnt/b134",
    "mount -F ufs -o ro /dev/dsk/c0t5d0s0 /mnt/bootdisk",
    "INNER=`/usr/sbin/lofiadm -a /mnt/bootdisk/platform/sun4v/boot_archive`; test -n \"$INNER\"; echo B134_INNER=$INNER",
    "mount -F ufs -o ro $INNER /mnt/b134",
    "echo B134_EXISTING_TOOLS",
    "for p in usr/bin/awk usr/bin/dd usr/bin/od usr/bin/head; do test -f /mnt/b134/$p && ls -l /mnt/b134/$p || echo MISSING:/$p; done",
    "for p in usr/bin/hexdump usr/bin/sum usr/bin/cksum; do test -f /mnt/b134/$p && ls -l /mnt/b134/$p || echo MISSING:/$p; done",
    "for p in usr/bin/hostname usr/sbin/fstyp; do test -f /mnt/b134/$p && ls -l /mnt/b134/$p || echo MISSING:/$p; done",
    "echo B134_RUNTIME_LIBS",
    "for p in usr/lib/libc.so.1 usr/lib/libdl.so.1 usr/lib/libm.so.2; do test -f /mnt/b134/$p && ls -l /mnt/b134/$p || echo MISSING:/$p; done",
    "for p in usr/lib/libcmdutils.so.1 usr/lib/ld.so.1 platform/sun4v/lib/ld.so.1; do test -f /mnt/b134/$p && ls -l /mnt/b134/$p || echo MISSING:/$p; done",
    "echo B134_LIB_LAYOUT",
    "ls -l /mnt/b134/lib/libc.so.1 /mnt/b134/lib/libdl.so.1 /mnt/b134/lib/libm.so.2",
    "file /mnt/b134/lib/libc.so.1 /mnt/b134/lib/libdl.so.1 /mnt/b134/lib/libm.so.2",
    "ls -l /mnt/b134/lib/ld.so.1 /mnt/b134/lib/sparcv9/ld.so.1",
    "echo SOURCE_SCRIPT_HELPERS",
    "head -40 /usr/bin/hostname",
    "head -80 /usr/sbin/fstyp",
    "ls -l /usr/sbin/sysinfo; file /usr/sbin/sysinfo; ldd /usr/sbin/sysinfo",
    "ls -l /usr/lib/fs/ufs/fstyp /usr/lib/fs/hsfs/fstyp",
    "file /usr/lib/fs/ufs/fstyp /usr/lib/fs/hsfs/fstyp",
    "ldd /usr/lib/fs/ufs/fstyp; ldd /usr/lib/fs/hsfs/fstyp",
    "umount /mnt/b134",
    "/usr/sbin/lofiadm -d $INNER",
    "umount /mnt/bootdisk",
    "echo SOLARIS9_B134_TOOLBOX_INVENTORY=PASS",
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
            raise SystemExit("SOLARIS9_B134_TOOLBOX_INVENTORY=FAIL reason=console-closed")
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
            expected = f"X{command_index}".encode()
            if expected not in output_lines:
                raise SystemExit(
                    f"SOLARIS9_B134_TOOLBOX_INVENTORY=FAIL reason=step-{command_index}"
                )
            if command_index == len(commands):
                raise SystemExit(0)

        command = commands[command_index]
        print(f"\nSOLARIS9_B134_TOOLBOX_INVENTORY_ACTION={command_index + 1}:{command}", flush=True)
        wire_command = f"{command}; echo X{command_index + 1}"
        console.sendall(wire_command.encode("ascii") + b"\r")
        command_index += 1
        captured.clear()

raise SystemExit("SOLARIS9_B134_TOOLBOX_INVENTORY=FAIL reason=deadline")
