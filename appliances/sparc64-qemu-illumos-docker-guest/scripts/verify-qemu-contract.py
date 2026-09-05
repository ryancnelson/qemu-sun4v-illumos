#!/usr/bin/env python3
"""Verify the required SPARC TLB-range-flush implementation in QEMU.

This checks both the pinned source shape and the compiled binary. A label, a
source revision, or the mere existence of the helper is not enough:
replace_tlb_entry() must actually call the range helper.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"QEMU_CONTRACT=FAIL reason={message}", file=sys.stderr)
    raise SystemExit(1)


def source_gate(path: Path) -> None:
    text = path.read_text()
    match = re.search(
        r"static void replace_tlb_entry\b.*?\n}\n\nstatic void demap_tlb",
        text,
        flags=re.DOTALL,
    )
    if not match:
        fail("replace_tlb_entry source function not found")
    function = match.group(0)
    if "tlb_flush_range_by_mmuidx(cs, va, size," not in function:
        fail("replace_tlb_entry does not use tlb_flush_range_by_mmuidx")
    if "for (offset = 0; offset < size; offset += TARGET_PAGE_SIZE)" in function:
        fail("replace_tlb_entry retains per-page invalidation loop")
    if "tlb_flush_page(cs, va + offset)" in function:
        fail("replace_tlb_entry retains per-page tlb_flush_page call")
    print(f"QEMU_TLB_RANGE_FLUSH_SOURCE=PASS path={path}")


def binary_gate(path: Path) -> None:
    try:
        disassembly = subprocess.run(
            ["objdump", "-d", str(path)],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        fail(f"objdump failed: {error}")

    blocks = re.findall(
        r"^[0-9a-f]+ <([^>]+)>:\n(.*?)(?=^[0-9a-f]+ <|\\Z)",
        disassembly,
        flags=re.MULTILINE | re.DOTALL,
    )
    candidates = [body for name, body in blocks if "replace_tlb_entry" in name]
    if not candidates:
        fail("replace_tlb_entry symbol is absent from binary disassembly")
    direct_call = re.compile(
        r"\b(?:bl|call[a-z]*)\b.*<tlb_flush_range_by_mmuidx(?:\+0x[0-9a-f]+)?>"
    )
    if not any(direct_call.search(block) for block in candidates):
        fail("replace_tlb_entry has no direct range-flush helper call")
    print(f"QEMU_TLB_RANGE_FLUSH_BINARY=PASS path={path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--qemu", type=Path)
    args = parser.parse_args()
    if not args.source and not args.qemu:
        parser.error("at least one of --source or --qemu is required")
    if args.source:
        source_gate(args.source)
    if args.qemu:
        binary_gate(args.qemu)


if __name__ == "__main__":
    main()
