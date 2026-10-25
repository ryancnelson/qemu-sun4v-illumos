import hashlib
from pathlib import Path
import unittest
import test_retention as t

NEW = "e235a3bbfdff9e5b4c364bf46757a0975265ff4ea52c95d891238b4be36813dc"
OLD = "0fe3be7270fe52e64085c690b05474e0063f9d184c35a3dd7d15406a15e38343"
P = Path(__file__).resolve().parent

class Pin(unittest.TestCase):
    def invoke(self, value, keep):
        case = t.Retention()
        case.setUp()
        try:
            return case.run_main(keep=keep, firmware_hash=value)
        finally:
            case.doCleanups()

    def test_only_firmware_pin_changed_and_helper_unchanged(self):
        before = (P/"approved-socket.py").read_bytes()
        self.assertEqual(hashlib.sha256(before).hexdigest(), "76dc7dbeddb6ecf34786c1cd4c2b7510db41fc7a8f9f7eebfeaf5fa3a09496b7")
        self.assertEqual(before.count(OLD.encode()), 1)
        self.assertEqual(before.replace(OLD.encode(), NEW.encode()), (P.parents[1]/"scripts/coldboot-dad-retained.py").read_bytes())
        self.assertEqual(hashlib.sha256((P.parents[1]/"scripts/retention.py").read_bytes()).hexdigest(), "1a73b6e73faa3f8830d1af0888af2c5837966b5ee5febd9d48644bf8fda4022d")

    def test_real_local_compiled_artifact_hash_accepted_both_modes(self):
        artifact = P.parents[1]/"notes/firmware132-dadcompat-build/artifacts/openbios-sparc64.candidate"
        observed = t.c.digest(artifact)
        self.assertEqual(observed, NEW)
        self.assertEqual(t.c.FW, NEW)
        for keep in (False, True):
            with self.subTest(keep=keep):
                _, calls, _, session, watch = self.invoke(observed,keep)
                self.assertTrue(any("create" in x for x in calls))
                (watch if keep else session).assert_called_once()

    def test_old_and_wrong_firmware_refused_before_create(self):
        for value in (OLD, "0"*64):
            for keep in (False, True):
                with self.subTest(value=value, keep=keep):
                    result,calls,_,session,watch = self.invoke(value,keep)
                    self.assertFalse(any("create" in x or "start" in x for x in calls))
                    session.assert_not_called(); watch.assert_not_called()
                    self.assertIn("pin or executable mismatch", result["error"])

    def test_inside_runtime_check_uses_new_pin_before_exec(self):
        for keep in (False, True):
            args=t.c.create_argv(Path("/disk"),Path("/new fw"),Path("/qemu"),Path("/evidence"),"owner","boot","1:2:3",keep)
            script=args[-1]
            self.assertIn(NEW+"  /firmware.bin",script)
            self.assertNotIn(OLD,script)
            self.assertLess(script.index(NEW),script.index("exec "))

if __name__ == "__main__": unittest.main()
