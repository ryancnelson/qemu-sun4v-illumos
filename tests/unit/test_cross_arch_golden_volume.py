"""Contract for the byte-identical cross-architecture guest-volume gate."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
APPLIANCE = ROOT if (ROOT / "appliance").is_file() else \
    ROOT / "appliances/sparc64-qemu-illumos-docker-guest"


class CrossArchGoldenVolumePolicy(unittest.TestCase):
    def test_release_assembles_and_verifies_gcc_with_atomic_qemu(self):
        harness = (APPLIANCE / "scripts/ci-golden-volume.sh").read_text()
        self.assertIn("/tmp/install-guest-ux.py", harness)
        self.assertIn("/bin/bash /jack/FETCH_GCC.sh", harness)
        self.assertIn("bash ./appliance self-toolchain", harness)
        dockerfile = (APPLIANCE / "Dockerfile").read_text()
        self.assertIn("0007-sparc-atomic-softint-updates.patch", dockerfile)
        self.assertIn("python3 /tmp/test-softint-atomic.py", dockerfile)
        policy = (APPLIANCE / "guest-assets/network-policy.env").read_text()
        self.assertIn("DNS_IP=8.8.8.8", policy)
        self.assertIn("NSS_HOSTS='files dns'", policy)
        self.assertIn("MemAvailable", (APPLIANCE / "appliance").read_text())
        self.assertIn("REBUILD_GUEST_RELEASE=3", harness)
        self.assertIn("guest-assets.release.SHA256SUMS", harness)
        publish = (APPLIANCE / "scripts/publish-golden.sh").read_text()
        self.assertIn("0007-atomic-softint", publish)

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

    def test_seed_collects_effective_smf_layers_before_repair(self):
        harness = (APPLIANCE / "scripts/ci-golden-volume.sh").read_text()
        appliance = (APPLIANCE / "appliance").read_text()
        self.assertNotIn("bash ./appliance self-smf-inspect", harness)
        self.assertIn("self-smf-inspect)", appliance)
        self.assertIn("svccfg -s svc:/system/filesystem/root:media listprop", appliance)
        self.assertIn("svcprop -p manifestfiles", appliance)
        self.assertIn("live-root-fs.xml", appliance)
        self.assertIn("root-minimal", appliance)
        self.assertIn("*root*minimal*.xml", appliance)
        self.assertIn("digest -a sha256", appliance)
        self.assertIn("cat -n", appliance)

    def test_seed_removes_only_the_hash_guarded_live_root_services(self):
        harness = (APPLIANCE / "scripts/ci-golden-volume.sh").read_text()
        appliance = (APPLIANCE / "appliance").read_text()
        self.assertNotIn("bash ./appliance self-groom-release", harness)
        self.assertIn("GOLDEN_BOOT_CLEAN=ADVISORY", harness)
        self.assertIn("8b64762aa964d3aef6d7496f1c298ce030866364fd4cab6548134461a6f96b35", appliance)
        self.assertIn("284e9c84c4780d2a8305b723671be526433fc2be31772cb6cf0d86eb7c24c978", appliance)
        self.assertIn("svccfg delete -f svc:/system/filesystem/root:media", appliance)
        self.assertIn("svccfg delete -f svc:/system/filesystem/root-minimal", appliance)
        self.assertIn("svccfg -s svc:/system/filesystem/root delpg live-fs-root-minimal", appliance)
        self.assertNotIn("svcadm clear", appliance)
        self.assertNotIn("svcadm disable", appliance)
        self.assertIn("root-minimal=absent", appliance)
        self.assertIn("root-media=absent", appliance)
        self.assertIn("(live_root=", appliance)
        self.assertNotIn("set -e; live=", appliance)

    def test_runtime_gates_pin_the_same_guest_payload(self):
        text = (APPLIANCE / "scripts/ci-golden-volume.sh").read_text()
        self.assertIn("org.opencontainers.image.appliance-root-sha256", text)
        self.assertIn("materialized-v1.manifest", text)
        self.assertIn("root_sha256", text)
        self.assertIn("GOLDEN_PAYLOAD_IDENTITY=PASS", text)
        self.assertIn("GOLDEN_BOOT_CLEAN=PASS", text)
        self.assertIn("dependency cycle", text)
        self.assertIn("generic\\.xml failed", text)

    def test_cleanup_preserves_seed_and_golden_evidence_separately(self):
        text = (APPLIANCE / "appliance").read_text()
        self.assertIn("container-state-$SELF_CONTAINER", text)
        self.assertIn("self-network-direct-tcp.log", text)

    def test_clean_shutdown_accepts_openboot_trap_level_prompt(self):
        text = (APPLIANCE / "appliance").read_text()
        self.assertIn("syncing file systems... done", text)
        self.assertIn(r"^(\{[0-9]+\}[[:space:]]+)?ok[[:space:]]*$", text)
        self.assertIn("emulator-exited-after-sync", text)
        self.assertIn("docker cp", text)
        self.assertLess(text.index("syncing file systems... done"),
                        text.index("emulator-exited-after-sync"))

    def test_workflows_are_dedicated_and_ordered(self):
        amd = (ROOT / ".woodpecker/golden-volume-amd64.yml").read_text()
        arm = (ROOT / ".woodpecker/golden-volume-arm64.yml").read_text()
        self.assertIn("branch: codex/softint-dualarch-release", amd)
        self.assertIn("branch: codex/softint-dualarch-release", arm)
        self.assertIn("depends_on: [golden-volume-amd64]", arm)
        for phase in ("seed-build", "freeze", "golden-build", "test-first", "test-second"):
            self.assertIn(phase, amd)
        for phase in ("golden-build", "test-first", "test-second"):
            self.assertIn(phase, arm)
        self.assertLess(amd.index("phase=freeze"), amd.index("phase=golden-build"))
        self.assertLess(arm.index("phase=test-first"), arm.index("phase=test-second"))


if __name__ == "__main__":
    unittest.main()
