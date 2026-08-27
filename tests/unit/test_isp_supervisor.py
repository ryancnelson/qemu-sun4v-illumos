#!/usr/bin/env python3

import json
import pathlib
import sys
import tempfile
import unittest
import subprocess
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "chan"))

from isp_protocol import parse_request
from isp_supervisor import (GateResult, Ledger, LinuxHostOperations, Peer,
                            Profile, Supervisor, ensure_private_dir)


def profile():
    return Profile(
        run_id="test-run", run_dir="/runs/test-run", manifest="/runs/test-run/manifest.env",
        mailbox="/dev/shm/test-run.img", channel_host_byte=327680,
        channel_socket="/runs/test-run/sockets/niag0.sock", bridge_pid=123,
        bridge_start_id="55",
    )


class FakeOperations:
    def __init__(self, gate=None, network=None, ready=True, alive=True, online=False):
        self.gate = gate or GateResult(facts={"carrier": "clean"})
        self.network = network or GateResult(facts={"rules": "adopted"})
        self.ready = ready
        self.alive = alive
        self.online = online
        self.negotiating = False
        self.calls = []
        self.stopped = []
        self.adopt = False

    def inspect(self, value):
        self.calls.append("inspect")
        return self.gate

    def ensure_run_network(self, value):
        self.calls.append("ensure_run_network")
        return self.network

    def launch_peer(self, value, request_id):
        self.calls.append("launch_peer")
        return Peer(4321, "99", "socket:1")

    def peer_ready(self, value, peer):
        self.calls.append("peer_ready")
        return self.ready

    def peer_alive(self, peer):
        self.calls.append("peer_alive")
        return self.alive

    def peer_online(self, value, peer):
        self.calls.append("peer_online")
        return self.online

    def peer_negotiating(self, value, peer):
        self.calls.append("peer_negotiating")
        return self.negotiating

    def stop_peer(self, peer):
        self.calls.append("stop_peer")
        self.stopped.append(peer.pid)

    def adopt_peer(self, value, peer):
        self.calls.append("adopt_peer")
        return self.adopt


class SupervisorTest(unittest.TestCase):
    def make_supervisor(self, operations, now=10):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        ledger_path = pathlib.Path(temporary.name) / "ledger.jsonl"
        supervisor = Supervisor(profile(), operations, Ledger(str(ledger_path)),
                                monotonic=lambda: now * 1_000_000_000,
                                id_factory=lambda: "7f31")
        return supervisor, ledger_path

    def test_prepare_ready_and_online(self):
        operations = FakeOperations()
        supervisor, ledger = self.make_supervisor(operations)
        answer = supervisor.handle(parse_request("ISP PREPARE\n"))
        self.assertEqual(answer, "ISP READY id=7f31 state=READY host=10.0.5.1 guest=10.0.5.15 expires=45")
        operations.online = True
        status = supervisor.handle(parse_request("ISP STATUS id=7f31\n"))
        self.assertIn("state=ONLINE", status)
        records = [json.loads(line) for line in ledger.read_text().splitlines()]
        self.assertEqual([row["to_state"] for row in records],
                         ["CHECKING", "READY", "ONLINE"])

    def test_abort_stops_only_owned_peer_and_preserves_run_network(self):
        operations = FakeOperations()
        supervisor, _ = self.make_supervisor(operations)
        supervisor.prepare()
        answer = supervisor.abort("7f31")
        self.assertEqual(answer, "ISP ABORTED id=7f31 state=FAILED")
        self.assertEqual(operations.stopped, [4321])
        self.assertEqual(operations.calls.count("ensure_run_network"), 1)

    def test_today_stale_carrier_is_zero_mutation(self):
        today = {
            "socket_state": "ESTAB", "recv_q": 360, "send_q": 0,
            "h2g_seq": 2, "h2g_len": 44, "h2g_ack": 2,
            "g2h_seq": 2, "g2h_len": 46, "g2h_ack": 1,
            "host_pppd": "absent",
        }
        operations = FakeOperations(GateResult("STALE_CARRIER", today))
        supervisor, ledger = self.make_supervisor(operations)
        answer = supervisor.prepare()
        self.assertEqual(answer,
                         "ISP BLOCKED id=7f31 state=FAILED code=STALE_CARRIER")
        self.assertEqual(operations.calls, ["inspect"])
        self.assertNotIn("ensure_run_network", operations.calls)
        self.assertNotIn("launch_peer", operations.calls)
        self.assertNotIn("stop_peer", operations.calls)
        record = json.loads(ledger.read_text().splitlines()[-1])
        self.assertEqual(record["facts"], today)

    def test_duplicate_prepare_is_busy(self):
        operations = FakeOperations()
        supervisor, _ = self.make_supervisor(operations)
        supervisor.prepare()
        self.assertEqual(supervisor.prepare(),
                         "ISP BLOCKED id=7f31 state=READY code=BUSY")
        self.assertEqual(operations.calls.count("launch_peer"), 1)

    def test_restart_fails_closed_without_positive_adoption(self):
        operations = FakeOperations()
        supervisor, ledger = self.make_supervisor(operations)
        supervisor.prepare()
        replacement = Supervisor(profile(), operations, Ledger(str(ledger)),
                                 id_factory=lambda: "beef")
        replacement.recover()
        self.assertEqual(replacement.active.state, "FAILED")
        self.assertEqual(operations.calls[-1], "adopt_peer")
        record = json.loads(ledger.read_text().splitlines()[-1])
        self.assertEqual(record["event"], "restart_not_adopted")


