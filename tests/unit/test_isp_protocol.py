#!/usr/bin/env python3

import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "chan"))

from isp_protocol import ProtocolError, parse_request, response, validate_response


class ProtocolTest(unittest.TestCase):
    def test_exact_requests(self):
        self.assertEqual(parse_request(b"ISP PREPARE\n").action, "PREPARE")
        request = parse_request("ISP STATUS id=7f31\n")
        self.assertEqual((request.action, request.request_id), ("STATUS", "7f31"))
        request = parse_request("ISP ABORT id=deadbeef\n")
        self.assertEqual((request.action, request.request_id), ("ABORT", "deadbeef"))

    def test_rejects_parameters_and_malformed_input(self):
        bad = ["ISP PREPARE host=1.2.3.4\n", "ISP PREPARE\nISP PREPARE\n",
               "ISP STATUS id=XYZ\n", "ISP ABORT id=1\n", "SHELL id=7f31\n"]
        for request in bad:
            with self.subTest(request=request), self.assertRaises(ProtocolError):
                parse_request(request)
        with self.assertRaises(ProtocolError):
            parse_request(b"ISP PREPARE \xff\n")

    def test_response_is_machine_readable_and_duplicate_fields_fail(self):
        line = response("READY", request_id="7f31", state="READY",
                        host="10.0.5.1", guest="10.0.5.15", expires=45)
        self.assertEqual(validate_response(line), line)
        with self.assertRaises(ProtocolError):
            validate_response("ISP READY id=7f31 state=READY state=FAILED")


if __name__ == "__main__":
    unittest.main()
