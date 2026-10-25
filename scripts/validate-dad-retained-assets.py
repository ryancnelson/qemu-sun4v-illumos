#!/usr/bin/env python3
"""Finite offline hash/mock validation; never invokes a coldboot or Docker."""
import hashlib
from pathlib import Path
import signal
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
PINS = {'scripts/coldboot-dad-retained.py': '2d058c758ab669d19ee049b7e60ad5eba6c9c3a0939f7d66b16eb1ebc6c57966', 'scripts/retention.py': '1a73b6e73faa3f8830d1af0888af2c5837966b5ee5febd9d48644bf8fda4022d', 'tests/coldboot-retention/approved-socket.py': '76dc7dbeddb6ecf34786c1cd4c2b7510db41fc7a8f9f7eebfeaf5fa3a09496b7', 'tests/coldboot-retention/baseline.py': '249897708935a1c83911d81bc1fc66a7c2f46ba924b9a8037b13ecef65f1f5e4', 'tests/coldboot-retention/native-fixtures/created-inspect.json': '75e59a3bd97a8856433bc13e4147a8668662c6e66cffcecc758bc3d32c14386f', 'tests/coldboot-retention/native-fixtures/native-after-eof.json': '9bc10110e9664cfbd97ceaa428598ae60d8c3b2ee93679c14054c88bf939d8a9', 'tests/coldboot-retention/native-fixtures/native-started.json': '8938123c86dc2f3bdbbf245056782b192df9620bde5abc3a6b69378c8909771d', 'tests/coldboot-retention/native-fixtures/socket-after-eof.json': 'ea9e2e84522ac7482388b09a36700bd54c8d97612e39b5ef4f5bf819997b9b25', 'tests/coldboot-retention/native-fixtures/socket-created.json': 'f97b32140d342ce6923e994782f9e0cd8704e66626cfb7e4310b1509d93edf47', 'tests/coldboot-retention/native-fixtures/socket-running.json': 'ea9e2e84522ac7482388b09a36700bd54c8d97612e39b5ef4f5bf819997b9b25', 'tests/coldboot-retention/test_dad_pin.py': '422533eb1dfe6f230ddcc361541ad73ec2020863f2b1c135f389adab099f6cf0', 'tests/coldboot-retention/test_default.py': '55f18ff1ac31628181eee5518171d57254f528cac24a4fffd339b3b7160019b3', 'tests/coldboot-retention/test_retention.py': '141498a58f95490da03a990d36fdc3c006b1dbc296fb18a5efa6c7d4878864ab', 'notes/firmware132-dadcompat-build/artifacts/openbios-sparc64.candidate': 'e235a3bbfdff9e5b4c364bf46757a0975265ff4ea52c95d891238b4be36813dc'}

def deny_runtime(event, args):
    if event.startswith(("subprocess.", "socket.")) or event in ("os.system", "os.exec", "os.posix_spawn", "os.fork", "os.forkpty"):
        raise RuntimeError("asset validation forbids runtime execution: " + event)
    if event == "open" and args and isinstance(args[0], (str, bytes)):
        name = str(args[0])
        if name.startswith("/mnt/disk-images/"):
            raise RuntimeError("asset validation forbids installed disk paths")

def timeout(sig, frame):
    raise TimeoutError("60-second offline validation limit")

def main():
    sys.dont_write_bytecode = True
    sys.addaudithook(deny_runtime)
    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(60)
    try:
        for name, expected in PINS.items():
            f = ROOT / name
            if f.is_symlink() or not f.is_file() or hashlib.sha256(f.read_bytes()).hexdigest() != expected:
                raise RuntimeError("missing/changed pinned asset: " + name)
        sys.path.insert(0, str(ROOT / "tests/coldboot-retention"))
        import test_retention
        sys.modules["coldboot"] = test_retention.c
        suite = unittest.TestSuite(unittest.defaultTestLoader.loadTestsFromName(n)
                                  for n in ("test_retention", "test_default", "test_dad_pin"))
        if suite.countTestCases() != 39:
            raise RuntimeError("expected exactly 39 tests")
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        if not result.wasSuccessful() or result.skipped:
            raise RuntimeError("failed/skipped mock coverage")
    except Exception as error:
        print("CI_RESULT=assetvalidation_failed", flush=True)
        print(str(error), file=sys.stderr)
        return 1
    finally:
        signal.alarm(0)
    print("CI_RESULT=assetvalidation", flush=True)
    print("INSTALLED_COLDBOOT_SUCCESS=NOT_TESTED", flush=True)
    return 0

if __name__ == "__main__":
    sys.exit(main())
