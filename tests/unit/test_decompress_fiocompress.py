import importlib.util
import struct
import unittest
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "tools/openindiana/decompress-fiocompress.py"
SPEC = importlib.util.spec_from_file_location("decompress_fiocompress", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def encoded(payload: bytes, byte_order: str, block_size: int = 8) -> bytes:
    blocks = [payload[offset : offset + block_size] for offset in range(0, len(payload), block_size)]
    compressed = [zlib.compress(block, level=9) for block in blocks]
    header_size = MODULE.COMPHDR_SIZE + len(blocks) * 8
    offsets = []
    cursor = header_size
    for block in compressed:
        offsets.append(cursor)
        cursor += len(block)
    fixed = struct.pack(
        f"{byte_order}5Q",
        MODULE.MAGIC_ZLIB,
        MODULE.VERSION,
        MODULE.ALGORITHM_ZLIB,
        len(payload),
        block_size,
    )
    block_map = struct.pack(f"{byte_order}{len(offsets)}Q", *offsets)
    unused_struct_slot = b"\0" * 8
    return fixed + block_map + unused_struct_slot + b"".join(compressed)


class DecodeTests(unittest.TestCase):
    def test_decodes_big_endian_single_block(self):
        payload = b"seven!!"
        output, endian, block_size, block_count = MODULE.decode(encoded(payload, ">"))
        self.assertEqual(output, payload)
        self.assertEqual((endian, block_size, block_count), ("big", 8, 1))

    def test_decodes_little_endian_multiple_blocks(self):
        payload = b"0123456789abcdef!"
        output, endian, block_size, block_count = MODULE.decode(encoded(payload, "<"))
        self.assertEqual(output, payload)
        self.assertEqual((endian, block_size, block_count), ("little", 8, 3))

    def test_rejects_bad_magic(self):
        with self.assertRaisesRegex(MODULE.FormatError, "magic"):
            MODULE.decode(b"x" * 64)


if __name__ == "__main__":
    unittest.main()
