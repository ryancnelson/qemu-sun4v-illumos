"""Release-lane invariants: ARM must boot before changing the preview index."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ArmPreviewPolicy(unittest.TestCase):
    def test_native_isolated_lane(self):
        script = (ROOT / 'appliances/sparc64-qemu-illumos-docker-guest/scripts/ci-smp-arm64.sh').read_text()
        for required in ('uname -m', 'aarch64', 'niagara-smp-arm64-$PIPELINE_ID',
                         'flock -n', 'REBUILD_RELEASE_FIRMWARE=0',
                         'REBUILD_GUEST_RELEASE=2', 'state/boot.pass', 'state/cpus.pass',
                         'timeout --signal=TERM --kill-after=30s'):
            self.assertIn(required, script)
        self.assertNotIn('docker system prune', script)
        self.assertNotIn('docker volume prune', script)

    def test_preview_only_and_immutable_amd64(self):
        script = (ROOT / 'appliances/sparc64-qemu-illumos-docker-guest/scripts/ci-smp-arm64.sh').read_text()
        self.assertIn('sha256:343d2a755d03352645d0c3ea63b3f687468a8390d2710e941b34feafac6663bc', script)
        self.assertIn('smp-preview', script)
        self.assertNotIn(':latest', script)
        self.assertIn('--password-stdin', script)
        self.assertIn('{"amd64", "arm64"}', script)

    def test_workflow_separates_gates(self):
        text = (ROOT / '.woodpecker/niagara-smp-arm64.yml').read_text()
        self.assertIn('branch: codex/niagara-smp-arm64', text)
        for phase in ('prepare', 'build', 'boot', 'cpus', 'publish', 'cleanup'):
            self.assertIn('arm64-' + phase, text)
        self.assertLess(text.index('name: arm64-cpus'), text.index('name: arm64-publish'))
        self.assertIn('status: [success, failure]', text)


if __name__ == '__main__':
    unittest.main()
