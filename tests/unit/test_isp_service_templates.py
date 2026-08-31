#!/usr/bin/env python3

import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
UNITS = ROOT / "tools" / "chan" / "systemd"


class ServiceTemplateTest(unittest.TestCase):
    def test_bbs_is_unprivileged_ordered_and_capability_free(self):
        unit = (UNITS / "niagara-bbs@.service").read_text()
        self.assertIn("User=niagara-bbs", unit)
        self.assertIn("Group=niagara-bbs", unit)
        self.assertIn("Requires=niagara-isp-supervisor@%i.service", unit)
        self.assertIn("NoNewPrivileges=yes", unit)
        self.assertIn("CapabilityBoundingSet=\n", unit)
        self.assertIn("ProtectSystem=strict", unit)
        self.assertLess(unit.index("EnvironmentFile="), unit.index("Environment=BBS_ISP_SOCKET="))
        self.assertIn("InaccessiblePaths=/mnt/disk-images/runs/%i/sockets/niag0.sock", unit)
        self.assertNotIn("InaccessiblePaths=/mnt/disk-images/runs/%i/sockets/niag4.sock", unit)
        self.assertNotIn("ExecStop=", unit)

    def test_supervisor_has_only_network_caps_and_no_shell(self):
        unit = (UNITS / "niagara-isp-supervisor@.service").read_text()
        self.assertIn("User=root", unit)
        self.assertIn("CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW", unit)
        self.assertIn("NoNewPrivileges=yes", unit)
        self.assertIn("ProtectSystem=strict", unit)
        self.assertNotIn("/bin/sh", unit)
        self.assertNotIn("ExecStop=", unit)
        self.assertIn("NIAGARA_BBS_UID", unit)
        self.assertIn("NIAGARA_BBS_GID", unit)
        self.assertIn("InaccessiblePaths=/mnt/disk-images/runs/%i/sockets/niag4.sock", unit)
        self.assertNotIn("InaccessiblePaths=/mnt/disk-images/runs/%i/sockets/niag0.sock", unit)

    def test_channel_target_is_only_an_explicit_operator_marker(self):
        unit = (UNITS / "niagara-channels@.target").read_text()
        self.assertIn("Operator-confirmed", unit)
        self.assertNotIn("ExecStart", unit)
        run = (UNITS / "niagara-run@.target").read_text()
        self.assertIn("Requires=niagara-channels@%i.target", run)


if __name__ == "__main__":
    unittest.main()
