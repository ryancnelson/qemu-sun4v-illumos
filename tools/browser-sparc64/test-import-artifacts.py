#!/usr/bin/env python3
"""Actual importer subprocess tests; tiny host files, no emulator execution."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SCRIPT = Path(os.environ.get('IMPORT_SCRIPT', HERE / 'import-artifacts.sh'))
NAMES = ('qemu-system-sparc64.js', 'qemu-system-sparc64.wasm',
         'qemu-system-sparc64.worker.js')
DATA = (b'export default function () {}\n', b'\0asm\x01\0\0\0',
        b'// synthetic worker\n')


class ImportContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='import contract ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.harness = self.root / 'harness space'
        self.harness.mkdir()
        self.script = self.harness / 'import-artifacts.sh'
        shutil.copyfile(SCRIPT, self.script)
        shutil.copyfile(HERE / 'ASSET-SHA256SUMS', self.harness / 'ASSET-SHA256SUMS')
        self.source = self.root / 'source space'
        self.source.mkdir()
        for name, content in zip(NAMES, DATA):
            (self.source / name).write_bytes(content)
        self.manifest = self.root / 'expected bundle.txt'
        self.lines = [hashlib.sha256(content).hexdigest() + '  assets/' + name
                      for name, content in zip(NAMES, DATA)]
        self.manifest.write_text('\n'.join(self.lines) + '\n')
        self.assets = self.harness / 'assets'

    def run_import(self, explicit=True, extra=None):
        args = ['bash', str(self.script), str(self.source)]
        if explicit:
            args += ['--expected-manifest', str(self.manifest)]
        if extra:
            args += extra
        result = subprocess.run(args, capture_output=True, text=True, timeout=15)
        print(self.id().split('.')[-1], 'exit', result.returncode,
              result.stderr.strip(), flush=True)
        return result

    def refuse(self, explicit=True):
        self.assertNotEqual(self.run_import(explicit).returncode, 0)
        self.assertFalse(self.assets.exists(), 'refusal mutated destination')

    def test_default_shipped_manifest_rejects_unpinned_before_mkdir(self):
        self.refuse(False)

    def test_explicit_exact_bundle_spaces_and_repeat(self):
        self.assertEqual(self.run_import().returncode, 0)
        for name, content in zip(NAMES, DATA):
            self.assertEqual((self.assets / name).read_bytes(), content)
        before = [(self.assets / n).stat().st_mtime_ns for n in NAMES]
        self.assertEqual(self.run_import().returncode, 0)
        self.assertEqual(before, [(self.assets / n).stat().st_mtime_ns for n in NAMES])

    def test_default_uses_shipped_manifest_location(self):
        shutil.copyfile(self.manifest, self.harness / 'ASSET-SHA256SUMS')
        self.assertEqual(self.run_import(False).returncode, 0)

    def test_extensionless_module(self):
        (self.source / NAMES[0]).rename(self.source / 'qemu-system-sparc64')
        self.assertEqual(self.run_import().returncode, 0)

    def test_wrong_each_companion_no_partial_copy(self):
        for index in range(3):
            with self.subTest(index=index):
                path = self.source / NAMES[index]
                path.write_bytes(DATA[index] + b'\n')
                self.refuse()
                path.write_bytes(DATA[index])

    def test_missing_each_companion(self):
        for name, content in zip(NAMES, DATA):
            with self.subTest(name=name):
                (self.source / name).unlink()
                self.refuse()
                (self.source / name).write_bytes(content)

    def test_missing_manifest(self):
        self.manifest.unlink()
        self.refuse()

    def test_missing_default_manifest(self):
        (self.harness / 'ASSET-SHA256SUMS').unlink()
        self.refuse(False)

    def test_malformed_duplicate_partial_and_extra_manifests(self):
        variants = ['', '\n'.join(self.lines[:2]), '\n'.join(self.lines + [self.lines[0]]),
                    '\n'.join(self.lines).replace('assets/', '../assets/', 1),
                    '\n'.join(self.lines).replace(self.lines[0][:64], 'g' * 64),
                    '\n'.join(self.lines + ['0' * 64 + '  assets/other.js']),
                    '\n'.join(self.lines) + '\n\n']
        for text in variants:
            with self.subTest(text=text[:80]):
                self.manifest.write_text(text)
                self.refuse()

    def test_mixed_bundle_late_worker_refused(self):
        (self.source / NAMES[2]).write_bytes(b'// other build worker\n')
        self.refuse()

    def test_optional_known_firmware_entry(self):
        self.manifest.write_text('\n'.join(self.lines +
            ['0' * 64 + '  assets/openbios-sparc64.patched']) + '\n')
        self.assertEqual(self.run_import().returncode, 0)
        self.assertFalse((self.assets / 'openbios-sparc64.patched').exists())

    def test_late_collision_preserves_everything(self):
        self.assets.mkdir()
        (self.assets / NAMES[2]).write_bytes(b'old worker')
        (self.assets / 'unrelated').write_bytes(b'preserve')
        before = {p.name: p.read_bytes() for p in self.assets.iterdir()}
        self.assertNotEqual(self.run_import().returncode, 0)
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.assets.iterdir()})

    def test_partial_existing_approved_bundle_completed(self):
        self.assets.mkdir()
        (self.assets / NAMES[0]).write_bytes(DATA[0])
        self.assertEqual(self.run_import().returncode, 0)
        self.assertEqual(set(p.name for p in self.assets.iterdir()), set(NAMES))

    def test_hash_matching_invalid_wasm_still_refused(self):
        (self.source / NAMES[1]).write_bytes(b'bad wasm')
        self.lines[1] = hashlib.sha256(b'bad wasm').hexdigest() + '  assets/' + NAMES[1]
        self.manifest.write_text('\n'.join(self.lines) + '\n')
        self.refuse()

    def test_unknown_option_refused(self):
        self.assertNotEqual(self.run_import(False, ['--destination', 'elsewhere']).returncode, 0)
        self.assertFalse(self.assets.exists())


if __name__ == '__main__':
    unittest.main()
