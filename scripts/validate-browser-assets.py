#!/usr/bin/env python3
"""Finite source/vendor tests only; no Wasm, browser, Docker or guest launch."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
H = ROOT / 'tools/browser-sparc64'
IMAGE_SHA256 = '52fa9b2c6313c7c50f430ea508815b0c1ed2bf7a5978ffb2131c21acffa5bdf5'

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
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
    # Explicit offline source/contract suite; its own scratch is not a Node fixture.
    subprocess.run([sys.executable, '-B', str(H/'sentinel/check.py')],
                   check=True, timeout=20, env=env)
    # CI mounts /src read-only. Copy only pinned source files, never imported assets,
    # then generate the fixed tiny fixture in this private, writable test layout.
    with tempfile.TemporaryDirectory(prefix='sun4u-browser-assets-') as tmp:
        scratch = Path(tmp)
        for name in expected:
            target = scratch / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(H/name, target)
        assets = scratch/'assets'
        assets.mkdir()
        image = assets/'sentinel-32k.raw'
        generated = subprocess.run(
            [sys.executable, '-B', str(scratch/'sentinel/sentinel.py'), 'generate', str(image)],
            check=True, capture_output=True, timeout=10, env=env)
        data = image.read_bytes()
        if len(data) != 32768 or hashlib.sha256(data).hexdigest() != IMAGE_SHA256:
            raise ValueError('generated storage fixture mismatch')
        if generated.stdout != (scratch/'sentinel/manifest.json').read_bytes():
            raise ValueError('generated storage manifest mismatch')
        subprocess.run(['node', '--test', 'test-config.mjs', 'test-terminal-input.mjs',
                        'test-storage.mjs'], cwd=scratch, check=True, timeout=30, env=env)
    # Compiled firmware is deliberately not packaged. Its serving test is an
    # explicit manual/imported-assets gate; these two HTTP tests need no binaries.
    subprocess.run([sys.executable, '-B', '-m', 'unittest',
        'test_server.ServerTests.test_html_is_cross_origin_isolated',
        'test_server.ServerTests.test_wasm_mime'], cwd=H, check=True, timeout=15, env=env)
    for name in ('serve.py', 'test_server.py'):
        compile((H/name).read_bytes(), name, 'exec')
    signal.alarm(0)
    print('BROWSER_STORAGE_ASSETS=VALIDATED_NOT_RUNTIME_ACCEPTANCE')
    print('BROWSER_ASSETS=VALIDATED_NOT_RUNTIME_ACCEPTANCE')

if __name__ == '__main__':
    main()
