#!/usr/bin/env python3
"""Unit tests for the channel BBS session state machine."""

import importlib.util
import pathlib
import subprocess
import socket
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "host_bbs", ROOT / "tools" / "chan" / "host-bbs.py"
)
host_bbs = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(host_bbs)


class ScriptedSession(host_bbs.Session):
    def __init__(self, lines):
        super().__init__(None, "/run/test-channel")
        self.lines = iter(lines)
        self.output = []

    def readline(self, timeout=300.0):
        return next(self.lines, None)

    def send(self, *lines):
        self.output.extend(lines)


class SessionTest(unittest.TestCase):
    def test_persistent_channel_session_has_no_modem_idle_timeout(self):
        class TimeoutRecordingSession(host_bbs.Session):
            def __init__(self):
                super().__init__(None, "/run/test-channel", modem_timeout=None)
                self.timeouts = []

            def readline(self, timeout=300.0):
                self.timeouts.append(timeout)
                return None

        session = TimeoutRecordingSession()
        session.run()
        self.assertEqual(session.timeouts, [None])

    def test_kermit_get_ready_uses_fixed_gkermit_argv_and_recovers(self):
        session = ScriptedSession([])

        class FakeProcess:
            returncode = 0
            def communicate(self, timeout):
                self.timeout = timeout
                return (b"", b"")

        with tempfile.TemporaryDirectory() as stage:
            def fake_run(argv, **kwargs):
                if "-sSIL" in argv:
                    return subprocess.CompletedProcess(argv, 0, "200 0", "")
                pathlib.Path(argv[argv.index("--output") + 1]).write_bytes(b"payload")
                return subprocess.CompletedProcess(argv, 0, "", "")

            with mock.patch.object(host_bbs, "KERMIT_STAGE", stage), \
                    mock.patch.object(host_bbs.shutil, "which", return_value="/usr/bin/gkermit"), \
                    mock.patch.object(host_bbs.os.path, "isfile", return_value=True), \
                    mock.patch.object(host_bbs.os, "access", return_value=True), \
                    mock.patch.object(host_bbs.subprocess, "run", side_effect=fake_run), \
                    mock.patch.object(host_bbs.subprocess, "Popen", return_value=FakeProcess()) as popen:
                session.cmd_kermit_get("https://example.test/file.bin")

        ready = next(line for line in session.output if line.startswith("KERMIT READY"))
        self.assertIn("name=file.bin size=7", ready)
        self.assertIn("sha256=239f59ed55e737c77147cf55ad0c1b030b6d7ee748a7426952f9b852d5a935e5", ready)
        self.assertIn("timeout=45", ready)
        argv = popen.call_args.args[0]
        self.assertEqual(argv[:5], ["/usr/bin/gkermit", "-X", "-q", "-i", "-s"])
        self.assertEqual(argv[-2:], ["-a", "file.bin"])
        self.assertTrue(any(line.startswith("KERMIT DONE") for line in session.output))

    def test_kermit_alias_and_canonical_dispatch_identically(self):
        for spelling in ("KERMIT-GET", "KERMET-GET"):
            session = ScriptedSession(["ATDT1", f"{spelling} https://example.test/a", "BYE"])
            with mock.patch.object(host_bbs.time, "sleep"), \
                    mock.patch.object(session, "cmd_kermit_get") as command:
                session.run()
            command.assert_called_once_with("https://example.test/a")

    def test_kermit_get_fails_closed_without_tool_or_with_unsafe_input(self):
        cases = [
            ("relative", "KERMIT BLOCKED code=DIRECT_URL_REQUIRED"),
            ("https://example.test/../", "KERMIT BLOCKED code=BAD_NAME"),
        ]
        with tempfile.TemporaryDirectory() as stage:
            for argument, expected in cases:
                session = ScriptedSession([])
                with mock.patch.object(host_bbs, "KERMIT_STAGE", stage), \
                        mock.patch.object(host_bbs.shutil, "which", return_value="/usr/bin/gkermit"), \
                        mock.patch.object(host_bbs.os.path, "isfile", return_value=True), \
                        mock.patch.object(host_bbs.os, "access", return_value=True):
                    session.cmd_kermit_get(argument)
                self.assertEqual(session.output, [expected])
            session = ScriptedSession([])
            with mock.patch.object(host_bbs, "KERMIT_STAGE", stage), \
                    mock.patch.object(host_bbs.shutil, "which", return_value=None), \
                    mock.patch.object(host_bbs.subprocess, "run") as run:
                session.cmd_kermit_get("https://example.test/a")
            self.assertEqual(session.output, ["KERMIT BLOCKED code=NO_TOOL"])
            run.assert_not_called()

    def test_kermit_get_rejects_http_failure_before_staging_or_transfer(self):
        session = ScriptedSession([])
        with tempfile.TemporaryDirectory() as stage, \
                mock.patch.object(host_bbs, "KERMIT_STAGE", stage), \
                mock.patch.object(host_bbs.shutil, "which", return_value="/usr/bin/gkermit"), \
                mock.patch.object(host_bbs.os.path, "isfile", return_value=True), \
                mock.patch.object(host_bbs.os, "access", return_value=True), \
                mock.patch.object(host_bbs.subprocess, "run", return_value=
                                  subprocess.CompletedProcess([], 0, "404 0", "")), \
                mock.patch.object(host_bbs.subprocess, "Popen") as popen:
            session.cmd_kermit_get("https://example.test/missing.bin")
            self.assertEqual(session.output,
                             ["KERMIT BLOCKED code=FETCH_HTTP status=404"])
            self.assertEqual(list(pathlib.Path(stage).iterdir()), [])
            popen.assert_not_called()

    def test_kermit_get_rejects_pipelined_bytes_without_mutation(self):
        session = ScriptedSession([])
        session.buf = b"unexpected\n"
        with tempfile.TemporaryDirectory() as stage, \
                mock.patch.object(host_bbs, "KERMIT_STAGE", stage), \
                mock.patch.object(host_bbs.shutil, "which", return_value="/usr/bin/gkermit"), \
                mock.patch.object(host_bbs.os.path, "isfile", return_value=True), \
                mock.patch.object(host_bbs.os, "access", return_value=True), \
                mock.patch.object(host_bbs.subprocess, "run") as run:
            session.cmd_kermit_get("https://example.test/a")
        self.assertEqual(session.output, ["KERMIT BLOCKED code=PIPELINED_INPUT"])
        run.assert_not_called()

    def test_redial_recovers_a_persistent_channel_session(self):
        session = ScriptedSession([
            "ATDT18005551212",
            "ATDT18005551212",
            "BYE",
        ])

        with mock.patch.object(host_bbs.time, "sleep"):
            session.run()

        self.assertEqual(session.output.count("CONNECT 2400"), 2)
        self.assertFalse(any(line.startswith("Unknown command")
                             for line in session.output))

    def test_get_direct_url_bypasses_oracle_discovery(self):
        session = ScriptedSession([])

        with tempfile.TemporaryDirectory() as delivery:
            def fake_run(argv, **kwargs):
                if "-sSIL" in argv:
                    return subprocess.CompletedProcess(argv, 0, "200 0", "")
                if "-fsSL" in argv:
                    destination = pathlib.Path(argv[argv.index("-o") + 1])
                    destination.write_bytes(b"GIF87a\x01\x00")
                    return subprocess.CompletedProcess(argv, 0, "", "")
                if argv[0] == "cksum":
                    return subprocess.CompletedProcess(argv, 0, "1234 8 file", "")
                raise AssertionError(f"unexpected command: {argv}")

            with mock.patch.object(host_bbs, "DELIVERY", delivery), \
                    mock.patch.object(host_bbs, "ask_llm") as oracle, \
                    mock.patch.object(host_bbs.subprocess, "run", fake_run):
                session.cmd_get("http://example.test/me.gif")

        oracle.assert_not_called()
        self.assertIn("URL: http://example.test/me.gif", session.output)
        self.assertTrue(any(line.startswith("DELIVERED 8 bytes")
                            for line in session.output))

    def test_isp_prepare_uses_constrained_client_not_oracle(self):
        session = ScriptedSession([])
        ready = "ISP READY id=7f31 state=READY host=10.0.5.1 guest=10.0.5.15 expires=45"
        with mock.patch.object(host_bbs, "ISP_SOCKET", "/run/test/control.sock"), \
                mock.patch.object(host_bbs.isp_client, "transact", return_value=ready) as client, \
                mock.patch.object(host_bbs, "ask_llm") as oracle:
            session.cmd_isp("PREPARE")
        client.assert_called_once_with("/run/test/control.sock", "ISP PREPARE")
        oracle.assert_not_called()
        self.assertEqual(session.output, [ready])

    def test_startppp_is_inert(self):
        session = ScriptedSession(["ATDT1", "STARTPPP", "BYE"])
        with mock.patch.object(host_bbs.time, "sleep"), \
                mock.patch.object(host_bbs.isp_client, "transact") as client, \
                mock.patch.object(host_bbs.os, "execv", create=True) as execv:
            session.run()
        client.assert_not_called()
        execv.assert_not_called()
        self.assertIn("ISP BLOCKED id=- state=FAILED code=USE_ISP_PREPARE",
                      session.output)

    def test_supervisor_unavailable_and_timeout_fail_closed(self):
        for failure in (FileNotFoundError(), socket.timeout()):
            session = ScriptedSession([])
            with self.subTest(failure=type(failure).__name__), \
                    mock.patch.object(host_bbs, "ISP_SOCKET", "/run/test/control.sock"), \
                    mock.patch.object(host_bbs.isp_client, "transact", side_effect=failure):
                session.cmd_isp("PREPARE")
            self.assertEqual(
                session.output,
                ["ISP BLOCKED id=- state=FAILED code=SUPERVISOR_UNAVAILABLE"])

    def test_malformed_isp_command_never_reaches_supervisor(self):
        session = ScriptedSession([])
        with mock.patch.object(host_bbs, "ISP_SOCKET", "/run/test/control.sock"), \
                mock.patch.object(host_bbs.isp_client, "transact",
                                  side_effect=host_bbs.ProtocolError("bad")):
            session.cmd_isp("PREPARE host=10.0.5.9")
        self.assertEqual(session.output,
                         ["ISP BLOCKED id=- state=FAILED code=BAD_REQUEST"])


if __name__ == "__main__":
    unittest.main()
