#!/usr/bin/env python3

import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "chan"))

from isp_qa_launcher import ReadyError, parse_ready, prepare_then_launch

READY = "ISP READY id=7f31 state=READY host=10.0.5.1 guest=10.0.5.15 expires=45"


class QaLauncherTest(unittest.TestCase):
    def test_ready_is_validated_before_immediate_launch(self):
        events = []
        clock = iter((10.0, 10.01))

        def prepare():
            events.append("prepare")
            return READY

        def launch(request_id):
            events.append(f"launch:{request_id}")

        self.assertEqual(prepare_then_launch(prepare, launch, lambda: next(clock)), "7f31")
        self.assertEqual(events, ["prepare", "launch:7f31"])

    def test_blocked_malformed_duplicate_and_unexpected_never_launch(self):
        bad = [
            "ISP BLOCKED id=7f31 state=FAILED code=STALE_CARRIER",
            "ISP READY id=7f31 state=READY host=10.0.5.9 guest=10.0.5.15 expires=45",
            READY + " extra=yes",
            READY + "\n" + READY,
            "garbage",
        ]
        for transcript in bad:
            launched = []
            with self.subTest(transcript=transcript), self.assertRaises(ReadyError):
                prepare_then_launch(lambda: transcript, launched.append)
            self.assertEqual(launched, [])

    def test_expired_ready_never_launches(self):
        launched = []
        clock = iter((0.0, 45.0))
        with self.assertRaisesRegex(ReadyError, "expired"):
            prepare_then_launch(lambda: READY, launched.append, lambda: next(clock))
        self.assertEqual(launched, [])

    def test_parser_ignores_human_banner_but_requires_one_machine_line(self):
        self.assertEqual(parse_ready("Sunset BBS\r\nisp> \r\n" + READY + "\r\n")[0],
                         "7f31")


if __name__ == "__main__":
    unittest.main()
