#!/usr/bin/env python3
"""Static safety gates for the OpenIndiana-compatible Perl launcher."""

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools" / "chan" / "guest-kermit-get.pl"


class GuestKermitGetTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text()

    def test_fixed_destination_and_no_shell(self):
        self.assertIn('my $root = "/rpool/kermit"', self.source)
        self.assertIn('exec($tool, "-X", "-q", "-i", "-r", "-a", $temp)',
                      self.source)
        self.assertNotIn("system(", self.source)
        self.assertNotIn("`", self.source)

    def test_strict_ready_and_no_buffered_socket_read(self):
        self.assertIn("^KERMIT READY name=", self.source)
        self.assertIn("timeout=45$", self.source)
        self.assertIn("sysread($s, $ch, 1)", self.source)
        self.assertNotIn("<$s>", self.source)

    def test_receive_is_bounded_and_atomic(self):
        self.assertIn("my $deadline = time + 45", self.source)
        self.assertIn('kill "KILL", $pid', self.source)
        self.assertIn("rename($temp, $final)", self.source)
        self.assertIn("hexdigest eq $sha", self.source)


if __name__ == "__main__":
    unittest.main()
