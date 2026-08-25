#!/usr/bin/env python3
"""Patch SPARC swapgeneric to force the Tribblix persistent UFS root.

The input and patch object must both be big-endian ELF64 relocatable objects.
Only the starts of get_bootpath_prop (text+0x960) and get_fstype_prop
(text+0xa40) are replaced. Relocations covered by those replacement bytes are
changed to R_SPARC_NONE; every other byte and relocation is preserved.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import struct
from pathlib import Path


ELF_HEADER = struct.Struct(">16sHHIQQQIHHHHHH")
SECTION_HEADER = struct.Struct(">IIQQQQIIQQ")
RELA = struct.Struct(">QQq")


def sections(blob: bytes) -> dict[str, tuple[int, int, int]]:
    values = ELF_HEADER.unpack_from(blob)
    ident = values[0]
    if ident[:6] != b"\x7fELF\x02\x02":
        raise ValueError("expected a big-endian ELF64 object")
    shoff, shentsize, shnum, shstrndx = values[6], values[11], values[12], values[13]
    if shentsize != SECTION_HEADER.size:
        raise ValueError(f"unexpected section-header size {shentsize}")
    raw = [SECTION_HEADER.unpack_from(blob, shoff + i * shentsize) for i in range(shnum)]
    strings = raw[shstrndx]
    string_data = blob[strings[4] : strings[4] + strings[5]]

    result = {}
    for entry in raw:
        end = string_data.find(b"\0", entry[0])
        name = string_data[entry[0] : end].decode("ascii") if end >= 0 else ""
        result[name] = (entry[4], entry[5], entry[1])
    return result


def sha256(blob: bytes) -> str:
    return hashlib.sha256(blob).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("patch_object", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    source = bytearray(args.source.read_bytes())
    patch = args.patch_object.read_bytes()
    source_sections = sections(source)
    patch_sections = sections(patch)

    text_off, text_size, _ = source_sections[".text"]
    rela_off, rela_size, _ = source_sections[".rela.text"]
    patch_text_off, patch_text_size, _ = patch_sections[".text"]
    patch_text = patch[patch_text_off : patch_text_off + patch_text_size]

    bootpath_start, bootpath_size = 0x960, 0x68
    fstype_start, fstype_size = 0xA40, 0x14
    if text_size < fstype_start + fstype_size:
        raise ValueError("source .text is smaller than expected")
    if patch_text_size != bootpath_size + fstype_size:
        raise ValueError(f"unexpected patch .text size 0x{patch_text_size:x}")
    if source[text_off + bootpath_start : text_off + bootpath_start + 4] != bytes.fromhex("9de3bf50"):
        raise ValueError("get_bootpath_prop prologue does not match the audited module")
    if source[text_off + fstype_start : text_off + fstype_start + 4] != bytes.fromhex("9de3bf50"):
        raise ValueError("get_fstype_prop prologue does not match the audited module")

    source[text_off + bootpath_start : text_off + bootpath_start + bootpath_size] = patch_text[:bootpath_size]
    source[text_off + fstype_start : text_off + fstype_start + fstype_size] = patch_text[bootpath_size:]

    ranges = (
        (bootpath_start, bootpath_start + bootpath_size),
        (fstype_start, fstype_start + fstype_size),
    )
    neutralized = []
    if rela_size % RELA.size:
        raise ValueError(".rela.text size is not an Elf64_Rela multiple")
    for pos in range(rela_off, rela_off + rela_size, RELA.size):
        offset, info, addend = RELA.unpack_from(source, pos)
        if any(start <= offset < end for start, end in ranges):
            neutralized.append((offset, info & 0xFFFFFFFF))
            RELA.pack_into(source, pos, offset, info & 0xFFFFFFFF00000000, addend)
    if not neutralized:
        raise ValueError("no covered relocations found; refusing an unverified patch")

    args.output.write_bytes(source)
    os.chmod(args.output, args.source.stat().st_mode & 0o7777)
    print(f"source_sha256={sha256(args.source.read_bytes())}")
    print(f"output_sha256={sha256(source)}")
    print("neutralized_relocations=" + ",".join(f"0x{o:x}:type{t}" for o, t in neutralized))


if __name__ == "__main__":
    main()
