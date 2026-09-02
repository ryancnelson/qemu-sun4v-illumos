#!/usr/bin/env python3
"""Derive the appliance OpenBoot policy from the accepted Niagara MD source."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


BASE_SHA256 = "f77342f2df32e54fc385f9a86e90469ecef60504ab0af836ab1e99619a4d598b"
BOOT_DEVICE = "/virtual-devices@100/disk@5:a"


def replace_once(text: str, old: str, new: str) -> str:
    count = text.count(old)
    if count != 1:
        raise ValueError(f"expected one occurrence of {old!r}, found {count}")
    return text.replace(old, new)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    source = args.source.read_bytes()
    digest = hashlib.sha256(source).hexdigest()
    if digest != BASE_SHA256:
        raise SystemExit(
            f"refusing unrecognized MD source: got {digest}, expected {BASE_SHA256}"
        )

    text = source.decode("ascii")
    text = replace_once(
        text,
        '        boot-device  = "vdisk";\n',
        f'        boot-device  = "{BOOT_DEVICE}";\n'
        '        boot-file  = "-v";\n',
    )
    text = replace_once(
        text,
        '        auto-boot?  = "false";\n',
        '        auto-boot?  = "true";\n',
    )
    args.output.write_text(text, encoding="ascii")
    print(f"MD_POLICY_EDIT=PASS boot_device={BOOT_DEVICE} boot_file=-v auto_boot=true")


if __name__ == "__main__":
    main()
