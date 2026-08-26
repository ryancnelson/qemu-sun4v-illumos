#!/usr/bin/env python3
"""Patch the recovered SPARC guest-chand's unique compiled placement word."""

from pathlib import Path
import sys


OLD_BLOCK = 1015808
DEFAULT_NEW_BLOCK = 1258240


def main() -> int:
    if len(sys.argv) not in (3, 4, 5):
        print(f"usage: {sys.argv[0]} input-guest-chand output [new-block [old-block]]",
              file=sys.stderr)
        return 2
    new_block = int(sys.argv[3], 0) if len(sys.argv) == 4 else DEFAULT_NEW_BLOCK
    if len(sys.argv) == 5:
        new_block = int(sys.argv[3], 0)
    old_block = int(sys.argv[4], 0) if len(sys.argv) == 5 else OLD_BLOCK
    if not 0 <= new_block <= 0xFFFFFFFF:
        print(f"new-block outside uint32 range: {new_block}", file=sys.stderr)
        return 2
    if not 0 <= old_block <= 0xFFFFFFFF:
        print(f"old-block outside uint32 range: {old_block}", file=sys.stderr)
        return 2
    source = Path(sys.argv[1]).read_bytes()
    old = old_block.to_bytes(4, "big")
    new = new_block.to_bytes(4, "big")
    if source.count(old) != 1:
        print(f"expected one {old.hex()} placement word, found {source.count(old)}",
              file=sys.stderr)
        return 1
    offset = source.index(old)
    result = source[:offset] + new + source[offset + 4:]
    Path(sys.argv[2]).write_bytes(result)
    print(f"patched guest channel default {old_block} -> {new_block} at file offset {offset}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
