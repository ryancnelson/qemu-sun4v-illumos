import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/openindiana/prepare-term4code-02.py"


class PrepareTests(unittest.TestCase):
    def run_config(self, config):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "config.json"
            path.write_text(json.dumps(config))
            return subprocess.run([sys.executable, str(SCRIPT), "--config", str(path),
                                   "--check-config"], text=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def base(self):
        return {
            "schema_version": 1, "run_id": "term4code-02", "run_dir": "/run/t02",
            "pinned": {"boot_archive": "/p/a", "boot_archive_size": 1,
                       "boot_archive_sha256": "0" * 64, "hsimd_size": 1,
                       "hsimd_sha256": "1" * 64},
            "builder_topology": None,
            "artifacts": {"installer": "/run/t02/i", "installer_manifest": "/run/t02/im",
                          "channel101": "/run/t02/c", "channel_manifest": "/run/t02/cm",
                          "unit104": "/run/t02/u", "unit104_manifest": "/run/t02/um",
                          "qemu_argv": "/run/t02/a"},
            "commands": {},
        }

    def test_missing_topology_is_typed_blocker(self):
        result = self.run_config(self.base())
        self.assertEqual(result.returncode, 20)
        self.assertEqual(result.stdout.strip(), "BLOCKED_MISSING_BUILDER_TOPOLOGY")

    def test_duplicate_units_fail(self):
        config = self.base()
        config["builder_topology"] = {
            "run_id": "oi-archive-builder-biggie-02",
            "run_dir": "/run/t02/oi-archive-builder-biggie-02",
            "tmux_session": "oi-archive-builder-biggie-02",
            "console_socket": "/run/t02/c.sock", "monitor_socket": "/run/t02/m.sock",
            "transport": "pcfs", "work_guest_device": "/dev/dsk/c0t0d0s3:c",
            "drives": [
                {"unit": 0, "role": "root", "path": "/run/t02/oi-archive-builder-biggie-02/root", "readonly": False},
                {"unit": 0, "role": "exchange", "path": "/run/t02/oi-archive-builder-biggie-02/x", "readonly": False},
            ],
        }
        result = self.run_config(config)
        self.assertEqual(result.returncode, 1)
        self.assertIn("duplicate", result.stderr)

    def test_command_requires_timeout_and_marker(self):
        config = self.base()
        config["builder_topology"] = {
            "run_id": "oi-archive-builder-biggie-02",
            "run_dir": "/run/t02/oi-archive-builder-biggie-02",
            "tmux_session": "oi-archive-builder-biggie-02",
            "console_socket": "/run/t02/c.sock", "monitor_socket": "/run/t02/m.sock",
            "transport": "pcfs", "work_guest_device": "/dev/dsk/c0t0d0s3:c",
            "drives": [{"unit": 0, "role": "root", "path": "/run/t02/oi-archive-builder-biggie-02/root",
                        "readonly": False}],
        }
        config["commands"] = {"bad": {"argv": ["true"], "timeout_seconds": 0,
                                        "expect": "PASS"}}
        result = self.run_config(config)
        self.assertEqual(result.returncode, 1)
        self.assertIn("invalid timeout", result.stderr)

    def test_media_v2_transform_is_idempotent(self):
        patcher = ROOT / "tools/openindiana/patch-media-fs-root.py"
        source = """#!/sbin/sh
# ... else try network (NFS)
if [ ! $MOUNT | grep -q \"^/.cdrom\" ] || [ ! -f /.liveusb ]; then
echo network
fi
"""
        with tempfile.TemporaryDirectory() as temp:
            first = Path(temp) / "first"
            second = Path(temp) / "second"
            original = Path(temp) / "original"
            original.write_text(source)
            subprocess.run([sys.executable, str(patcher), str(original), str(first)], check=True)
            subprocess.run([sys.executable, str(patcher), str(first), str(second)], check=True)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            text = first.read_text()
            self.assertIn("NIAGARA_HSIMD_MEDIA_FALLBACK_V2", text)
            self.assertIn("/dev/dsk/*s0 /dev/dsk/*s2", text)
            self.assertIn("if false; then", text)

    def test_channel_ppp_uses_byte_exact_asyncmap(self):
        guest = (ROOT / "tools/chan/guest-ppp-chan.pl").read_text()
        host = (ROOT / "tools/chan/host-pppd-once.sh").read_text()
        self.assertIn("'asyncmap', '0'", guest)
        self.assertIn("asyncmap 0 ${HOST_IP}:${GUEST_IP}", host)
        self.assertNotIn("'asyncmap', '0xffffffff'", guest)
        self.assertNotIn("asyncmap 0xffffffff ${HOST_IP}:${GUEST_IP}", host)

    def test_mock_pipeline_reaches_prelaunch_ready(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            trial = root / "term4code-02"
            builder = root / "oi-archive-builder-biggie-02"
            (trial / "manifests").mkdir(parents=True)
            archive = root / "boot_archive.ufs"
            archive.write_bytes(b"pinned-fixture")
            digest = __import__("hashlib").sha256(archive.read_bytes()).hexdigest()
            manifest = trial / "manifests/installer.manifest"
            manifest.write_text("\n".join((
                "etc_system:zfs_vdev_aggregation_limit=0x20000:PASS",
                "etc_system_literal:set zfs:zfs_vdev_aggregation_limit=0x20000:PASS",
                "media_fallback_v2:PASS",
                "# NIAGARA_HSIMD_MEDIA_FALLBACK_V2",
                "hsimd_pinned_unchanged:PASS",
                "ramroot_required_mounts_rw:PASS",
                "guest_channel_payload:unit101-block640:PASS",
                "archive_reopened_read_only:PASS",
            )) + "\n")
            argv = trial / "qemu.argv"
            argv.write_text("qemu -smp 1 -serial unix:/c -monitor unix:/m "
                            "unit=101,x unit=103,readonly=on,x unit=104,readonly=off,x\n")
            config = self.base()
            config["run_dir"] = str(trial)
            config["pinned"] = {"boot_archive": str(archive),
                                "boot_archive_size": archive.stat().st_size,
                                "boot_archive_sha256": digest,
                                "hsimd_size": 7, "hsimd_sha256": "1" * 64}
            config["builder_topology"] = {
                "run_id": "oi-archive-builder-biggie-02", "run_dir": str(builder),
                "tmux_session": "oi-archive-builder-biggie-02",
                "console_socket": str(builder / "console.sock"),
                "monitor_socket": str(builder / "monitor.sock"),
                "transport": "pcfs", "work_guest_device": "/dev/dsk/c0t0d0s3:c",
                "drives": [{"unit": 100, "role": "donor-root",
                            "path": str(builder / "root.img"), "readonly": False}],
            }
            config["artifacts"] = {
                "installer": str(trial / "installer"),
                "installer_manifest": str(manifest),
                "channel101": str(trial / "channel"),
                "channel_manifest": str(trial / "channel.manifest"),
                "unit104": str(trial / "unit104"),
                "unit104_manifest": str(trial / "unit104.manifest"),
                "qemu_argv": str(argv),
            }
            stages = ("verify_pinned_hsimd", "apply_media_v2",
                      "apply_aggregation_literal", "stage_donor", "run_mutation",
                      "reopen_read_only", "publish_immutable", "verify_unit101",
                      "verify_unit104", "prepare_qemu_argv")
            config["commands"] = {
                stage: {"argv": ["/bin/printf", "STAGE_PASS\n"],
                        "timeout_seconds": 2, "expect": "STAGE_PASS"}
                for stage in stages
            }
            config_path = root / "config.json"
            config_path.write_text(json.dumps(config))
            result = subprocess.run([sys.executable, str(SCRIPT), "--config",
                                     str(config_path)], text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "PRELAUNCH_READY")
            events = (trial / "evidence/prepare-events.jsonl").read_text().splitlines()
            self.assertEqual(len(events), len(stages))


if __name__ == "__main__":
    unittest.main()
