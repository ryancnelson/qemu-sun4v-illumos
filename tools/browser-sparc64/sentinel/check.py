#!/usr/bin/env python3
"""Offline regression entry point; generates only in a temporary layout."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
PIN = '52fa9b2c6313c7c50f430ea508815b0c1ed2bf7a5978ffb2131c21acffa5bdf5'

def main():
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
    with tempfile.TemporaryDirectory(prefix='sun4u-sentinel-') as tmp:
        root = Path(tmp) / 'tools/browser-sparc64'
        suite = root / 'sentinel'
        suite.mkdir(parents=True)
        for name in ('sentinel.py', 'test_sentinel.py', 'manifest.json',
                     'check_contract.py', 'storage-control.fth', 'expected.json'):
            shutil.copyfile(HERE / name, suite / name)
        assets = root / 'assets'
        assets.mkdir()
        output = assets / 'sentinel-32k.raw'
        result = subprocess.run([sys.executable, str(suite / 'sentinel.py'),
                                 'generate', str(output)], check=True,
                                capture_output=True, env=env)
        data = output.read_bytes()
        if len(data) != 32768 or hashlib.sha256(data).hexdigest() != PIN:
            raise RuntimeError('generated fixture does not match frozen pin')
        if json.loads(result.stdout) != json.loads((suite / 'manifest.json').read_text()):
            raise RuntimeError('generated manifest drift')
        # Verify byte-for-byte manifest reproducibility, not only its parsed meaning.
        if result.stdout != (suite / 'manifest.json').read_bytes():
            raise RuntimeError('generated manifest byte drift')
        subprocess.run([sys.executable, str(suite / 'test_sentinel.py')],
                       check=True, env=env)
        subprocess.run([sys.executable, str(suite / 'check_contract.py')],
                       check=True, env=env)
        print('PASS: deterministic tools/browser-sparc64/assets/sentinel-32k.raw '
              '+ exact manifest + 8 tests + static command contract')

if __name__ == '__main__':
    main()
