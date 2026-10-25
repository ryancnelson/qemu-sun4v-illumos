import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from contextlib import ExitStack
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
import retention as r

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("candidate", HERE.parents[1] / "scripts/coldboot-dad-retained.py")
c = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = c
spec.loader.exec_module(c)


class Retention(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.cid = "a" * 64
        self.token = "b" * 32
        self.obj = {"Id": self.cid, "Image": c.IMAGE,
                    "Config": {"Labels": {"sun4u.coldboot.owner": self.token}, "OpenStdin": False, "StdinOnce": False,
                               "AttachStdin": False, "Tty": False},
                    "HostConfig": {"LogConfig": {"Type": "json-file", "Config": {"max-size": "64m", "max-file": "1"}}},
                    "Mounts": [{"Source": "/disk", "Destination": "/installed.qcow2"}],
                    "State": {"Running": False, "ExitCode": 0, "OOMKilled": False}}
        self.read = Path.read_text
        self.addCleanup(patch.stopall)
        patch.object(Path, "read_text", lambda p, *a, **kw: "boot" if str(p) == "/proc/sys/kernel/random/boot_id" else self.read(p, *a, **kw)).start()

    def prepare(self):
        (self.root / "owned.cid").write_text(self.cid)
        (self.root / "preflight.json").write_text("{}")
        (self.root / "serial.log").write_text("firmware console\n")
        with patch.object(c, "owned", return_value=(self.cid, self.obj)):
            r.prepare(c, self.root, self.token)

    def test_pinned_default_argv_unchanged_and_opt_in_logging(self):
        spec = importlib.util.spec_from_file_location("base", HERE / "baseline.py")
        base = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(base)
        base.FW = c.FW  # The one authorized firmware pin change; default semantics unchanged.
        args = [self.root / "disk with spaces", self.root / "fw", self.root / "qemu", self.root, self.token, "boot", "1:2:3"]
        self.assertEqual(c.create_argv(*args), base.create_argv(*args))
        opt = c.create_argv(*args, keep_running=True)
        self.assertIn("max-size=64m", opt)
        self.assertIn("max-file=1", opt)
        self.assertNotIn("--rm", opt)
        self.assertNotIn("-i", opt)
        self.assertIn("-i", c.create_argv(*args))
        q = c.qemu_argv(keep_running=True)
        self.assertNotIn("stdio", q)
        self.assertEqual(q[q.index("-serial")+1], "chardev:owner_serial")
        self.assertIn("path=/run/sun4u/serial.sock", q[q.index("-chardev")+1])
        self.assertIn("logfile=/run/sun4u/serial.log", q[q.index("-chardev")+1])
        self.assertEqual(c.qemu_argv(), base.qemu_argv())

    def test_manifest_durable_before_start(self):
        self.prepare()
        record = json.loads((self.root / "retention.json").read_text())
        self.assertEqual(record["cid"], self.cid)
        self.assertEqual(record["owner"], self.token)
        self.assertFalse((self.root / "retention.json.tmp").exists())

    def test_logging_or_stdin_refusal(self):
        for which in ("logging", "stdin", "open", "attach", "tty", "running"):
            with self.subTest(which=which):
                (self.root / "preflight.json").write_text("{}")
                obj = json.loads(json.dumps(self.obj))
                if which == "logging": obj["HostConfig"]["LogConfig"]["Type"] = "none"
                if which == "stdin": obj["Config"]["StdinOnce"] = True
                if which == "open": obj["Config"]["OpenStdin"] = True
                if which == "attach": obj["Config"]["AttachStdin"] = True
                if which == "tty": obj["Config"]["Tty"] = True
                if which == "running": obj["State"]["Running"] = True
                with patch.object(c, "owned", return_value=(self.cid, obj)):
                    with self.assertRaises(ValueError): r.prepare(c, self.root, self.token)

    def test_exact_native_oom_transition_only(self):
        fixture = HERE / "native-fixtures"
        created = json.loads((fixture / "created-inspect.json").read_text())
        started = json.loads((fixture / "native-started.json").read_text())
        exited = json.loads((fixture / "native-after-eof.json").read_text())
        self.assertIs(created["HostConfig"]["OomKillDisable"], False)
        self.assertIsNone(started["HostConfig"]["OomKillDisable"])
        self.assertNotEqual(created["HostConfig"], started["HostConfig"])
        self.assertEqual(r.fingerprint(created), r.fingerprint(started))
        self.assertEqual(r.fingerprint(created), r.fingerprint(exited))
        for key, value in (("OomKillDisable", True), ("Memory", 99), ("NetworkMode", "host")):
            changed = json.loads(json.dumps(started))
            changed["HostConfig"][key] = value
            self.assertNotEqual(r.fingerprint(created), r.fingerprint(changed))
        self.assertIsNone(started["HostConfig"]["OomKillDisable"])  # no mutation

    def test_actual_socket_native_configuration_and_transition(self):
        fixture = HERE / "native-fixtures"
        created = json.loads((fixture / "socket-created.json").read_text())
        started = json.loads((fixture / "socket-running.json").read_text())
        after = json.loads((fixture / "socket-after-eof.json").read_text())
        self.assertFalse(created["Config"]["OpenStdin"])
        self.assertFalse(created["Config"]["StdinOnce"])
        self.assertFalse(created["Config"]["AttachStdin"])
        self.assertIn(c.qemu_argv(True)[c.qemu_argv(True).index("-chardev")+1], created["Config"]["Cmd"][-1])
        self.assertTrue(after["State"]["Running"])
        self.assertEqual(r.fingerprint(created), r.fingerprint(started))
        self.assertEqual(r.fingerprint(created), r.fingerprint(after))
        (self.root / "owned.cid").write_text(created["Id"])
        (self.root / "preflight.json").write_text("{}")
        with patch.object(c, "owned", return_value=(created["Id"], created)):
            r.prepare(c, self.root, self.token)
        with patch.object(c, "owned", return_value=(started["Id"], started)):
            self.assertEqual(r.inspect_retained(c, self.root, self.token)[0], created["Id"])

    def test_missing_or_symlink_serial_log_incomplete(self):
        self.prepare()
        (self.root / "serial.log").unlink()
        for symlink in (False, True):
            if symlink: (self.root / "serial.log").symlink_to(self.root / "preflight.json")
            with patch.object(c, "owned", return_value=(self.cid, self.obj)), patch.object(r.subprocess, "run", return_value=subprocess.CompletedProcess([],0)):
                self.assertEqual(r.reconcile(c,self.root,self.token)["outcome"], "RETAINED_SERIAL_LOG_INCOMPLETE")

    def test_owner_boot_preflight_cid_and_configuration_refusal(self):
        self.prepare()
        original = (self.root / "retention.json").read_text()
        for field in ("owner", "boot_id", "cid", "preflight_sha256", "fingerprint", "transport"):
            data = json.loads(original)
            data[field] = "wrong"
            (self.root / "retention.json").write_text(json.dumps(data))
            with patch.object(c, "owned", return_value=(self.cid, self.obj)):
                with self.assertRaises(ValueError): r.inspect_retained(c, self.root, self.token)

    def test_timeout_retains_and_never_opens_attached_pipe(self):
        with patch.object(r.time, "monotonic", side_effect=[0, 1]), patch.object(c, "call") as call, patch.object(subprocess, "Popen") as popen:
            self.assertEqual(r.watch(c, self.root, self.token, 1)["outcome"], "RETAINED_DEADLINE_UNVERIFIED")
        call.assert_not_called()
        popen.assert_not_called()

    def test_natural_exit_is_not_pass(self):
        with patch.object(r, "inspect_retained", return_value=(self.cid, self.obj)):
            self.assertEqual(r.watch(c, self.root, self.token, 1)["outcome"], "RETAINED_EXIT_UNVERIFIED")

    def test_reconcile_exports_regular_files_exact_cid_no_stop(self):
        self.prepare()
        def run(argv, **kw):
            self.assertEqual(argv, c.DOCKER + ["logs", "--timestamps", self.cid])
            self.assertTrue(kw["stdout"].writable())
            self.assertTrue(kw["stderr"].writable())
            self.assertEqual(kw["timeout"], 30)
            kw["stdout"].write(b"saved console\n")
            return subprocess.CompletedProcess(argv, 0)
        with patch.object(c, "owned", return_value=(self.cid, self.obj)), patch.object(r.subprocess, "run", side_effect=run):
            result = r.reconcile(c, self.root, self.token)
        self.assertEqual(result["outcome"], "RETAINED_EXIT_UNVERIFIED")
        self.assertEqual(next(self.root.glob("docker-*.log")).read_bytes(), b"saved console\n")
        self.assertTrue(list(self.root.glob("reconcile-*.json")))

    def test_reconcile_errors_never_stop_or_pass(self):
        self.prepare()
        for error in (OSError("disk error"), subprocess.TimeoutExpired("logs", 30)):
            with patch.object(c, "owned", return_value=(self.cid, self.obj)), patch.object(r.subprocess, "run", side_effect=error), patch.object(c, "stop_owned") as stop:
                self.assertEqual(r.reconcile(c, self.root, self.token)["outcome"], "RETAINED_LOG_ERROR_INCOMPLETE")
            stop.assert_not_called()

    def run_main(self, *, keep=True, error=None, prepare_error=None, export_error=None, start_error=None, firmware_hash=None):
        ev = self.root / "evidence"
        argv = ["candidate", "--disk", "/disk", "--firmware", "/fw", "--qemu", "/qemu", "--evidence", str(ev),
                "--offline-clean-shutdown-confirmed", "--exclusive-host-confirmed"]
        if keep: argv += ["--keep-running"]
        lock = self.root / "disk.coldboot.lock"
        real_open = os.open
        def opened(path, *a, **kw):
            return real_open(lock if str(path) == "/disk.coldboot.lock" else path, *a, **kw)
        def prep(*args):
            if prepare_error: raise prepare_error
            (ev / "retention.json").write_text("{}")
        calls = []
        def call(args, *a):
            calls.append(args)
            if args[:3] == ["stat", "-f", "-c"]: return "ext2/ext3"
            if "image" in args: return json.dumps([{"Id": c.IMAGE}])
            if "start" in args and start_error: raise start_error
            return self.cid
        with ExitStack() as stack:
            for name in ("host_check", "no_openers", "qcow_header"):
                stack.enter_context(patch.object(c, name))
            stack.enter_context(patch.object(c, "regular", side_effect=Path))
            stack.enter_context(patch.object(c, "identity", return_value="1:2:3"))
            stack.enter_context(patch.object(c, "digest", side_effect=[c.FW if firmware_hash is None else firmware_hash, c.QEMU]))
            stack.enter_context(patch.object(c.os, "access", return_value=True))
            stack.enter_context(patch.object(c.os, "open", side_effect=opened))
            stack.enter_context(patch.object(c.sys, "argv", argv))
            stack.enter_context(patch.object(c.signal, "signal"))
            stack.enter_context(patch("builtins.print"))
            stack.enter_context(patch.object(c, "call", side_effect=call))
            stack.enter_context(patch.object(c, "owned", return_value=(self.cid, self.obj)))
            stack.enter_context(patch.object(r, "prepare", side_effect=prep))
            watch = stack.enter_context(patch.object(r, "watch", side_effect=error, return_value={"outcome": "RETAINED_DEADLINE_UNVERIFIED"}))
            session = stack.enter_context(patch.object(c, "session", side_effect=error, return_value={"outcome": "DEADLINE_INCOMPLETE"}))
            stack.enter_context(patch.object(r, "reconcile", side_effect=export_error, return_value={"outcome": "RETAINED_RUNNING_UNVERIFIED"}))
            stop = stack.enter_context(patch.object(c, "stop_owned", return_value={"created": False}))
            self.assertEqual(c.main(), 2)
        return json.loads((ev / "outcome.json").read_text()), calls, stop, session, watch

    def test_opt_in_deadline_does_not_stop(self):
        result, calls, stop, session, _ = self.run_main()
        stop.assert_not_called()
        session.assert_not_called()
        self.assertIn(c.DOCKER + ["start", self.cid], calls)
        self.assertEqual(result["outcome"], "RETAINED_UNVERIFIED")

    def test_cancel_keeps_guest(self):
        result, _, stop, _, _ = self.run_main(error=KeyboardInterrupt("signal"))
        stop.assert_not_called()
        self.assertEqual(result["observation_outcome"], "CANCELLED_INCOMPLETE")

    def test_eof_keeps_guest(self):
        result, _, stop, _, _ = self.run_main(error=EOFError("input closed"))
        stop.assert_not_called()
        self.assertEqual(result["observation_outcome"], "ERROR_INCOMPLETE")

    def test_manifest_failure_prevents_start_and_never_stops(self):
        result, calls, stop, _, watch = self.run_main(prepare_error=OSError("full"))
        self.assertFalse(any("start" in a for a in calls))
        stop.assert_not_called()
        watch.assert_not_called()
        self.assertEqual(result["outcome"], "RETENTION_PREFLIGHT_INCOMPLETE")

    def test_ambiguous_start_timeout_retained(self):
        result, _, stop, _, watch = self.run_main(start_error=subprocess.TimeoutExpired("start", 30))
        stop.assert_not_called()
        watch.assert_not_called()
        self.assertEqual(result["outcome"], "RETAINED_UNVERIFIED")

    def test_export_failure_never_falls_back_to_stop(self):
        result, _, stop, _, _ = self.run_main(export_error=OSError("full"))
        stop.assert_not_called()
        self.assertEqual(result["outcome"], "RETENTION_RECONCILE_INCOMPLETE")

    def test_default_deadline_still_cleans_up(self):
        result, _, stop, session, watch = self.run_main(keep=False)
        stop.assert_called_once()
        session.assert_called_once()
        watch.assert_not_called()
        self.assertEqual(result["outcome"], "DEADLINE_INCOMPLETE")

    def test_default_cancel_still_cleans_up(self):
        result, _, stop, _, _ = self.run_main(keep=False, error=KeyboardInterrupt("signal"))
        stop.assert_called_once()
        self.assertEqual(result["outcome"], "CANCELLED_INCOMPLETE")


if __name__ == "__main__": unittest.main()
