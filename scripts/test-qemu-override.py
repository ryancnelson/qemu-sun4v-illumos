#!/usr/bin/env python3
"""Execute the harness preflight against local command fixtures, never Docker."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE=Path(__file__).parent
PIN="902dc13a3dbc23a6057cd8f98109632fcbf11ad80a2ad6e0934f48b8b8305d40"
IMAGE="sha256:56dac302ff0a10a576bd39f9df942e3833b759c5eb1b525ebd86f548f7bf022f"
ISO="c1ac3fb8bae47d4b8421d7a5506a33b05b1189c9ba731e0e560f78b140f228e0"

class Override(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix="override ' space ")
        self.root=Path(self.tmp.name);self.bin=self.root/"bin";self.bin.mkdir()
        self.binary=self.root/"rebuilt qemu $ literal";self.binary.write_bytes(b"fixture, never executed\n");self.binary.chmod(0o755)
        self.sha=hashlib.sha256(self.binary.read_bytes()).hexdigest()
        self.fw=self.root/"firmware";self.fw.write_text("fixture")
        self.iso=self.root/"iso";self.iso.write_text("fixture")
        self.env=dict(os.environ,PATH=str(self.bin)+":"+os.environ["PATH"],
                      B134_ISO=str(self.iso),SUN4U_TRACE_CMD646="0",
                      SUN4U_INSTALL_TARGET_GIB="0",SUN4U_KEEP_GUEST="0",SUN4U_KEEP_MAINTENANCE="0",
                      CALLS=str(self.root/"calls"),INSIDE=self.sha,IMAGE=IMAGE,PIN=PIN,ISO=ISO)
        for k in ["SUN4U_QEMU_BINARY","SUN4U_QEMU_SHA256","SUN4U_CMD646_B134_COMPAT"]:self.env.pop(k,None)
        self.stub("docker",'''import os,sys,json
a=sys.argv[1:]
with open(os.environ["CALLS"],"a") as f:f.write(json.dumps(a)+"\\n")
if a[:2]==["image","inspect"]:print(os.environ["IMAGE"])
elif "-d" in a:sys.exit(95) # boundary: DO NOT create any guest
elif "/usr/bin/sha256sum" in a:print((os.environ["INSIDE"] if "--mount" in a else os.environ["PIN"])+"  /usr/bin/qemu-system-sparc64")
elif "--version" in a:
 print("fixture version")
 sys.exit(int(os.environ.get("VERSION_EXIT","0")))
elif "cmd646-ide,help" in a:
 print(os.environ.get("PROPERTIES","  x-b134-status-compat=<bool> -  (default: false)"))
 sys.exit(int(os.environ.get("PROPERTY_EXIT","0")))
else:sys.exit(96)
''')
        self.stub("sha256sum",'''import os,sys,hashlib
if sys.argv[1:]==["-c","-"]:
 assert sys.stdin.read().startswith(os.environ["ISO"])
 print("fixture ISO: OK")
else:print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()+"  -")
''')
        self.stub("timeout",'''import os,sys
assert sys.argv[1:4]==["-k","5","30"]
os.execvp(sys.argv[4],sys.argv[4:])
''')
        self.stub("socat","raise SystemExit(99)\n")
    def stub(self,name,body):
        p=self.bin/name;p.write_text("#!/usr/bin/env python3\n"+body);p.chmod(0o755)
    def tearDown(self):self.tmp.cleanup()
    def run_harness(self,on=True,**env):
        e=dict(self.env)
        if on:e.update(SUN4U_QEMU_BINARY=str(self.binary),SUN4U_QEMU_SHA256=self.sha)
        e.update(env)
        result=subprocess.run(["bash",str(HERE/"ci-openbios-sun4u-boot.sh"),str(self.fw),str(self.root/"run dir")],env=e,text=True,capture_output=True)
        log=self.root/"calls"
        calls=[json.loads(x) for x in log.read_text().splitlines()] if log.exists() else []
        return result,calls
    def assert_no_guest(self,result,calls):
        self.assertNotEqual(result.returncode,0);self.assertFalse(any("-d" in x for x in calls))
    def test_off_original_hash_and_no_mount(self):
        r,c=self.run_harness(False)
        self.assertEqual(r.returncode,95,r.stderr)
        self.assertEqual(c[1],["run","--rm","--entrypoint","/usr/bin/sha256sum","solaris9-sun4m-workbench:arm64","/usr/bin/qemu-system-sparc64"])
        self.assertFalse(any("dst=/usr/bin/qemu-system-sparc64" in a for x in c for a in x))
    def test_spaces_same_readonly_mount_three_calls(self):
        r,c=self.run_harness();self.assertEqual(r.returncode,95,r.stderr)
        mount="type=bind,src="+str(self.binary)+",dst=/usr/bin/qemu-system-sparc64,readonly"
        self.assertEqual(sum(mount in x for x in c),3)
        self.assertIn("--version",c[2]);self.assertIn("-d",c[3])
    def test_missing_hash(self):
        self.assert_no_guest(*self.run_harness(SUN4U_QEMU_SHA256=""))
    def test_invalid_hash(self):
        self.assert_no_guest(*self.run_harness(SUN4U_QEMU_SHA256="not hex"))
    def test_wrong_host_hash(self):
        self.assert_no_guest(*self.run_harness(SUN4U_QEMU_SHA256="0"*64))
    def test_missing_path(self):
        self.assert_no_guest(*self.run_harness(SUN4U_QEMU_BINARY=str(self.root/"absent")))
    def test_not_executable(self):
        self.binary.chmod(0o644);self.assert_no_guest(*self.run_harness())
    def test_directory(self):
        self.assert_no_guest(*self.run_harness(SUN4U_QEMU_BINARY=str(self.root)))
    def test_inside_hash_mismatch(self):
        r,c=self.run_harness(INSIDE="0"*64);self.assert_no_guest(r,c)
        self.assertFalse(any("--version" in x for x in c))
    def test_loader_failure(self):
        self.assert_no_guest(*self.run_harness(VERSION_EXIT="127"))
    def test_hash_without_path(self):
        self.assert_no_guest(*self.run_harness(SUN4U_QEMU_BINARY=""))
    def test_image_still_pinned(self):
        r,c=self.run_harness(IMAGE="wrong");self.assert_no_guest(r,c)
        self.assertEqual(len(c),1)
    def test_compat_default_no_flag(self):
        r,c=self.run_harness();self.assertEqual(r.returncode,95,r.stderr)
        self.assertFalse(any("-global" in x or "cmd646-ide,help" in x for x in c))
    def test_compat_explicit_zero_no_flag(self):
        r,c=self.run_harness(SUN4U_CMD646_B134_COMPAT="0");self.assertEqual(r.returncode,95,r.stderr)
        self.assertFalse(any("-global" in x or "cmd646-ide,help" in x for x in c))
    def test_compat_invalid(self):
        for flag in ["yes","2","-global other=on"]:
            with self.subTest(flag=flag):self.assert_no_guest(*self.run_harness(SUN4U_CMD646_B134_COMPAT=flag))
    def test_compat_requires_override(self):
        self.assert_no_guest(*self.run_harness(False,SUN4U_CMD646_B134_COMPAT="1"))
    def test_compat_exact_flag_and_property_probe(self):
        r,c=self.run_harness(SUN4U_CMD646_B134_COMPAT="1");self.assertEqual(r.returncode,95,r.stderr)
        guest=next(x for x in c if "-d" in x)
        i=guest.index("-global");self.assertEqual(guest[i+1],"cmd646-ide.x-b134-status-compat=on")
        self.assertEqual(guest.count("-global"),1)
        self.assertEqual(sum("cmd646-ide,help" in x for x in c),1)
    def test_compat_property_absent(self):
        self.assert_no_guest(*self.run_harness(SUN4U_CMD646_B134_COMPAT="1",PROPERTIES="other=<bool>"))
    def test_compat_property_probe_failure(self):
        self.assert_no_guest(*self.run_harness(SUN4U_CMD646_B134_COMPAT="1",PROPERTY_EXIT="1"))

if __name__=="__main__":unittest.main()
