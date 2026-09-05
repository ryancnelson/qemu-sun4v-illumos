"""Apply the small, deterministic Niagara integration edits."""

from pathlib import Path
import sys


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"missing integration anchor in {path}: {old!r}")
    path.write_text(text.replace(old, new, 1))


root = Path(sys.argv[1])
niagara = root / "hw/sparc64/niagara.c"
meson = root / "hw/sparc64/meson.build"
kconfig = root / "hw/sparc64/Kconfig"

# An early prototype added a nonexistent Kconfig symbol. Remove it so rerunning
# this idempotent patcher also repairs that prototype tree.
kconfig.write_text(kconfig.read_text().replace('    select NETWORKING\n', ''))

# Repair the pre-`qemu_create_nic_device()` prototype if this script is rerun
# against a development worktree that received it.
niagara.write_text(niagara.read_text().replace(
    '    if (nd_table[0].used) {\n'
    '        qemu_check_nic_model(&nd_table[0], TYPE_SUN4V_SNET);\n'
    '        sun4v_snet_init(&nd_table[0], NIAGARA_SNET_BASE);\n'
    '    }\n',
    ''
))

replace_once(
    niagara,
    '#include "hw/rtc/sun4v-rtc.h"\n',
    '#include "hw/rtc/sun4v-rtc.h"\n#include "hw/net/sun4v_snet.h"\n',
)
replace_once(
    niagara,
    '#define NIAGARA_FPGA_UART_BASE   0xfff0c2c000ULL\n',
    '#define NIAGARA_FPGA_UART_BASE   0xfff0c2c000ULL\n'
    '#define NIAGARA_SNET_BASE        0xfff0c2c050ULL\n',
)
replace_once(
    niagara,
    '    sun4v_rtc_init(NIAGARA_RTC_BASE);\n',
    '    sun4v_rtc_init(NIAGARA_RTC_BASE);\n'
    '    sun4v_snet_init(NIAGARA_SNET_BASE);\n',
)
replace_once(
    niagara,
    '    mc->default_cpu_type = SPARC_CPU_TYPE_NAME("Sun-UltraSparc-T1");\n',
    '    mc->default_cpu_type = SPARC_CPU_TYPE_NAME("Sun-UltraSparc-T1");\n'
    '    mc->default_nic = TYPE_SUN4V_SNET;\n',
)
replace_once(
    meson,
    "sparc64_ss.add(when: 'CONFIG_NIAGARA', if_true: files('niagara.c'))\n",
    "sparc64_ss.add(when: 'CONFIG_NIAGARA', if_true: files('niagara.c', '../net/sun4v_snet.c'))\n",
)
