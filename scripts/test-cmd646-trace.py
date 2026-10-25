#!/usr/bin/env python3
"""Host fixtures only: subprocess.run is mocked; no Docker/guest invocation."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC=importlib.util.spec_from_file_location("trace_helper",Path(__file__).with_name("cmd646-trace.py"))
m=importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(m)
CID="a"*64
GOOD="8@1792901686.223991:pci_cfg_read sabre-pci 00:00.0 @0x0 -> 0x108e\n"

class TraceTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix="trace fixture ")
        self.root=Path(self.tmp.name); self.calls=[]
        m.ERROR=False; m.STOP_REQUESTED=False
    def tearDown(self): self.tmp.cleanup()
    def fake(self,args,**kwargs):
        self.calls.append(args)
        self.assertEqual(args[-1],CID)
        self.assertEqual(kwargs["timeout"],10)
        body=json.dumps([{"Id":CID,"State":{"Running":False}}])
        return subprocess.CompletedProcess(args,0,body)
    def test_real_format_and_invalid(self):
        p=self.root/"cmd646.trace";p.write_text(GOOD)
        self.assertEqual(m.finish(self.root),0)
        p.write_text("8@1.0:pci_cfg_read malformed\n")
        self.assertEqual(m.finish(self.root),1)
    def test_missing_and_partial(self):
        self.assertEqual(m.finish(self.root),1)
        (self.root/"cmd646.trace").write_text(GOOD.rstrip())
        self.assertEqual(m.finish(self.root),1)
    def test_cap_overshoot_stops_exact_owner(self):
        (self.root/"cmd646.trace").write_text("x"*101)
        with patch.object(m,"CAP",100),patch.object(m.subprocess,"run",side_effect=self.fake):
            self.assertEqual(m.watch(self.root,CID),1)
        self.assertEqual(json.loads((self.root/"trace-incomplete.json").read_text())["overshoot_bytes"],1)
        self.assertTrue(any(x[1]=="stop" for x in self.calls))
    def test_deadline(self):
        with patch.object(m.time,"monotonic",side_effect=[0,2101]),patch.object(m.subprocess,"run",side_effect=self.fake):
            self.assertEqual(m.watch(self.root,CID),1)
        self.assertEqual(json.loads((self.root/"trace-incomplete.json").read_text())["reason"],"DEADLINE")
    def test_stop_nonzero_not_success(self):
        def failed(args,**kw):
            r=self.fake(args,**kw)
            if args[1]=="stop":r.returncode=1
            return r
        with patch.object(m.subprocess,"run",side_effect=failed):
            self.assertTrue(m.stop_owned(self.root,CID))
        self.assertTrue(m.ERROR)
    def test_stop_still_running_converges_once(self):
        def live(args,**kw):
            r=self.fake(args,**kw)
            r.stdout=json.dumps([{"Id":CID,"State":{"Running":True}}]);return r
        with patch.object(m.subprocess,"run",side_effect=live):
            self.assertFalse(m.stop_owned(self.root,CID))
        self.assertEqual(sum(x[1]=="kill" for x in self.calls),1)
        self.assertTrue(m.ERROR)
    def test_marker_and_log_write_failure_still_stops(self):
        (self.root/"cmd646.trace").write_text("x"*101)
        with patch.object(m,"CAP",100),patch.object(m.Path,"open",side_effect=OSError("disk full")),patch.object(m.subprocess,"run",side_effect=self.fake):
            self.assertEqual(m.watch(self.root,CID),1)
        self.assertTrue(any(x[1]=="stop" for x in self.calls))
        self.assertTrue(any(x[1]=="inspect" for x in self.calls))
        self.assertTrue(m.ERROR)
    def test_invalid_owner_no_docker(self):
        with patch.object(m.subprocess,"run",side_effect=AssertionError("must not execute")):
            self.assertFalse(m.stop_owned(self.root,"other-guest"))
    def test_error_retains_raw(self):
        (self.root/"cmd646.trace").write_text(GOOD)
        m.failure(self.root,"TIMEOUT")
        self.assertEqual(m.finish(self.root),1)
        self.assertEqual((self.root/"cmd646.trace").read_text(),GOOD)
    def test_inspect_timeout_bounded(self):
        def timeout(args,**kw):
            self.fake(args,**kw);raise subprocess.TimeoutExpired(args,10)
        with patch.object(m.subprocess,"run",side_effect=timeout):
            self.assertFalse(m.stop_owned(self.root,CID))
        self.assertEqual(len(self.calls),5)

if __name__=="__main__":unittest.main()
