"""Contract for the byte-identical cross-architecture guest-volume gate."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
APPLIANCE = ROOT / "appliances/sparc64-qemu-illumos-docker-guest"


class CrossArchGoldenVolumePolicy(unittest.TestCase):
    def test_harness_freezes_a_cleanly_shutdown_seed(self):
        text = (APPLIANCE / "scripts/ci-golden-volume.sh").read_text()
        self.assertIn("bash ./appliance self-shutdown", text)
        self.assertIn("GOLDEN_GUEST_ROOT_SHA256", text)
        self.assertIn("tar --sparse", text)
        self.assertIn("assets.release.SHA256SUMS", text)
        self.assertNotIn("docker system prune", text)
        self.assertNotIn("docker volume prune", text)

    def test_each_architecture_gets_a_fresh_private_volume_and_two_boots(self):
        text = (APPLIANCE / "scripts/ci-golden-volume.sh").read_text()
        self.assertIn("golden-${ARCH}-${PIPELINE_ID}-state", text)
        self.assertIn("test-first", text)
        self.assertIn("test-second", text)
        self.assertIn("bash ./appliance self-smoke", text)
        self.assertIn("bash ./appliance self-restart", text)
        self.assertGreaterEqual(text.count("run_runtime_gates"), 3)
        for gate in ("self-smp", "self-network", "self-inventory"):
            self.assertIn(gate, text)
        self.assertIn("self-release-ready", text)

    def test_runtime_gates_pin_the_same_guest_payload(self):
        text = (APPLIANCE / "scripts/ci-golden-volume.sh").read_text()
        self.assertIn("org.opencontainers.image.appliance-root-sha256", text)
        self.assertIn("materialized-v1.manifest", text)
        self.assertIn("root_sha256", text)
        self.assertIn("GOLDEN_PAYLOAD_IDENTITY=PASS", text)
        self.assertIn("GOLDEN_BOOT_CLEAN=PASS", text)
        self.assertIn("dependency cycle", text)
        self.assertIn("generic\\.xml failed", text)

    def test_workflows_are_dedicated_and_ordered(self):
        amd = (ROOT / ".woodpecker/golden-volume-amd64.yml").read_text()
        arm = (ROOT / ".woodpecker/golden-volume-arm64.yml").read_text()
        self.assertIn("branch: codex/cross-arch-golden-volume", amd)
        self.assertIn("branch: codex/cross-arch-golden-volume", arm)
        self.assertIn("depends_on: [golden-volume-amd64]", arm)
        for phase in ("seed-build", "freeze", "golden-build", "test-first", "test-second"):
            self.assertIn(phase, amd)
        for phase in ("golden-build", "test-first", "test-second"):
            self.assertIn(phase, arm)
        self.assertLess(amd.index("phase=freeze"), amd.index("phase=golden-build"))
        self.assertLess(arm.index("phase=test-first"), arm.index("phase=test-second"))


if __name__ == "__main__":
    unittest.main()
