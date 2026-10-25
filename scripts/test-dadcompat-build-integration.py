"""Real patch/application checks; run only recipe pre-build prefix, never compile.
DADCOMPAT_TEST_SOURCE must be a pristine archive of af97fd7 (no .git).
Git commit guard is mocked for the locally committed archive; git status/apply
and patch/SHA checks are real. No real build tools or firmware are invoked.
"""
import hashlib, os, shutil, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=Path(os.environ['DADCOMPAT_TEST_SOURCE'])
BASE='60ac3a0d1aa22d8b87ffbde695b96ba8202309a4c6b3ee0aeb1189362edce654'
FIXED='54d8f54b0db401a173e91da7837c94875ad8f4f680a9541764765cc61f11bfa2'
PIN='af97fd7af5e7c18f591a7b987291d3db4ffb28b5'
REAL_GIT=shutil.which('git')
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def snapshot(p):return {str(f.relative_to(p)):digest(f) for f in p.rglob('*') if f.is_file() and '.git' not in f.relative_to(p).parts}
class Tests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory(prefix='dad recipe ')
  self.addCleanup(self.tmp.cleanup)
  self.dir=Path(self.tmp.name);self.project=self.dir/'project';self.src=self.dir/'source space'
  shutil.copytree(SOURCE,self.src)
  self.assertEqual(digest(self.src/'drivers/ide.c'),BASE)
  self.project.mkdir();(self.project/'scripts').mkdir()
  shutil.copytree(ROOT/'patches',self.project/'patches')
  # copytree preserves frozen handoff modes; mutate only disposable copies.
  for name in ('0002-sun4u-solaris-device-paths.patch',
               '0004-fcode-64bit-token-slots.patch',
               '0005-sparc64-ata-dad-compatible.patch'):
   copied=self.project/'patches/openbios'/name
   copied.chmod(copied.stat().st_mode | 0o200)
  recipe=Path(os.environ.get('DADCOMPAT_TEST_RECIPE', ROOT/'scripts/build-openbios-sun4u-solaris.sh')).read_text()
  marker='\n(\n    cd "$source_dir"'
  self.assertEqual(recipe.count(marker),1)
  (self.project/'scripts/run.sh').write_text(recipe.split(marker)[0]+'\necho PREBUILD_PASS\nexit 86\n')
  for cmd in [['init','-q'],['add','.'],['-c','user.name=fixture','-c','user.email=fixture.invalid','commit','-qm','exact upstream archive']]:
   subprocess.run([REAL_GIT,'-C',str(self.src)]+cmd,check=True,capture_output=True)
  self.tools=self.dir/'tools';self.tools.mkdir()
  self.stub('git',"""if [ "$3" = rev-parse ] && [ "$4" = HEAD ]; then
 echo "${MOCK_COMMIT:-af97fd7af5e7c18f591a7b987291d3db4ffb28b5}"; exit 0
fi
"$REAL_GIT" "$@"
rc=$?
if [ "$rc" = 0 ] && [ "${CORRUPT_FINAL:-}" = 1 ] && [ "$3" = apply ] && [ "$4" != --check ]; then
 case "$4" in *0005*) printf '\\n' >> "$2/drivers/ide.c";; esac
fi
exit "$rc"
""")
  for t in ('make','xsltproc','toke','sparc64-linux-gnu-gcc','sparc64-linux-gnu-objdump'):
   self.stub(t,'echo UNEXPECTED_BUILD_TOOL >&2; exit 99')
  self.env=dict(os.environ,PATH=str(self.tools)+os.pathsep+os.environ['PATH'],REAL_GIT=REAL_GIT)
  for n in ('CORRUPT_FINAL','MOCK_COMMIT'):self.env.pop(n,None)
  self.before=snapshot(self.src)
 def stub(self,n,s):
  p=self.tools/n;p.write_text('#!/bin/sh\n'+s);p.chmod(0o755)
 def run_recipe(self):
  return subprocess.run(['bash',str(self.project/'scripts/run.sh'),str(self.src),str(self.dir/'out')],env=self.env,text=True,capture_output=True,timeout=30)
 def refused(self,unchanged=False):
  r=self.run_recipe();self.assertNotIn(r.returncode,(0,86),r.stdout+r.stderr)
  self.assertNotIn('PREBUILD_PASS',r.stdout);self.assertNotIn('UNEXPECTED_BUILD_TOOL',r.stderr)
  if unchanged:self.assertEqual(snapshot(self.src),self.before)
 def test_exact_real_application_and_only_expected_files(self):
  r=self.run_recipe();self.assertEqual(r.returncode,86,r.stdout+r.stderr)
  self.assertEqual(digest(self.src/'drivers/ide.c'),FIXED)
  self.assertEqual(digest(self.src/'forth/device/table.fs'),'cef7bb8cfe39a7c0e27dcad8568b6890da7837a936063b81cf997687804f46c2')
  after=snapshot(self.src)
  self.assertEqual(set(after),set(self.before))
  changed={p for p in after if after[p]!=self.before[p]}
  self.assertEqual(changed,{'config/scripts/switch-arch','arch/sparc64/tree.fs','drivers/pci.c','arch/sparc64/ofmem_sparc64.c','include/libopenbios/ofmem.h','libopenbios/ofmem_common.c','forth/device/table.fs','drivers/ide.c'})
 def test_wrong_dad_patch_refused_before_any_mutation(self):
  p=self.project/'patches/openbios/0005-sparc64-ata-dad-compatible.patch';p.write_bytes(p.read_bytes()+b'\n')
  self.refused(True)
 def test_wrong_base_refused_before_any_mutation(self):
  p=self.src/'drivers/ide.c';p.write_bytes(p.read_bytes()+b'\n')
  subprocess.run([REAL_GIT,'-C',str(self.src),'add','.'],check=True)
  subprocess.run([REAL_GIT,'-C',str(self.src),'-c','user.name=fixture','-c','user.email=fixture.invalid','commit','-qm','drift'],check=True)
  self.before=snapshot(self.src);self.refused(True)
 def test_multi_file_patch_tamper_refused(self):
  p=self.project/'patches/openbios/0005-sparc64-ata-dad-compatible.patch'
  p.write_bytes(p.read_bytes()+b'--- a/README\n+++ b/README\n@@ -1 +1 @@\n-x\n+y\n')
  self.refused(True)
 def test_dirty_worktree_refused(self):
  (self.src/'unexpected').write_text('x');self.before=snapshot(self.src);self.refused(True)
 def test_wrong_commit_refused(self):
  self.env['MOCK_COMMIT']='wrong';self.refused(True)
 def test_prior_patch_dad_drift_refused_before_dad_application(self):
  p=self.project/'patches/openbios/0002-sun4u-solaris-device-paths.patch'
  import difflib
  old=(self.src/'drivers/ide.c').read_text();new=old.replace('/*','/* drift',1)
  p.write_text(p.read_text()+''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/drivers/ide.c',tofile='b/drivers/ide.c')))
  self.refused();self.assertEqual((self.src/'drivers/ide.c').read_text(),new)
 def test_wrong_final_hash_refused(self):
  self.env['CORRUPT_FINAL']='1';self.refused()
 def test_token_patch_drift_still_refused(self):
  p=self.project/'patches/openbios/0004-fcode-64bit-token-slots.patch';p.write_bytes(p.read_bytes()+b'\n')
  self.refused(True)
if __name__=='__main__':unittest.main()
