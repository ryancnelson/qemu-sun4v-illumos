"""Exercise resource ownership and failure paths without Docker or remote hosts."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
SCRIPTS = REPO / "appliances/sparc64-qemu-illumos-docker-guest/scripts"
COMMIT = "a" * 40


class LaneIsolationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.calls = self.base / "calls"
        self.stub("flock", "exit 0")
        self.stub("docker", 'echo "$*" >> "$CALLS"; exit 1')
        self.env = dict(os.environ, PATH=str(self.bin) + ":" + os.environ["PATH"],
                        CALLS=str(self.calls), CI_COMMIT_SHA=COMMIT)

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)

    def run_phase(self, number, phase="identity", **extra):
        root = self.base / ("niagara-lab-" + number)
        (root / "scripts").mkdir(parents=True, exist_ok=True)
        script = root / "scripts/ci-niagara-smp.sh"
        shutil.copyfile(SCRIPTS / script.name, script)
        appliance = root / "appliance"
        appliance.write_text('#!/bin/sh\necho "$1 $SELF_CONTAINER $SELF_VOLUME" >> "$CALLS"\n')
        env = dict(self.env, CI_PIPELINE_NUMBER=number, **extra)
        result = subprocess.run(["bash", str(script), phase], env=env,
                                capture_output=True, text=True)
        return result, root

    def test_two_runs_share_no_mutable_resource_names(self):
        first, _ = self.run_phase("701")
        second, _ = self.run_phase("702")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        for output, number in [(first.stdout, "701"), (second.stdout, "702")]:
            self.assertIn("container=niagara-smp-niagara-lab-" + number, output)
            self.assertIn("volume=niagara-smp-niagara-lab-" + number + "-state", output)
            self.assertIn("base=sparc64-qemu-illumos-guest:niagara-smp-niagara-lab-" + number, output)
        self.assertFalse(self.calls.exists())

    def test_low_disk_fails_before_source_copy_or_docker(self):
        self.stub("df", "printf 'Filesystem 1024-blocks Used Available Capacity Mounted\\n/dev/test 100 99 1 99%% /\\n'")
        result, _ = self.run_phase("703", "prepare")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("reason=insufficient-disk-space", result.stderr)
        self.assertFalse(self.calls.exists())

    def test_existing_commit_cannot_be_replaced(self):
        self.run_phase("704", "cleanup")
        result, _ = self.run_phase("704", "build", CI_COMMIT_SHA="b" * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("another commit", result.stderr)

    def test_busy_run_cannot_be_entered(self):
        self.stub("flock", "exit 1")
        result, _ = self.run_phase("705", "cleanup")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("another phase owns this run", result.stderr)
        self.assertFalse(self.calls.exists())

    def test_cleanup_only_names_its_own_resources(self):
        result, _ = self.run_phase("706", "cleanup")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls.read_text().splitlines()
        self.assertTrue(calls)
        self.assertTrue(all("niagara-smp-niagara-lab-706" in call for call in calls), calls)
        self.assertFalse(any("prune" in call or "volume ls" in call for call in calls))

    def test_invalid_identity_is_rejected(self):
        result, _ = self.run_phase("manual")
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.calls.exists())

    def test_smp_branch_selects_only_dedicated_workflow(self):
        dedicated = (REPO / ".woodpecker/niagara-smp.yml").read_text()
        legacy = (REPO / ".woodpecker/self-contained-oci.yml").read_text()
        self.assertIn("branch: codex/niagara-smp-oci", dedicated.split("steps:")[0])
        self.assertNotIn("codex/niagara-smp-oci", legacy.split("steps:")[0])
        self.assertNotIn("rsync", dedicated)
        self.assertNotIn("release-ghcr", dedicated)
        self.assertIn("smp-two-cpus-online", dedicated)
        self.assertIn("smp-ppp-and-dns", dedicated)
        self.assertIn("status: [success, failure]", dedicated)
        old_runner = (SCRIPTS / "ci-self-contained-oci.sh").read_text()
        self.assertNotIn("docker volume ls", old_runner)


if __name__ == "__main__":
    unittest.main()

