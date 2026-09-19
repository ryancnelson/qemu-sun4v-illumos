"""Exercise verified archive reuse and rejection with isolated fake downloads."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'appliances/sparc64-qemu-illumos-docker-guest/scripts/stage-golden-inputs.sh'


@unittest.skipUnless(sys.platform == 'linux', 'staging uses GNU cp on the Linux builder')
class GoldenInputCacheTest(unittest.TestCase):
    def run_case(self, cached, downloaded, succeeds):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            run = base / 'golden-volume-amd64-2'
            old = base / 'golden-volume-amd64-1'
            for folder in ('scripts', 'sources', 'release', 'assets'):
                (run / folder).mkdir(parents=True)
            shutil.copyfile(SCRIPT, run / 'scripts/stage-golden-inputs.sh')
            (run / 'appliance').touch()
            names = [('sources/qemu-049affb20df67162cf58deeaf74d5ad4b83cbdc3.tar.gz', 'sources/SHA256SUMS'),
                     ('release/sparc64-qemu-openindiana-20g-beta-20260901.tar.zst', 'RELEASE-ARCHIVE.SHA256SUMS')]
            for relative, manifest in names:
                candidate = old / relative
                candidate.parent.mkdir(parents=True, exist_ok=True)
                candidate.write_text(cached)
                (run / manifest).write_text(hashlib.sha256(b'accepted').hexdigest() + '  ' + candidate.name + '\n')
            bindir = base / 'bin'
            bindir.mkdir()
            fake = bindir / 'scp'
            fake.write_text('#!/bin/bash\n'
                            'case "$*" in *assets/firmware*) exit 0;; esac\n'
                            'echo download >> "$DOWNLOAD_LOG"\n'
                            'printf "%s" "$DOWNLOAD_BYTES" > "${!#}"\n')
            fake.chmod(0o755)
            log = base / 'downloads'
            env = dict(os.environ, PATH=str(bindir) + ':' + os.environ['PATH'],
                       DOWNLOAD_BYTES=downloaded, DOWNLOAD_LOG=str(log))
            result = subprocess.run(['bash', str(run / 'scripts/stage-golden-inputs.sh')],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode == 0, succeeds, result.stderr)
            self.assertEqual(log.exists(), cached != 'accepted')
            for relative, _ in names:
                self.assertEqual((old / relative).read_text(), cached)
                if succeeds:
                    self.assertEqual((run / relative).read_text(), 'accepted')
                else:
                    self.assertFalse((run / relative).exists())
            self.assertFalse(list(run.rglob('*.partial.*')))

    def test_verified_cache_avoids_download(self):
        self.run_case('accepted', 'unused', True)

    def test_bad_cache_falls_back_to_verified_download(self):
        self.run_case('corrupt', 'accepted', True)

    def test_bad_download_cannot_be_published(self):
        self.run_case('corrupt', 'also corrupt', False)


if __name__ == '__main__':
    unittest.main()
