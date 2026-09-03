#!/usr/bin/env python3
"""Decode an illumos/Solaris fiocompress object on either host endian."""

from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path


MAGIC_ZLIB = 0x5A636D70
VERSION = 1
ALGORITHM_ZLIB = 1
FIXED_HEADER_SIZE = 40
COMPHDR_SIZE = 48


class FormatError(ValueError):
    pass


def decode(data: bytes) -> tuple[bytes, str, int, int]:
    if len(data) < COMPHDR_SIZE:
        raise FormatError("input is shorter than struct comphdr")

    if struct.unpack_from(">Q", data)[0] == MAGIC_ZLIB:
        byte_order = ">"
        endian_name = "big"
    elif struct.unpack_from("<Q", data)[0] == MAGIC_ZLIB:
        byte_order = "<"
        endian_name = "little"
    else:
        raise FormatError("input does not have an illumos Zcmp magic value")

    magic, version, algorithm, file_size, block_size = struct.unpack_from(
        f"{byte_order}5Q", data
    )
    if magic != MAGIC_ZLIB:
        raise FormatError("internal magic check failed")
    if version != VERSION:
        raise FormatError(f"unsupported format version {version}")
    if algorithm != ALGORITHM_ZLIB:
        raise FormatError(f"unsupported compression algorithm {algorithm}")
    if file_size == 0:
        raise FormatError("zero-length fiocompress object is invalid")
    if block_size == 0 or block_size & (block_size - 1):
        raise FormatError(f"invalid block size {block_size}")

    block_count = (file_size + block_size - 1) // block_size
    header_size = COMPHDR_SIZE + block_count * 8
    if header_size > len(data):
        raise FormatError("block map extends beyond input")
    block_offsets = struct.unpack_from(
        f"{byte_order}{block_count}Q", data, FIXED_HEADER_SIZE
    )
    if block_offsets[0] < header_size:
        raise FormatError("first compressed block overlaps the header")
    if any(left >= right for left, right in zip(block_offsets, block_offsets[1:])):
        raise FormatError("compressed block offsets are not strictly increasing")
    if block_offsets[-1] >= len(data):
        raise FormatError("last compressed block starts beyond input")

    output = bytearray()
    for index, start in enumerate(block_offsets):
        end = block_offsets[index + 1] if index + 1 < block_count else len(data)
        try:
            block = zlib.decompress(data[start:end])
        except zlib.error as error:
            raise FormatError(f"zlib block {index} failed: {error}") from error
        expected = min(block_size, file_size - len(output))
        if len(block) != expected:
            raise FormatError(
                f"block {index} expanded to {len(block)} bytes, expected {expected}"
            )
        output.extend(block)

    if len(output) != file_size:
        raise FormatError(f"output is {len(output)} bytes, expected {file_size}")
    return bytes(output), endian_name, block_size, block_count


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Decode a native-endian Solaris/illumos fiocompress object"
    )
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    try:
        output, endian_name, block_size, block_count = decode(args.input.read_bytes())
    except (OSError, FormatError) as error:
        print(f"decompress-fiocompress: {error}", file=sys.stderr)
        return 1

    args.output.write_bytes(output)
    print(f"FIOCOMPRESS_ENDIAN={endian_name}")
    print(f"FIOCOMPRESS_BLOCK_SIZE={block_size}")
    print(f"FIOCOMPRESS_BLOCK_COUNT={block_count}")
    print(f"FIOCOMPRESS_OUTPUT_BYTES={len(output)}")
    print("FIOCOMPRESS_DECOMPRESS=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
