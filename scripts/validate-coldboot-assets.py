#!/usr/bin/env python3
"""Pinned offline assets/mocks only. Never executes a coldboot invocation."""
import hashlib
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "work/maestro-sun4u-001"
PINS = {
    "coldboot-harness/coldboot.py": "9ae6db9926a4cd7fd1e8f1dc2e204fe5705cb5370018dae75821075bfc75697b",
    "coldboot-harness/test_coldboot.py": "55f18ff1ac31628181eee5518171d57254f528cac24a4fffd339b3b7160019b3",
    "coldboot-harness-ready/test_ready.py": "aaa0117fcb1f5e328817db5136d34126f9c50dee57b6c9c40f2351c4dc9de3c8",
    "coldboot-harness-ready/run142-manifest.template.json": "35d64ed3dee336d1ca5a3f691adf1b58c83ddf24ce9cca815d94f20e05f8049e",
    "coldboot-harness-ready/integration.patch": "6faa0f0050d22d86ec9bdc5f85231b057e7a11a8f4d467ae4695d5ba457d7c8b",
}

def deny_runtime(event, args):
    if event.startswith(("subprocess.", "socket.")) or event in ("os.system", "os.exec", "os.posix_spawn", "os.fork", "os.forkpty"):
        raise RuntimeError("asset validation forbids process/network execution: " + event)

def main():
    sys.dont_write_bytecode = True
    sys.addaudithook(deny_runtime)
    try:
        if sys.version_info < (3, 11):
            raise RuntimeError("Python 3.11+ required")
        for name, expected in PINS.items():
            path = ASSETS / name
            if path.is_symlink() or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                raise RuntimeError("missing/changed pinned asset: " + name)
            print("ASSET_SHA256=" + expected + " " + name, flush=True)
        sys.path.insert(0, str(ASSETS / "coldboot-harness-ready"))
        suite = unittest.defaultTestLoader.loadTestsFromName("test_ready")
        if suite.countTestCases() != 20:
            raise RuntimeError("expected exactly 20 pinned mock tests")
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        if not result.wasSuccessful() or result.skipped:
            raise RuntimeError("mock test failure or skipped coverage")
    except Exception as error:
        print("CI_RESULT=assetvalidation_failed", flush=True)
        print(str(error), file=sys.stderr)
        return 1
    print("CI_RESULT=assetvalidation", flush=True)
    print("INSTALLED_COLDBOOT_SUCCESS=NOT_TESTED", flush=True)
    return 0

if __name__ == "__main__":
    sys.exit(main())
