#!/usr/bin/env python3
"""Patch the recovered SPARC guest-chand's unique compiled placement word."""

from pathlib import Path
import sys


OLD_BLOCK = 1015808
NEW_BLOCK = 1258240


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} input-guest-chand output", file=sys.stderr)
        return 2
    source = Path(sys.argv[1]).read_bytes()
    old = OLD_BLOCK.to_bytes(4, "big")
    new = NEW_BLOCK.to_bytes(4, "big")
    if source.count(old) != 1:
        print(f"expected one {old.hex()} placement word, found {source.count(old)}",
              file=sys.stderr)
        return 1
    offset = source.index(old)
    result = source[:offset] + new + source[offset + 4:]
    Path(sys.argv[2]).write_bytes(result)
    print(f"patched guest channel default {OLD_BLOCK} -> {NEW_BLOCK} at file offset {offset}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
