import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
from contextlib import ExitStack
from unittest.mock import patch
import coldboot_fresh as c

class Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.disk = self.root / "installed disk.qcow2"
        h = bytearray(104)
        h[:4] = b"QFI\xfb"
        struct.pack_into(">I", h, 4, 3)
        struct.pack_into(">Q", h, 24, 8 * 1024**3)
        self.disk.write_bytes(h)
        self.cid = "a" * 64
        (self.root / "owned.cid").write_text(self.cid)

    def obj(self, running=True, owner="token"):
        return {"Id": self.cid, "Config": {"Labels": {"sun4u.coldboot.owner": owner}},
                "State": {"Running": running, "ExitCode": 0, "OOMKilled": False}}

    def test_existing_only_and_symlink_refusal(self):
        self.assertEqual(c.regular(str(self.disk)), self.disk)
        with self.assertRaises(FileNotFoundError): c.regular(str(self.root / "absent"))
        link = self.root / "link"
        link.symlink_to(self.disk)
        with self.assertRaises(ValueError): c.regular(str(link))

    def test_qcow_backing_dirty_size_refused(self):
        c.qcow_header(self.disk)
        original = self.disk.read_bytes()
        for offset in (8, 24, 72):
            h = bytearray(original)
            struct.pack_into(">Q", h, offset, 1)
            self.disk.write_bytes(h)
            with self.assertRaises(ValueError): c.qcow_header(self.disk)
        self.disk.write_bytes(b"not qcow")
        with self.assertRaises(ValueError): c.qcow_header(self.disk)

    def test_any_opener_refused(self):
        proc = self.root / "proc"
        fd = proc / "987654321" / "fd"
        fd.mkdir(parents=True)
        (fd / "7").symlink_to(self.disk)
        with self.assertRaisesRegex(ValueError, "disk open"): c.no_openers(self.disk, proc)
        (fd / "7").unlink()
        c.no_openers(self.disk, proc)

    def test_uninspectable_process_refused(self):
        proc = self.root / "proc"
        (proc / "987654321").mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, "visibility"): c.no_openers(self.disk, proc)

    def test_argv_fixed_pins_spaces_no_media(self):
        args = c.create_argv(self.disk, self.root / "firm ware", self.root / "q emu", self.root,
                             "token", "boot", "1:2:3")
        self.assertIn(f"type=bind,src={self.disk},dst=/installed.qcow2", args)
        self.assertIn(c.IMAGE, args)
        q = c.qemu_argv()
        self.assertIn("ide-hd,drive=installed0,bus=ide.0,unit=0", q)
        self.assertNotIn("-cdrom", q)
        self.assertNotIn("-snapshot", q)
        self.assertIn("file=/installed.qcow2,if=none,id=installed0,format=qcow2,file.locking=on", q)
        self.assertEqual(q[q.index("-m") + 1], "1088")
        self.assertEqual(q[q.index("-boot") + 1], "c")
        self.assertIn("cmd646-ide.x-b134-status-compat=on", q)
        script = args[-1]
        self.assertLess(script.index(c.QEMU), script.index("exec "))
        self.assertIn("/proc/sys/kernel/random/boot_id", script)
        self.assertIn("stat -c", script)

    def test_owner_mismatch_never_stops(self):
        with patch.object(c, "call", return_value=json.dumps([self.obj(owner="other")])) as call:
            with self.assertRaises(ValueError): c.stop_owned(self.root, "token")
        self.assertEqual(len(call.call_args_list), 1)

    def test_stop_verified_exact_cid(self):
        replies = [json.dumps([self.obj()]), "", json.dumps([self.obj(False)])]
        with patch.object(c, "call", side_effect=replies) as call:
            result = c.stop_owned(self.root, "token")
        self.assertTrue(result["stopped"])
        self.assertEqual(call.call_args_list[1].args[0][-1], self.cid)
        self.assertTrue((self.root / "owned.cid").exists())

    def test_failed_stop_not_silently_successful(self):
        replies = [json.dumps([self.obj()]), RuntimeError("stop failed"), json.dumps([self.obj()]),
                   "", json.dumps([self.obj(False)])]
        with patch.object(c, "call", side_effect=replies):
            result = c.stop_owned(self.root, "token")
        self.assertTrue(result["stopped"])
        self.assertTrue(result["errors"])

    def test_unresolved_stop_incomplete(self):
        replies = [json.dumps([self.obj()]), "", json.dumps([self.obj()]), "", json.dumps([self.obj()])]
        with patch.object(c, "call", side_effect=replies):
            self.assertFalse(c.stop_owned(self.root, "token")["stopped"])

    def test_missing_cid_no_name_fallback(self):
        (self.root / "owned.cid").unlink()
        with patch.object(c, "call") as call:
            self.assertEqual(c.stop_owned(self.root, "token"), {"created": False})
        call.assert_not_called()

    def test_invalid_cid_no_docker(self):
        (self.root / "owned.cid").write_text("unrelated-name")
        with patch.object(c, "call") as call:
            with self.assertRaises(ValueError): c.stop_owned(self.root, "token")
        call.assert_not_called()

    def test_host_refuses_mac_before_docker(self):
        with patch.object(c.sys, "platform", "darwin"):
            with self.assertRaises(ValueError): c.host_check()

    def run_main(self, *, bad_hash=False, session_error=None, marker_error=False):
        ev = self.root / "new evidence"
        fw, qemu = self.root / "firmware", self.root / "qemu"
        fw.write_bytes(b"firmware")
        qemu.write_bytes(b"binary")
        qemu.chmod(0o700)
        argv = ["coldboot.py", "--disk", str(self.disk), "--firmware", str(fw), "--qemu", str(qemu),
                "--evidence", str(ev), "--offline-clean-shutdown-confirmed", "--exclusive-host-confirmed"]
        original_write = Path.write_text
        def write(p, text, *args, **kwargs):
            if marker_error and p.name == "preflight.json": raise OSError("disk full")
            return original_write(p, text, *args, **kwargs)
        with ExitStack() as stack:
            for name in ("host_check", "no_openers"):
                stack.enter_context(patch.object(c, name))
            stack.enter_context(patch.object(c.sys, "argv", argv))
            stack.enter_context(patch.object(c.signal, "signal"))
            stack.enter_context(patch("builtins.print"))
            stack.enter_context(patch.object(Path, "write_text", write))
            stack.enter_context(patch.object(c, "digest", side_effect=["wrong" if bad_hash else c.FW, c.QEMU]))
            stack.enter_context(patch.object(Path, "read_text", autospec=True,
                side_effect=lambda p, *a, **k: "boot-id" if str(p) == "/proc/sys/kernel/random/boot_id" else p.open().read()))
            call = stack.enter_context(patch.object(c, "call", side_effect=["ext2/ext3", json.dumps([{"Id": c.IMAGE}]), self.cid]))
            stack.enter_context(patch.object(c, "owned", return_value=(self.cid, self.obj())))
            session = stack.enter_context(patch.object(c, "session", side_effect=session_error,
                                         return_value={"outcome": "UNVERIFIED_SESSION_END", "client_exit": 0}))
            stop = stack.enter_context(patch.object(c, "stop_owned", return_value={"created": False}))
            self.assertEqual(c.main(), 2)
            stop.assert_called_once()
        return json.loads((ev / "outcome.json").read_text()), call, session

    def test_bad_pin_never_creates_guest(self):
        result, call, session = self.run_main(bad_hash=True)
        self.assertEqual(result["outcome"], "ERROR_INCOMPLETE")
        self.assertEqual(call.call_count, 1)  # filesystem only
        session.assert_not_called()

    def test_evidence_failure_still_cleans_up(self):
        result, call, session = self.run_main(marker_error=True)
        self.assertEqual(result["outcome"], "ERROR_INCOMPLETE")
        self.assertEqual(call.call_count, 2)  # no create
        session.assert_not_called()

    def test_cancellation_still_cleans_up(self):
        result, _, _ = self.run_main(session_error=KeyboardInterrupt("signal"))
        self.assertEqual(result["outcome"], "CANCELLED_INCOMPLETE")

    def test_zero_exit_is_not_boot_pass(self):
        result, _, _ = self.run_main()
        self.assertEqual(result["outcome"], "UNVERIFIED_SESSION_END")

if __name__ == "__main__": unittest.main()
