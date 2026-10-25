#!/usr/bin/env python3
"""Execute real recover.sh with private path substitutions and command fixtures.
No guest/network; fixture shell is separate, production script has no test bypass.
"""
import json, os, pathlib, subprocess, tempfile, unittest

HERE = pathlib.Path(__file__).resolve().parent
MOCK = r'''#!/usr/bin/env python3
import json,os,sys,pathlib
p=pathlib.Path(os.environ["FIXTURE"])
s=json.loads((p/"state.json").read_text())
cmd=pathlib.Path(sys.argv[0]).name; a=sys.argv[1:]
with (p/"calls.jsonl").open("a") as f: f.write(json.dumps([cmd]+a)+"\n")
def out(x): print(x); sys.exit(0)
def save(): (p/"state.json").write_text(json.dumps(s))
if cmd in ("awk","nawk"):
 if cmd=="awk" and s.get("legacy_awk") and any("sub(" in v or "tolower(" in v for v in a):
  print("fixture Solaris oldawk: sub/tolower unsupported",file=sys.stderr);sys.exit(2)
 os.execv("/usr/bin/awk",["/usr/bin/awk"]+a)
if cmd=="id": out("0")
if cmd=="uname": out({"-s":"SunOS","-r":"5.11","-v":s.get("version","snv_134"),"-m":"sun4u"}[a[0]])
if cmd=="digest":
 if s.get("digest_status"): sys.exit(s["digest_status"])
 out(s.get("digest","cfac5c32f4dcdb4da0ea1c774d4f0cf6f4910bb5246dc820b95de4970dbbe004"))
if cmd=="openssl":
 print("fixture provider warning",file=sys.stderr)
 value=s.get("openssl_output","SHA256("+a[-1]+")= "+s.get("openssl_hash","cfac5c32f4dcdb4da0ea1c774d4f0cf6f4910bb5246dc820b95de4970dbbe004"))
 print(value)
 if s.get("openssl_duplicate"): print(value)
 sys.exit(s.get("openssl_status",0))
if cmd=="zfs":
 if a[0]=="get": out("yes")
 if s.get("no_snapshot"): sys.exit(1)
 out(a[-1])
if cmd=="getent": out("niagara:x:101:10::/home/niagara:/usr/bin/bash")
if cmd=="ls":
 if a[-1].endswith("/export/home/niagara"): out("drwxr-xr-x 2 101 10 0 Oct 25 00:00 niagara")
 out("-rw-r--r-- 1 0 0 0 Oct 25 00:00 auto_home")
if cmd=="svccfg":
 if a[0]=="validate": sys.exit(0)
 if a[0]=="export":
  if s.get("export_fail"): sys.exit(1)
  out("<fixture-export/>")
 if a[-1]=="last-import": s["current"]=True;save();sys.exit(0)
 if a[-1]=="refresh":
  if not s.get("stale"): s["running"]=s.get("current",True)
  save();sys.exit(0)
if cmd=="svcadm":
 if a[0]=="enable": s["enabled"]=True
 if a[0]=="disable": s["media"]=False
 save();sys.exit(0)
if cmd=="svcprop":
 svc=a[-1]; prop=a[a.index("-p")+1]
 if prop=="restarter/state": out("online" if s.get("active_installer") else "disabled")
 if prop=="general/enabled":
  if svc.endswith("root:default"): out("true" if s.get("enabled",True) else "false")
  if "console-login" in svc: out("true")
  out("true" if s.get("media",False) else "false")
 view=a[a.index("-s")+1] if "-s" in a else "current"
 if not s.get(view,True): sys.exit(1)
 out({"start/exec":"/lib/svc/method/fs-root","start/timeout_seconds":"300","stop/exec":":true","stop/timeout_seconds":"0","startd/duration":"transient"}[prop])
if cmd=="automount": sys.exit(s.get("automount_status",0))
if cmd=="sleep": sys.exit(0)
raise SystemExit("unexpected mock call "+repr([cmd]+a))
'''
class Recovery(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
  self.p=pathlib.Path(self.tmp.name); self.bin=self.p/"bin";self.bin.mkdir()
  self.state={}
  self.map=self.p/"etc/auto_home";self.map.parent.mkdir()
  self.original="# retain comment\nniagara localhost:/export/home/&\nother remote:/keep\n+auto_home\n"
  self.map.write_text(self.original);self.map.chmod(0o640)
  (self.p/"etc/mnttab").write_text("rpool/ROOT/opensolaris / zfs rw 0\nrpool/export/home /export/home zfs rw 0\n")
  for d in ["var/tmp","export/home/niagara","var/svc/manifest/system/filesystem","lib/svc/method"]:
   (self.p/d).mkdir(parents=True,exist_ok=True)
  (self.p/"var/svc/manifest/system/filesystem/root-fs.xml").write_text("<fixture/>")
  method=self.p/"lib/svc/method/fs-root";method.write_text("fixture");method.chmod(0o755)
  dispatcher=self.bin/"dispatcher";dispatcher.write_text(MOCK);dispatcher.chmod(0o755)
  for c in ["awk","nawk","id","uname","digest","openssl","zfs","getent","ls","svccfg","svcadm","svcprop","automount","sleep"]:
   (self.bin/c).symlink_to(dispatcher)
  text=(HERE/"recover.sh").read_text()
  text=text.replace("PATH=/usr/sbin:/usr/bin:/sbin","PATH="+str(self.bin)+":/usr/bin:/bin")
  # Only filesystem access paths are relocated; semantic expected strings remain exact.
  import re
  paths=["/var/svc/manifest/system/filesystem/root-fs.xml","/etc/auto_home","/etc/mnttab","/var/tmp"]
  text=re.sub("|".join(map(re.escape,paths)),lambda m:str(self.p)+m.group(),text)
  text=text.replace("[ -x /lib/svc/method/fs-root ]","[ -x "+str(method)+" ]")
  text=text.replace("for p in /export /export/home /export/home/niagara;", "for p in "+" ".join(str(self.p/x) for x in ["export","export/home","export/home/niagara"])+";")
  text=text.replace("ls -ldn /export/home/niagara","ls -ldn "+str(self.p/"export/home/niagara"))
  text=text.replace("/usr/sbin/automount","automount")
  text=text.replace("/usr/bin/nawk",str(self.bin/"nawk"))
  self.script=self.p/"candidate.sh";self.script.write_text(text)
  self.evidence=self.p/"var/tmp/postinstall-recovery-test"
 def run_script(self,apply=False):
  (self.p/"state.json").write_text(json.dumps(self.state))
  args=["bash",str(self.script)]
  if apply: args+=["--apply","--snapshot","rpool/ROOT/opensolaris@test","--evidence",str(self.evidence)]
  env=dict(os.environ,FIXTURE=str(self.p))
  result=subprocess.run(args,env=env,text=True,capture_output=True,timeout=15)
  self.calls=[json.loads(x) for x in (self.p/"calls.jsonl").read_text().splitlines()] if (self.p/"calls.jsonl").exists() else []
  return result
 def mutations(self):
  return [x for x in self.calls if x[0] in ("svcadm","automount") or (x[0]=="svccfg" and x[-1] in ("refresh","last-import"))]
 def test_dry_run_no_mutations(self):
  self.state={"current":False}
  r=self.run_script();self.assertEqual(r.returncode,0,r.stderr)
  self.assertFalse(self.mutations());self.assertEqual(self.map.read_text(),self.original);self.assertFalse(self.evidence.exists())
 def test_repair_actual_shell_preserves_other_lines_mode(self):
  (self.p/"export/home/niagara/user-data").write_text("preserve me")
  self.state={"current":False,"running":False,"enabled":False}
  r=self.run_script(True);self.assertEqual(r.returncode,0,r.stderr+r.stdout)
  self.assertEqual(self.map.read_text(),self.original.replace("niagara localhost:/export/home/&","niagara -fstype=lofs :/export/home/niagara"))
  self.assertEqual(self.map.stat().st_mode & 0o777,0o640)
  self.assertEqual((self.evidence/"auto_home.before").read_text(),self.original)
  self.assertTrue(any(x[-1]=="last-import" for x in self.mutations()))
  self.assertIn(["automount"],self.calls)
  self.assertFalse(pathlib.Path(str(self.map)+".postinstall-recovery.pending").exists())
  self.assertEqual((self.p/"export/home/niagara/user-data").read_text(),"preserve me")
  self.assertEqual((self.evidence/"script-exit-status").read_text(),"0\n")
 def test_already_recovered_no_revert_or_automount(self):
  self.map.write_text(self.original.replace("niagara localhost:/export/home/&","niagara -fstype=lofs :/export/home/niagara"))
  self.state={"last-import":False}
  r=self.run_script(True);self.assertEqual(r.returncode,0,r.stderr)
  self.assertNotIn(["automount"],self.calls)
  self.assertFalse(any(x[-1]=="last-import" for x in self.mutations()))
 def test_missing_needed_snapshot_refuses(self):
  self.state={"current":False,"last-import":False}
  self.assertNotEqual(self.run_script(True).returncode,0);self.assertFalse(self.mutations())
 def test_wrong_version_or_manifest_refuses(self):
  for state in [{"version":"snv_135"},{"digest":"bad"}]:
   self.state=state
   self.assertNotEqual(self.run_script(True).returncode,0);self.assertFalse(self.mutations())
 def test_missing_backing_mount_refuses(self):
  (self.p/"etc/mnttab").write_text("rpool/ROOT/opensolaris / zfs rw 0\n")
  self.assertNotEqual(self.run_script(True).returncode,0);self.assertFalse(self.mutations())
 def test_active_installer_refuses(self):
  self.state={"active_installer":True}
  self.assertNotEqual(self.run_script(True).returncode,0);self.assertFalse(self.mutations())
 def test_absent_rollback_refuses(self):
  self.state={"no_snapshot":True}
  self.assertNotEqual(self.run_script(True).returncode,0);self.assertFalse(self.mutations())
 def test_export_failure_before_mutation(self):
  self.state={"export_fail":True,"current":False}
  self.assertNotEqual(self.run_script(True).returncode,0);self.assertFalse(self.mutations());self.assertEqual(self.map.read_text(),self.original)
 def test_stale_running_stops_before_map(self):
  self.state={"current":False,"running":False,"stale":True}
  self.assertNotEqual(self.run_script(True).returncode,0);self.assertEqual(self.map.read_text(),self.original)
  self.assertTrue((self.evidence/"root-before.xml").exists())
 def test_duplicate_or_unknown_map_refuses(self):
  for content in [self.original+"niagara localhost:/export/home/&\n",self.original.replace("localhost:","other:")]:
   self.map.write_text(content)
   self.assertNotEqual(self.run_script(True).returncode,0);self.assertFalse(self.mutations())
 def test_symlink_map_refuses(self):
  self.map.unlink();self.map.symlink_to(self.p/"unrelated")
  self.assertNotEqual(self.run_script(True).returncode,0);self.assertFalse(self.mutations())
 def test_existing_evidence_refuses(self):
  self.evidence.mkdir();(self.evidence/"keep").write_text("untouched")
  self.assertNotEqual(self.run_script(True).returncode,0);self.assertFalse(self.mutations());self.assertEqual((self.evidence/"keep").read_text(),"untouched")
 def test_automount_failure_retry_fails_closed(self):
  self.state={"automount_status":7}
  first=self.run_script(True)
  self.assertEqual(first.returncode,7,first.stderr)
  self.assertIn("-fstype=lofs",self.map.read_text())
  self.assertEqual((self.evidence/"script-exit-status").read_text(),"7\n")
  self.state={}
  self.evidence=self.p/"var/tmp/postinstall-recovery-retry"
  (self.p/"calls.jsonl").write_text("")
  retry=self.run_script(True)
  print("automount failure: first=%d retry=%d; retry automount calls=%d" % (first.returncode,retry.returncode,self.calls.count(["automount"])))
  self.assertNotEqual(retry.returncode,0,"retry falsely reports success after unreconciled map change")
  self.assertIn("pending",retry.stderr)
  self.assertFalse(self.mutations())
  self.assertFalse(self.evidence.exists())
  pending=pathlib.Path(str(self.map)+".postinstall-recovery.pending")
  self.assertTrue(pending.is_file())
  self.assertIn("postinstall-recovery-test",pending.read_text())
 def test_preexisting_pending_not_removed(self):
  pending=pathlib.Path(str(self.map)+".postinstall-recovery.pending")
  pending.write_text("owner evidence\n")
  r=self.run_script()
  self.assertNotEqual(r.returncode,0)
  self.assertFalse(self.mutations())
  self.assertEqual(pending.read_text(),"owner evidence\n")
 def test_failed_digest_uses_verified_openssl(self):
  self.state={"digest_status":1}
  r=self.run_script()
  self.assertEqual(r.returncode,0,r.stderr)
  self.assertTrue(any(c[0]=="openssl" for c in self.calls))
  self.assertFalse(self.mutations())
 def test_successful_digest_never_uses_fallback(self):
  r=self.run_script()
  self.assertEqual(r.returncode,0,r.stderr)
  self.assertFalse(any(c[0]=="openssl" for c in self.calls))
 def test_openssl_invalid_outputs_fail_closed(self):
  pin="cfac5c32f4dcdb4da0ea1c774d4f0cf6f4910bb5246dc820b95de4970dbbe004"
  cases=[{"openssl_output":""},{"openssl_output":"not a digest"},
   {"openssl_output":pin},{"openssl_output":"SHA256(wrong-file)= "+pin},
   {"openssl_duplicate":True},{"openssl_status":7},
   {"openssl_hash":"0"*64}]
  for case in cases:
   with self.subTest(case=case):
    self.state=dict(case,digest_status=1)
    (self.p/"calls.jsonl").write_text("")
    r=self.run_script()
    self.assertNotEqual(r.returncode,0)
    self.assertFalse(self.mutations())
 def test_successful_bad_digest_refuses_without_fallback(self):
  for raw in ["", "bad", "0"*64, "a"*64+"\\n"+"b"*64]:
   with self.subTest(raw=raw):
    self.state={"digest":raw}
    (self.p/"calls.jsonl").write_text("")
    r=self.run_script()
    self.assertNotEqual(r.returncode,0)
    self.assertFalse(any(c[0]=="openssl" for c in self.calls))
    self.assertFalse(self.mutations())
 def test_solaris_oldawk_requires_explicit_nawk(self):
  self.state={"legacy_awk":True,"digest_status":1}
  r=self.run_script(True)
  self.assertEqual(r.returncode,0,r.stderr)
  self.assertFalse(any(c[0]=="awk" for c in self.calls))
  self.assertGreaterEqual(sum(c[0]=="nawk" for c in self.calls),8)
  self.assertIn("-fstype=lofs",self.map.read_text())
if __name__=="__main__": unittest.main(verbosity=2)
