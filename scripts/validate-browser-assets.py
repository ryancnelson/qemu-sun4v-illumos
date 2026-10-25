#!/usr/bin/env python3
"""Finite source/vendor tests only; no Wasm, browser, Docker or guest launch."""
import hashlib
import json
from pathlib import Path
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
H = ROOT / 'tools/browser-sparc64'

def timeout(signum, frame):
    raise TimeoutError('browser asset validation60s deadline')

def main():
    signal.signal(signal.SIGALRM, timeout)
    signal.alarm(60)
    expected = json.loads((H / 'SOURCE-SHA256.json').read_text())
    for name, digest in expected.items():
        path = H / name
        if path.is_symlink() or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError('browser asset mismatch: ' + name)
    # Only these exact source tests, no artifact import/build or browser launch.
    subprocess.run(['node', '--test', 'test-config.mjs', 'test-terminal-input.mjs'], cwd=H, check=True, timeout=30)
    # Compiled firmware is deliberately not packaged. Its serving test is an
    # explicit manual/imported-assets gate; these two HTTP tests need no binaries.
    subprocess.run([sys.executable, '-B', '-m', 'unittest',
        'test_server.ServerTests.test_html_is_cross_origin_isolated',
        'test_server.ServerTests.test_wasm_mime'], cwd=H, check=True, timeout=15)
    for name in ('serve.py', 'test_server.py'):
        compile((H/name).read_bytes(), name, 'exec')
    signal.alarm(0)
    print('BROWSER_ASSETS=VALIDATED_NOT_RUNTIME_ACCEPTANCE')

if __name__ == '__main__':
    main()
