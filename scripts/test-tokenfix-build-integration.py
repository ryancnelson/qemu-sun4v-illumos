"""Recipe wiring/refusal tests: toolchain mocked, compilation never occurs."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RECIPE = ROOT / 'scripts/build-openbios-sun4u-solaris.sh'
FIXTURE = Path(os.environ.get('TOKENFIX_TEST_TABLE', ROOT / 'work/maestro-sun4u-001/diskboot-loader-kestrel/candidate/forth/device/table.fs'))
BASE = '7691a6aae98da1de270304071791dbb3e34fb30372790a1ff21d86b68fd0d9d2'
FIXED = 'cef7bb8cfe39a7c0e27dcad8568b6890da7837a936063b81cf997687804f46c2'

class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='tokenfix recipe ')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.project = self.root / 'project'
        (self.project / 'scripts').mkdir(parents=True)
        shutil.copyfile(RECIPE, self.project / 'scripts/build.sh')
        (self.project / 'patches/openbios').mkdir(parents=True)
        self.patch = self.project / 'patches/openbios/0004-fcode-64bit-token-slots.patch'
        shutil.copyfile(ROOT / 'patches/openbios/0004-fcode-64bit-token-slots.patch', self.patch)
        shutil.copyfile(ROOT / 'patches/openbios/0005-sparc64-ata-dad-compatible.patch',
                        self.project / 'patches/openbios/0005-sparc64-ata-dad-compatible.patch')
        self.source = self.root / 'source space'
        (self.source / '.git').mkdir(parents=True)
        (self.source / 'drivers').mkdir()
        dad_base = Path(os.environ.get('DADCOMPAT_TEST_IDE', ROOT / 'work/maestro-sun4u-001/ata-dad-compatible-kestrel/baseline/drivers/ide.c'))
        shutil.copyfile(dad_base, self.source / 'drivers/ide.c')
        (self.source / 'forth/device').mkdir(parents=True)
        candidate = FIXTURE.read_bytes()
        self.assertEqual(hashlib.sha256(candidate).hexdigest(), FIXED)
        baseline = candidate.replace(b'  [\'], xa+\n  [\'], xa1+\n', b'\\   [\'], /xa+\n\\   [\'], /xa1+\n')
        self.assertEqual(hashlib.sha256(baseline).hexdigest(), BASE)
        self.table = self.source / 'forth/device/table.fs'
        self.table.write_bytes(baseline)
        (self.source / 'config/scripts').mkdir(parents=True)
        self.stub(self.source / 'config/scripts/switch-arch', 'exit 0')
        tools = self.root / 'tools'
        tools.mkdir()
        self.stub(tools / 'git', '''case "$*" in
*rev-parse*) echo "${MOCK_COMMIT:-af97fd7af5e7c18f591a7b987291d3db4ffb28b5}" ;;
*status*) printf '%s' "${MOCK_DIRTY:-}" ;;
*apply*0005*) src=$2; shift 2; check=; for arg do
  case "$arg" in --check) check=--dry-run;; *0005*) p=$arg;; esac
done
"$REAL_PATCH" --batch --forward ${check:+$check} "$src/drivers/ide.c" "$p" || exit $? ;;
esac
exit 0''')
        self.stub(tools / 'make', 'echo MOCK_COMPILER_BOUNDARY; exit 86')
        for tool in ('xsltproc', 'toke', 'sparc64-linux-gnu-gcc', 'sparc64-linux-gnu-objdump'):
            self.stub(tools / tool, 'echo UNEXPECTED_TOOL_EXECUTION >&2; exit 97')
        self.env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'])
        self.env['REAL_PATCH'] = shutil.which('patch')
        self.env.pop('MOCK_COMMIT', None)
        self.env.pop('MOCK_DIRTY', None)

    def stub(self, path, body):
        path.write_text('#!/bin/sh\n' + body + '\n')
        path.chmod(0o755)

    def run_recipe(self):
        return subprocess.run(['bash', str(self.project / 'scripts/build.sh'), str(self.source), str(self.root / 'output')],
                              env=self.env, capture_output=True, text=True, timeout=15)

    def refused(self):
        result = self.run_recipe()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotEqual(result.returncode, 86)
        self.assertNotIn('MOCK_COMPILER_BOUNDARY', result.stdout)
        self.assertFalse((self.root / 'output').exists())

    def test_exact_patch_applied_before_compiler_boundary(self):
        result = self.run_recipe()
        self.assertEqual(result.returncode, 86, result.stdout + result.stderr)
        self.assertEqual(hashlib.sha256(self.table.read_bytes()).hexdigest(), FIXED)
        self.assertIn('MOCK_COMPILER_BOUNDARY', result.stdout)

    def test_changed_patch_refused_without_source_mutation(self):
        self.patch.write_bytes(self.patch.read_bytes() + b'\n')
        self.refused()
        self.assertEqual(hashlib.sha256(self.table.read_bytes()).hexdigest(), BASE)

    def test_changed_source_refused(self):
        self.table.write_bytes(self.table.read_bytes() + b'\n')
        self.refused()

    def test_dirty_source_refused(self):
        self.env['MOCK_DIRTY'] = ' M forth/device/table.fs'
        self.refused()

    def test_wrong_commit_refused(self):
        self.env['MOCK_COMMIT'] = 'wrong'
        self.refused()

if __name__ == '__main__': unittest.main()
