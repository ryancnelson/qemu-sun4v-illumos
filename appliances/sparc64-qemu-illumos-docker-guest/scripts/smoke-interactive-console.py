#!/usr/bin/env python3
"""Prove that the published `docker run -it` path is a bidirectional console."""

from __future__ import annotations

import argparse
import os
import pty
import re
import select
import signal
import subprocess
import sys
import time
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument("--image", required=True)
parser.add_argument("--name", required=True)
parser.add_argument("--timeout", type=int, default=240)
parser.add_argument("--transcript", type=Path, required=True)
args = parser.parse_args()
volume_name = f"{args.name}-state"

subprocess.run(
    ["docker", "volume", "rm", volume_name],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    check=False,
)
subprocess.run(
    [
        "docker",
        "volume",
        "create",
        "--label",
        "io.niagara.appliance-ci=1",
        volume_name,
    ],
    stdout=subprocess.DEVNULL,
    check=True,
)

command = [
    "docker",
    "run",
    "--rm",
    "-it",
    "--name",
    args.name,
    "--hostname",
    "oi-basecamp",
    "--memory",
    "6g",
    "--cpus",
    "2",
    "-e",
    "NIAGARA_NETWORK=off",
    "-e",
    "OPENBOOT_AUTO_BOOT=false",
    "--tmpfs",
    "/run/unit100:rw,size=1200m,mode=0700",
    "--mount",
    f"type=volume,src={volume_name},dst=/var/lib/illumos-appliance",
    args.image,
]

master, slave = pty.openpty()
process = subprocess.Popen(
    command,
    stdin=slave,
    stdout=slave,
    stderr=slave,
    start_new_session=True,
    close_fds=True,
)
os.close(slave)

transcript = bytearray()
deadline = time.monotonic() + args.timeout
sent_banner = False
passed = False
openboot_prompt = re.compile(rb"(?:^|\n)(?:\{[0-9a-fA-F]+\} )?ok ")

try:
    while time.monotonic() < deadline:
        readable, _, _ = select.select([master], [], [], 1.0)
        if readable:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                chunk = b""
            if not chunk:
                if process.poll() is not None:
                    break
                continue
            transcript.extend(chunk)
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()

        normalized = bytes(transcript).replace(b"\r", b"")
        if not sent_banner and openboot_prompt.search(normalized):
            os.write(master, b"banner\r")
            sent_banner = True
            continue
        if sent_banner and normalized.count(b"Sun Fire T200, No Keyboard") >= 2:
            passed = True
            break

    args.transcript.parent.mkdir(parents=True, exist_ok=True)
    args.transcript.write_bytes(transcript)

    if not passed:
        raise SystemExit(
            "INTERACTIVE_CONSOLE=FAIL: OpenBoot prompt and bidirectional banner "
            f"exchange not observed within {args.timeout}s"
        )
    print("\nINTERACTIVE_CONSOLE=PASS mode=stdio command=banner")
finally:
    try:
        os.close(master)
    except OSError:
        pass
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        else:
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=5)
    subprocess.run(
        ["docker", "rm", "-f", args.name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(
        ["docker", "volume", "rm", volume_name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
