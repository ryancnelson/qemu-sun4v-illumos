#!/usr/bin/env python3
"""Patch blocking OpenIndiana live-media console questions in-place.

This is deliberately a same-length binary transform for a disposable combined
ISO whose boot archive contains an uncompressed media-fs-root.  It never moves
UFS data or changes the file size.
"""

from pathlib import Path
import argparse
import mmap
import os


TRANSFORMS = (
    (
        b"/usr/bin/kbd -s </dev/console >/dev/console 2>&1",
        b"/usr/bin/kbd -s US-English >/dev/console 2>&1",
        1,
    ),
    (
        b"/usr/sbin/set_lang </dev/console >/dev/console 2>&1",
        b"/usr/sbin/set_lang default >/dev/console 2>&1",
        2,
    ),
)


def occurrences(mapping: mmap.mmap, needle: bytes) -> list[int]:
    found = []
    start = 0
    while True:
        offset = mapping.find(needle, start)
        if offset < 0:
            return found
        found.append(offset)
        start = offset + 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument(
        "--scan-bytes",
        type=int,
        default=644_198_400,
        help="scan only the source ISO extent (default: 644198400)",
    )
    args = parser.parse_args()

    with args.image.open("r+b") as stream:
        length = min(args.scan_bytes, os.fstat(stream.fileno()).st_size)
        with mmap.mmap(stream.fileno(), length, access=mmap.ACCESS_WRITE) as image:
            plans = []
            for old, new, expected in TRANSFORMS:
                if len(new) > len(old):
                    raise ValueError("replacement is longer than source text")
                offsets = occurrences(image, old)
                if len(offsets) != expected:
                    raise RuntimeError(
                        f"expected {expected} copies of {old!r}, found {len(offsets)}"
                    )
                plans.append((old, new.ljust(len(old), b" "), offsets))

            for old, replacement, offsets in plans:
                for offset in offsets:
                    image[offset : offset + len(old)] = replacement
                    print(f"patched {old!r} at image offset {offset:#x}")
            image.flush()
        os.fsync(stream.fileno())

    print("noninteractive console patch complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
