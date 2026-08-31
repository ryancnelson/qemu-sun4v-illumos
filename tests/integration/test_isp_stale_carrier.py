#!/usr/bin/env python3
"""Regression fixture for the 2026-08-27 channel-0 stale-carrier failure."""

import pathlib
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "chan"))

from isp_supervisor import GateResult, Ledger, Profile, Supervisor


class MutationTrap:
    facts = {
        "socket_state": "ESTAB", "recv_q": 360, "send_q": 0,
        "h2g_seq": 2, "h2g_len": 44, "h2g_ack": 2,
        "g2h_seq": 2, "g2h_len": 46, "g2h_ack": 1,
        "host_pppd": "absent",
    }

    def __init__(self):
        self.inspections = 0
        self.mutations = []

    def inspect(self, profile):
        self.inspections += 1
        return GateResult("STALE_CARRIER", self.facts)

    def ensure_run_network(self, profile):
        self.mutations.append("network")
        raise AssertionError("network mutation after stale carrier")

    def launch_peer(self, profile, request_id):
        self.mutations.append("pppd")
        raise AssertionError("pppd launch after stale carrier")

    def stop_peer(self, peer):
        self.mutations.append("stop")
        raise AssertionError("peer stop after stale carrier")


class TodayStaleCarrierIntegrationTest(unittest.TestCase):
    def test_prepare_fails_closed_before_every_mutation_boundary(self):
        profile = Profile(
            run_id="workstation-playbox-known-good-20260827T165948Z",
            run_dir="/not-used", manifest="/not-used", mailbox="/not-used",
            channel_host_byte=327680, channel_socket="/not-used/niag0.sock",
            bridge_pid=38896, bridge_start_id="not-used",
        )
        operations = MutationTrap()
        with tempfile.TemporaryDirectory() as temporary:
            supervisor = Supervisor(
                profile, operations, Ledger(str(pathlib.Path(temporary) / "ledger.jsonl")),
                id_factory=lambda: "7f31",
            )
            answer = supervisor.prepare()

        self.assertEqual(
            answer, "ISP BLOCKED id=7f31 state=FAILED code=STALE_CARRIER")
        self.assertEqual(operations.inspections, 1)
        self.assertEqual(operations.mutations, [])


if __name__ == "__main__":
    unittest.main()
