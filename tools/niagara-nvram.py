#!/usr/bin/env python3
"""Diagnose Niagara OpenBoot NVRAM records; never encode release firmware.

OpenBoot itself is the project's production NVRAM encoder.  See
notes/NIAGARA-NVRAM-ORACLE.md.  The mutation options here exist only for
format experiments and must not feed installer, release, or regression runs.
"""

from __future__ import annotations

import argparse
import pathlib
import struct


PRIMES = (2971, 8747, 1031, 1151, 2861)
VALID_HASH = 0x80000000
EXPECTED_SIZE = 8192
TOKEN_BASE = 0x40


def nvhash(name: str) -> int:
    modifier = ((ord(name[0]) & 0x5F) << 6) | (len(name) & 0x1F)
    value = 0
    for index, byte in enumerate(name.encode("ascii")):
        value = (value + byte * PRIMES[index % len(PRIMES)]) & 0xFFFFFFFF
        value = (value & 0xFFFF) + (value >> 16)
    value = (value << 12) & 0xFFFFFFFF
    if value & VALID_HASH:
        raise ValueError(f"hash/valid collision for {name}")
    return value | VALID_HASH | modifier


def simple_crc(data: bytes) -> int:
    value = len(data)
    for byte in data:
        value += byte
        value = (value & 0xFF) + (value >> 8)
    return value & 0xFF


def scan(image: bytes) -> tuple[int, list[tuple[int, int, bytes]]]:
    if len(image) != EXPECTED_SIZE:
        raise ValueError(f"expected {EXPECTED_SIZE} bytes, got {len(image)}")
    offset = TOKEN_BASE + 4  # fixed region ends at 0x40; first word is magic
    records: list[tuple[int, int, bytes]] = []
    while offset + 4 <= len(image):
        key = struct.unpack_from(">I", image, offset)[0]
        if key == 0xFFFFFFFF:
            return offset, records
        if not key & VALID_HASH:  # deleted-key tombstone is only four bytes
            offset += 4
            continue
        if offset + 7 > len(image):
            raise ValueError(f"truncated record header at 0x{offset:x}")
        crc = image[offset + 4]
        length = struct.unpack_from(">H", image, offset + 5)[0]
        end = offset + 7 + length
        if end > len(image):
            raise ValueError(f"record at 0x{offset:x} extends past image")
        data = image[offset + 7 : end]
        if simple_crc(data) != crc:
            raise ValueError(f"bad CRC at 0x{offset:x}")
        records.append((offset, key, data))
        offset = end
    raise ValueError("no NVRAM EOF marker")


def append_record(image: bytes, name: str, data: bytes) -> bytes:
    eof, _ = scan(image)
    record = struct.pack(">IBH", nvhash(name), simple_crc(data), len(data)) + data
    if eof + len(record) + 4 > len(image):
        raise ValueError("NVRAM token region is full")
    output = bytearray(image)
    output[eof : eof + len(record)] = record
    output[eof + len(record) : eof + len(record) + 4] = b"\xff" * 4
    return bytes(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--nvramrc")
    parser.add_argument("--enable-nvramrc", action="store_true")
    args = parser.parse_args()

    image = args.input.read_bytes()
    eof, records = scan(image)
    print(f"size={len(image)} magic={image[TOKEN_BASE:TOKEN_BASE+4].hex()} eof=0x{eof:x}")
    known = {
        nvhash("boot-device"): "boot-device",
        nvhash("input-device"): "input-device",
        nvhash("output-device"): "output-device",
        nvhash("auto-boot?"): "auto-boot?",
        nvhash("use-nvramrc?"): "use-nvramrc?",
        nvhash("nvramrc"): "nvramrc",
    }
    for offset, key, data in records:
        print(f"0x{offset:04x} {known.get(key, f'hash:{key:08x}')} {data.hex()}")

    changed = image
    if args.enable_nvramrc:
        changed = append_record(changed, "use-nvramrc?", b"\xff")
    if args.nvramrc is not None:
        changed = append_record(changed, "nvramrc", args.nvramrc.encode("ascii") + b"\0")
    if changed != image:
        if args.output is None:
            parser.error("--output is required when changing the image")
        scan(changed)
        args.output.write_bytes(changed)
        print(f"wrote={args.output} size={len(changed)}")


if __name__ == "__main__":
    main()
