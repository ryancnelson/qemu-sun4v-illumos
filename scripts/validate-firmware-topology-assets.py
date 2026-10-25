#!/usr/bin/env python3
"""Pinned offline artifact/real-C validation. No firmware execution or Docker."""
import hashlib,json,os,signal,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MANIFEST_SHA='612f3b8b1940128c3a3e2380a67dded0f59f51784905cd41ea3f702925f78ea8'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(args,cwd,env):
 p=subprocess.Popen(args,cwd=cwd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,start_new_session=True)
 try:
  out,_=p.communicate(timeout=90)
 except subprocess.TimeoutExpired:
  os.killpg(p.pid,signal.SIGKILL);out,_=p.communicate()
  print(out);raise RuntimeError('90-second offline test process-group limit')
 print(out,end='')
 if p.returncode:raise RuntimeError('offline command failed: '+str(args))
 return out
def main():
 manifest=ROOT/'tests/firmware-topology/manifest.json'
 if sha(manifest)!=MANIFEST_SHA:raise RuntimeError('manifest pin mismatch')
 for name,digest in json.loads(manifest.read_text()).items():
  p=ROOT/name
  if p.is_symlink() or not p.is_file() or sha(p)!=digest:raise RuntimeError('asset drift: '+name)
 base=ROOT/'work/maestro-sun4u-001/ata-dad-compatible-kestrel/candidate/drivers/ide.c'
 if sha(base)!='54d8f54b0db401a173e91da7837c94875ad8f4f680a9541764765cc61f11bfa2':raise RuntimeError('existing dad fixture drift')
 env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1')
 # Constructor fixtures retain emulated hardware allocations for process lifetime.
 # Disable only leak reporting; address/undefined checks remain enabled.
 env['ASAN_OPTIONS']='detect_leaks=0'
 with tempfile.TemporaryDirectory(prefix='firmware topology offline ') as tmp:
  d=Path(tmp)
  mappings={
   'ide.c':'artifacts/firmware132-dad-topology-kestrel/r1-failed/ide.c',
   'test_composed.py':'tests/firmware-topology/test_composed.py',
   'r2/ide.c':'tests/firmware-topology/r2/ide.c',
   'r2/bindings.h':'tests/firmware-topology/r2/bindings.h',
   'r2/test_bindings.py':'tests/firmware-topology/r2/test_bindings.py',
   'r2/test_composed.py':'tests/firmware-topology/r2/test_composed.py'}
  for dest,src in mappings.items():
   p=d/dest;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((ROOT/src).read_bytes())
  patchroot=d/'apply';(patchroot/'drivers').mkdir(parents=True)
  (patchroot/'drivers/ide.c').write_bytes(base.read_bytes())
  patch=ROOT/'tests/firmware-topology/r2/topology-on-dad.patch'
  run(['git','apply','--check',str(patch)],patchroot,env)
  run(['git','apply',str(patch)],patchroot,env)
  if (patchroot/'drivers/ide.c').read_bytes()!=(d/'r2/ide.c').read_bytes():raise RuntimeError('composition mismatch')
  if sorted(str(p.relative_to(patchroot)) for p in patchroot.rglob('*') if p.is_file())!=['drivers/ide.c']:raise RuntimeError('unexpected patch target')
  binding=run([sys.executable,str(d/'r2/test_bindings.py')],d,env)
  if 'R1 expected compile FAIL' not in binding or 'R2 actual bindings macros/table/runtime metadata PASS' not in binding:raise RuntimeError('missing real macro proof')
  constructor=run([sys.executable,str(d/'r2/test_composed.py'),str(d/'r2/ide.c')],d,env)
  if sum('PASS real constructor:' in l for l in constructor.splitlines())!=64:raise RuntimeError('expected64 constructor passes')
 print('CI_RESULT=firmware_topology_assetvalidation')
 print('NATIVE_TOPOLOGY_BOOT=NOT_TESTED')
 return 0
if __name__=='__main__':
 try:sys.exit(main())
 except Exception as e:
  print('CI_RESULT=firmware_topology_assetvalidation_failed',file=sys.stderr)
  print(str(e),file=sys.stderr);sys.exit(1)
