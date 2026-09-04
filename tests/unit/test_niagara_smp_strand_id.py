#!/usr/bin/env python3

import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
LDST_HELPER = ROOT / "work/qemu-sun4v-mp/target/sparc/ldst_helper.c"
CPU_C = ROOT / "work/qemu-sun4v-mp/target/sparc/cpu.c"
STRAND_PATCH = ROOT / "patches/0004-niagara-smp-strand-id.patch"
DIAGNOSTIC_PATCH = ROOT / "patches/0005-niagara-smp-interrupt-state-dump.patch"
MONDO_PATCH = ROOT / "patches/0006-niagara-defer-guest-mondo-in-hypervisor.patch"


class NiagaraSmpPatchContractTest(unittest.TestCase):
    def test_strand_patch_reports_the_current_cpu_index(self):
        patch = STRAND_PATCH.read_text()

        self.assertIn("case 0x00000010ULL", patch)
        self.assertIn("(cs->cpu_index & 0x3f)", patch)
        self.assertIn("report the current Niagara strand ID", patch)

    def test_mondo_patch_preserves_the_request_in_hypervisor_mode(self):
        patch = MONDO_PATCH.read_text()

        guard = patch.index("if (cpu_hypervisor_mode(env))")
        deferred = patch.index("Keep that request", guard)
        guest_clear = patch.index(
            "+        cpu_reset_interrupt(cs, CPU_INTERRUPT_HARD);", deferred
        )
        self.assertGreater(guest_clear, guard)
        self.assertIn(
            "+            cpu_reset_interrupt(cs, CPU_INTERRUPT_HARD);", patch
        )

    def test_interrupt_dump_patch_is_diagnostic_only(self):
        patch = DIAGNOSTIC_PATCH.read_text()

        self.assertIn("This patch is diagnostic only", patch)
        self.assertIn('qemu_fprintf(f, "interrupts: request=%x', patch)
        self.assertIn("env->int_queue[0]", patch)
        self.assertIn("env->htstate", patch)


@unittest.skipUnless(
    LDST_HELPER.exists() and CPU_C.exists(), "Niagara QEMU worktree is absent"
)
class NiagaraSmpAppliedSourceTest(unittest.TestCase):
    def test_cmt_strand_id_uses_the_current_cpu_index(self):
        source = LDST_HELPER.read_text()
        match = re.search(
            r"case 0x00000010ULL:\s*/\* ASI_CMT_STRAND_ID \*/"
            r"(?P<body>.*?)break;",
            source,
            re.DOTALL,
        )
        self.assertIsNotNone(match, "ASI_CMT_STRAND_ID read case is missing")
        self.assertIn(
            "cs->cpu_index",
            match.group("body"),
            "all Niagara vCPUs currently report physical strand zero",
        )

    def test_hard_interrupt_is_not_cleared_while_in_hypervisor_mode(self):
        source = CPU_C.read_text()
        function = source.split("static bool sparc_cpu_exec_interrupt", 1)[1]
        function = function.split("#endif /* !CONFIG_USER_ONLY */", 1)[0]
        hypervisor_guard = function.index("if (cpu_hypervisor_mode(env))")
        guest_clear = function.index(
            "cpu_reset_interrupt(cs, CPU_INTERRUPT_HARD);",
            hypervisor_guard,
        )

        self.assertGreater(
            guest_clear,
            hypervisor_guard,
            "a queued guest mondo is discarded while the vCPU is in the "
            "hypervisor",
        )


if __name__ == "__main__":
    unittest.main()