class NetworkPreparationTest(unittest.TestCase):
    def test_privileged_runtime_rejects_symlink(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            target = root / "target"
            target.mkdir()
            link = root / "runtime"
            link.symlink_to(target, target_is_directory=True)
            with self.assertRaises(SystemExit):
                ensure_private_dir(link, 0o700)

    def test_existing_equivalent_run_rules_are_adopted_without_mutation(self):
        calls = []

        def runner(argv, **kwargs):
            calls.append(argv)
            self.assertIn("-C", argv)
            return subprocess.CompletedProcess(argv, 0, "", "")

        with tempfile.TemporaryDirectory() as temporary:
            forwarding = pathlib.Path(temporary) / "ip_forward"
            forwarding.write_text("1\n")
            operations = LinuxHostOperations(runner, forwarding)
            result = operations.ensure_run_network(profile())

        self.assertIsNone(result.code)
        self.assertEqual(result.facts["forwarding"], "adopted")
        self.assertEqual(len(result.facts["adopted"]), 3)
        self.assertEqual(len(calls), 3)
        self.assertFalse(any("-A" in call or "-D" in call for call in calls))

    def test_peer_alive_requires_matching_process_start_identity(self):
        operations = LinuxHostOperations()
        peer = Peer(4321, "expected", "inode:1")
        with mock.patch.object(operations, "_proc_start", return_value="expected"), \
                mock.patch.object(pathlib.Path, "exists", return_value=True):
            self.assertTrue(operations.peer_alive(peer))
        with mock.patch.object(operations, "_proc_start", return_value="reused"), \
                mock.patch.object(pathlib.Path, "exists", return_value=True):
            self.assertFalse(operations.peer_alive(peer))

    def test_isolated_network_failure_rolls_back_only_created_state(self):
        calls = []
        additions = 0

        def runner(argv, **kwargs):
            nonlocal additions
            calls.append(argv)
            if "-C" in argv:
                return subprocess.CompletedProcess(argv, 1, "", "missing")
            if "-A" in argv:
                additions += 1
                if additions == 2:
                    raise subprocess.CalledProcessError(1, argv)
            return subprocess.CompletedProcess(argv, 0, "", "")

        with tempfile.TemporaryDirectory() as temporary:
            forwarding = pathlib.Path(temporary) / "ip_forward"
            forwarding.write_text("0\n")
            operations = LinuxHostOperations(runner, forwarding)
            result = operations.ensure_run_network(profile())
            final_forwarding = forwarding.read_text()

        self.assertEqual(result.code, "NAT_FAILED")
        self.assertEqual(final_forwarding, "0\n")
        deletes = [call for call in calls if "-D" in call]
        self.assertEqual(len(deletes), 1)
        self.assertIn("niagara-test-run-out", deletes[0])


if __name__ == "__main__":
    unittest.main()
