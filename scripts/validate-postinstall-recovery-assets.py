#!/usr/bin/env python3
"""Validate frozen recovery R4 using private host mocks, never the guest script."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "artifacts/postinstall-recovery-r4"
PIN = "f9a4d6eb85d4a5fdbd76a2909ca3d67dc1620f8aa5901a45d28565a21ebf7ef1"

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def run(args, cwd):
    p = subprocess.Popen(args, cwd=cwd,
                         env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"),
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, start_new_session=True)
    try:
        output, _ = p.communicate(timeout=90)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        output, _ = p.communicate()
        print(output)
        raise RuntimeError("offline subprocess exceeded 90 seconds")
    print(output, end="")
    if p.returncode:
        raise RuntimeError("offline subprocess failed: " + str(args))
    return output

def main():
    manifest = ASSETS / "integration-manifest.json"
    if sha(manifest) != PIN:
        raise RuntimeError("manifest drift")
    pins = json.loads(manifest.read_text())
    for name, digest in pins.items():
        rel = Path(name)
        if rel.is_absolute() or ".." in rel.parts:
            raise RuntimeError("invalid relative path")
        p = ASSETS / name
        if p.is_symlink() or not p.is_file() or sha(p) != digest:
            raise RuntimeError("frozen recovery drift: " + name)
    with tempfile.TemporaryDirectory(prefix="recovery offline ") as tmp:
        d = Path(tmp)
        for name in pins:
            p = d / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes((ASSETS / name).read_bytes())
        applied = d / "applied"
        applied.mkdir()
        (applied / "recover.sh").write_bytes((d / "R3/recover.sh").read_bytes())
        patch = str(d / "R4-nawk.patch")
        run(["git", "apply", "--check", patch], applied)
        run(["git", "apply", patch], applied)
        if [p.name for p in applied.iterdir()] != ["recover.sh"]:
            raise RuntimeError("unexpected patch targets")
        if (applied / "recover.sh").read_bytes() != (d / "recover.sh").read_bytes():
            raise RuntimeError("R3 plus patch differs from frozen R4")
        run(["bash", "-n", "recover.sh"], d)
        result = run([sys.executable, "-m", "unittest", "-v", "test_recovery.py"], d)
        if "Ran 20 tests" not in result or "\nOK\n" not in result:
            raise RuntimeError("expected all 20 frozen fixture methods")
    print("CI_RESULT=postinstall_recovery_offline_assetvalidation")
    print("NATIVE_RECOVERY_EXECUTED=NO RESTORE_NEEDED_NATIVE=NOT_TESTED")
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print("CI_RESULT=postinstall_recovery_offline_assetvalidation_failed", file=sys.stderr)
        print(str(error), file=sys.stderr)
        sys.exit(1)
