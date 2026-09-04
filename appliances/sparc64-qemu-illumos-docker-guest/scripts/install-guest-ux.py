#!/usr/bin/env python3
"""Install the release's user-facing networking helpers over its QEMU console."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import shlex
import subprocess


parser = argparse.ArgumentParser()
parser.add_argument("--socket", required=True)
parser.add_argument("--guest-command", type=Path, required=True)
parser.add_argument("--source-dir", type=Path, required=True)
parser.add_argument("--transcript-dir", type=Path, required=True)
args = parser.parse_args()

files = ("BRING_UP_NETWORKING.sh", "CALL_BBS.sh")
args.transcript_dir.mkdir(parents=True, exist_ok=True)


def guest(command: str, label: str) -> str:
    proc = subprocess.run(
        [
            "python3",
            str(args.guest_command),
            "--socket",
            args.socket,
            "--timeout",
            "300",
            "--transcript",
            str(args.transcript_dir / f"{label}.log"),
            "--command",
            command,
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    print(proc.stdout, end="")
    return proc.stdout


expected = {
    name: hashlib.sha256((args.source_dir / name).read_bytes()).hexdigest()
    for name in files
}
probe = guest(
    "; ".join(
        f"test -f /jack/{name} && /usr/bin/digest -a sha256 /jack/{name} || true"
        for name in files
    ),
    "probe",
)

if all(digest in probe for digest in expected.values()):
    print("GUEST_UX_ALREADY_INSTALLED=PASS")
else:
    guest("test -d /jack && id jack", "preflight")
    for name in files:
        lines = (args.source_dir / name).read_text(encoding="utf-8").splitlines()
        words = " ".join(shlex.quote(line) for line in lines)
        command = (
            f"/usr/bin/printf '%s\\n' {words} > /jack/{name} && "
            f"/usr/bin/chmod 0755 /jack/{name} && "
            f"/usr/bin/chown jack:staff /jack/{name} && "
            f"/usr/bin/digest -a sha256 /jack/{name}"
        )
        output = guest(command, f"install-{name}")
        if expected[name] not in output:
            raise SystemExit(f"installed digest mismatch for {name}")
    print("GUEST_UX_INSTALL=PASS")

guest(
    "test -x /jack/BRING_UP_NETWORKING.sh && test -x /jack/CALL_BBS.sh && "
    "/usr/bin/ls -l /jack/BRING_UP_NETWORKING.sh /jack/CALL_BBS.sh",
    "verify",
)
print("GUEST_UX_VERIFY=PASS")

guest(
    "/usr/bin/cp -p /etc/resolv.conf "
    "/etc/resolv.conf.before-niagara-release 2>/dev/null || true; "
    "/usr/bin/printf '%s\\n' 'nameserver 10.0.5.1' > /etc/resolv.conf && "
    "/usr/bin/chown root:sys /etc/resolv.conf && "
    "/usr/bin/chmod 0644 /etc/resolv.conf && "
    "/usr/bin/cp -p /etc/nsswitch.conf "
    "/etc/nsswitch.conf.before-niagara-release 2>/dev/null || true; "
    "/usr/bin/sed -e 's/^hosts:.*/hosts: files dns/' "
    "-e 's/^ipnodes:.*/ipnodes: files dns/' /etc/nsswitch.conf "
    "> /etc/nsswitch.conf.niagara && "
    "/usr/bin/chown root:sys /etc/nsswitch.conf.niagara && "
    "/usr/bin/chmod 0644 /etc/nsswitch.conf.niagara && "
    "/usr/bin/mv /etc/nsswitch.conf.niagara /etc/nsswitch.conf && "
    "/usr/bin/grep -Fx 'nameserver 10.0.5.1' /etc/resolv.conf && "
    "/usr/bin/grep -E '^hosts:[[:space:]]+files[[:space:]]+dns[[:space:]]*$' "
    "/etc/nsswitch.conf && "
    "/usr/bin/grep -E '^ipnodes:[[:space:]]+files[[:space:]]+dns[[:space:]]*$' "
    "/etc/nsswitch.conf && "
    "echo GUEST_NAME_SERVICE_CONFIG=PASS",
    "configure-name-service",
)
print("GUEST_NAME_SERVICE_INSTALL=PASS")
