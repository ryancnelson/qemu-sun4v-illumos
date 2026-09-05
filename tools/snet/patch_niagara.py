"""Apply the small, deterministic Niagara integration edits."""

from pathlib import Path
import sys


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if new in text:
        return
    if text.count(old) != 1:
        raise SystemExit(f"expected one integration anchor in {path}: {old!r}")
    path.write_text(text.replace(old, new))


root = Path(sys.argv[1])
niagara = root / "hw/sparc64/niagara.c"
meson = root / "hw/sparc64/meson.build"
kconfig = root / "hw/sparc64/Kconfig"

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
    '    if (nd_table[0].used) {\n'
    '        qemu_check_nic_model(&nd_table[0], TYPE_SUN4V_SNET);\n'
    '        sun4v_snet_init(&nd_table[0], NIAGARA_SNET_BASE);\n'
    '    }\n',
)
replace_once(
    meson,
    "sparc64_ss.add(when: 'CONFIG_NIAGARA', if_true: files('niagara.c'))\n",
    "sparc64_ss.add(when: 'CONFIG_NIAGARA', if_true: files('niagara.c', '../net/sun4v_snet.c'))\n",
)
replace_once(
    kconfig,
    '    select UNIMP\n',
    '    select UNIMP\n    select NETWORKING\n',
)

