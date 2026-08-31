#!/usr/bin/env python3

import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
GUEST = ROOT / "tools" / "chan" / "guest-isp-prepare.pl"


class GuestLauncherTest(unittest.TestCase):
    def perl_parse(self, transcript):
        escaped = transcript.replace("\\", "\\\\").replace("'", "\\'")
        program = (f"do '{GUEST}' or die $@ || $!; "
                   f"my ($id,$line)=parse_ready('{escaped}'); "
                   "print defined($id) ? $id : 'REJECT';")
        return subprocess.run(["perl", "-e", program], capture_output=True, text=True,
                              check=True).stdout

    def test_solaris_perl_syntax_and_exact_ready_parser(self):
        subprocess.run(["perl", "-c", str(GUEST)], check=True, capture_output=True)
        ready = "ISP READY id=7f31 state=READY host=10.0.5.1 guest=10.0.5.15 expires=45\n"
        self.assertEqual(self.perl_parse(ready), "7f31")

    def test_guest_parser_rejects_blocked_malformed_duplicate_and_addresses(self):
        ready = "ISP READY id=7f31 state=READY host=10.0.5.1 guest=10.0.5.15 expires=45"
        for value in (
            "ISP BLOCKED id=7f31 state=FAILED code=NO_UPSTREAM\n",
            ready + " extra=1\n",
            ready.replace("10.0.5.1", "10.0.5.9") + "\n",
            ready + "\n" + ready + "\n",
        ):
            with self.subTest(value=value):
                self.assertEqual(self.perl_parse(value), "REJECT")

    def test_guest_ppp_is_finite_and_fixed_after_prepare(self):
        source = GUEST.read_text()
        self.assertIn("ISP PREPARE\\r\\n", source)
        self.assertLess(source.index("parse_ready($seen)"), source.index("connect_unix($PPP)"))
        self.assertIn("'lcp-max-configure', '10'", source)
        self.assertIn("'lcp-restart', '3'", source)
        self.assertNotIn("'persist'", source)
        self.assertNotIn("maxfail", source)
        self.assertNotIn("STARTPPP", source)


if __name__ == "__main__":
    unittest.main()
