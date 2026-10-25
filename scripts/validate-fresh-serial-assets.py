#!/usr/bin/env python3
"""Pinned fresh-launch handoff: offline tests/replay only; no guest invocation."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "artifacts/fresh-serial-boot"
PIN = "b1e9d0ba40b775c888c7e0c129059d0491cd1ceeb30638b4888f73e3750c6ebb"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run(args, cwd):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", HARNESS="coldboot_fresh.py")
    p = subprocess.Popen(args, cwd=cwd, env=env, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True, start_new_session=True)
    try:
        text, _ = p.communicate(timeout=90)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        text, _ = p.communicate()
        print(text)
        raise RuntimeError("offline subprocess exceeded 90 seconds")
    print(text, end="")
    if p.returncode:
        raise RuntimeError("offline subprocess failed: " + str(args))
    return text

def main():
    manifest = ASSETS / "integration-manifest.json"
    if sha(manifest) != PIN:
        raise RuntimeError("integration manifest drift")
    pins = json.loads(manifest.read_text())
    for name, digest in pins.items():
        rel = Path(name)
        if rel.is_absolute() or ".." in rel.parts:
            raise RuntimeError("invalid manifest path")
        p = ASSETS / name
        if p.is_symlink() or not p.is_file() or sha(p) != digest:
            raise RuntimeError("frozen handoff drift: " + name)
    # All replay work occurs in new writable copies, even with read-only inputs.
    with tempfile.TemporaryDirectory(prefix="fresh serial offline ") as tmp:
        d = Path(tmp)
        for name in pins:
            p = d / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes((ASSETS / name).read_bytes())
        applied = d / "applied"
        applied.mkdir()
        (applied / "coldboot_fresh.py").write_bytes((d / "baseline.py").read_bytes())
        patch = str(d / "fresh-serial.patch")
        run(["git", "apply", "--check", patch], applied)
        run(["git", "apply", patch], applied)
        expected = {"coldboot_fresh.py", "fresh_serial.py", "boot_protocol.py"}
        if {p.name for p in applied.iterdir()} != expected:
            raise RuntimeError("patch target mismatch")
        for name in expected:
            if (applied / name).read_bytes() != (d / name).read_bytes():
                raise RuntimeError("patch/runtime mismatch: " + name)
        result = run([sys.executable, "-m", "unittest", "-v",
                      "test_fresh_serial.py", "test_retention_existing.py",
                      "test_default_existing.py"], d)
        if "Ran 51 tests" not in result or "\nOK\n" not in result:
            raise RuntimeError("expected all 51 frozen tests")
        # Replay the saved diskless evidence; never execute native_smoke.py.
        evidence = d / "native-evidence"
        evidence.mkdir()
        total = 0
        with tarfile.open(d / "native-evidence.tar") as archive:
            members = archive.getmembers()
            if len(members) > 64:
                raise RuntimeError("unexpected evidence member count")
            for member in members:
                rel = Path(member.name)
                if rel.is_absolute() or ".." in rel.parts:
                    raise RuntimeError("invalid evidence path")
                if member.isdir():
                    continue
                if not member.isfile():
                    raise RuntimeError("nonregular evidence")
                total += member.size
                if total > 1024 * 1024:
                    raise RuntimeError("unexpected evidence size")
                dest = evidence / rel
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(archive.extractfile(member).read())
        run([sys.executable, "verify_native.py"], d)
        if sha(d / "native-verified.json") != pins["native-verified.json"]:
            raise RuntimeError("saved evidence replay mismatch")
    print("CI_RESULT=fresh_serial_offline_assetvalidation")
    print("INSTALLED_GUEST_EXECUTED=NO AUTHENTICATED_LOGIN=NOT_TESTED")
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print("CI_RESULT=fresh_serial_offline_assetvalidation_failed", file=sys.stderr)
        print(str(error), file=sys.stderr)
        sys.exit(1)
