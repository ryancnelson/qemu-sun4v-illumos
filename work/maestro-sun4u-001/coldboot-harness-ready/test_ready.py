"""Offline integration checks; imports frozen harness, never invokes Docker."""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
FROZEN = HERE.parent / "coldboot-harness"
sys.path.insert(0, str(FROZEN))
import coldboot
from test_coldboot import Tests as FrozenTests

class ReadyTests(unittest.TestCase):
    def test_frozen_bytes_and_patch(self):
        self.assertEqual(hashlib.sha256((FROZEN / "coldboot.py").read_bytes()).hexdigest(),
                         "9ae6db9926a4cd7fd1e8f1dc2e204fe5705cb5370018dae75821075bfc75697b")
        self.assertEqual(hashlib.sha256((HERE / "integration.patch").read_bytes()).hexdigest(),
                         "6faa0f0050d22d86ec9bdc5f85231b057e7a11a8f4d467ae4695d5ba457d7c8b")

    def test_template_cannot_be_a_launch(self):
        m = json.loads((HERE / "run142-manifest.template.json").read_text())
        self.assertIsNone(m["launch_argv"])
        self.assertIsNone(m["disk"]["canonical_host_path"])
        self.assertIsNone(m["disk"]["offline_sha256"])
        self.assertFalse(m["owner_launch_approval"])
        self.assertFalse(m["clean_shutdown_confirmed"])
        self.assertEqual(m["firmware"]["sha256"], coldboot.FW)
        self.assertEqual(m["qemu"]["sha256"], coldboot.QEMU)
        self.assertEqual(m["image"], coldboot.IMAGE)

    def test_missing_confirmations_fail_before_any_io(self):
        argv = ["coldboot.py", "--disk", "/PENDING", "--firmware", "/PENDING",
                "--qemu", "/PENDING", "--evidence", "/PENDING"]
        for extra in ([], ["--offline-clean-shutdown-confirmed"], ["--exclusive-host-confirmed"]):
            with patch.object(sys, "argv", argv + extra), patch.object(coldboot, "call") as call, \
                 patch.object(Path, "mkdir") as mkdir, contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    coldboot.main()
                self.assertEqual(error.exception.code, 2)
                call.assert_not_called()
                mkdir.assert_not_called()

    def test_workflow_transport_and_disk_only(self):
        args = coldboot.qemu_argv()
        self.assertEqual(args[args.index("-serial") + 1], "stdio")
        self.assertEqual(args[args.index("-monitor") + 1], "none")
        self.assertNotIn("-cdrom", args)
        self.assertNotIn("-chardev", args)
        self.assertNotIn("-snapshot", args)
        self.assertEqual(args[args.index("-global") + 1], "cmd646-ide.x-b134-status-compat=on")

if __name__ == "__main__":
    unittest.main()
