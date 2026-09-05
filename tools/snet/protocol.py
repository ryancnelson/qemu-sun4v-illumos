"""Reference model for the sun4v SNET 64-bit FIFO protocol."""

from collections import deque
from dataclasses import dataclass

MAGIC = 0x534E
VERSION = 1
MIN_FRAME = 14
MAX_FRAME = 1518
WORD_BYTES = 8


def header(length: int) -> int:
    if not MIN_FRAME <= length <= MAX_FRAME:
        raise ValueError("invalid Ethernet frame length")
    return (MAGIC << 48) | (VERSION << 32) | length


def decode_header(word: int) -> int:
    if word == 0:
        return 0
    magic = word >> 48
    version = (word >> 32) & 0xFFFF
    length = word & 0xFFFFFFFF
    if magic != MAGIC or version != VERSION or not MIN_FRAME <= length <= MAX_FRAME:
        raise ValueError("invalid SNET record header")
    return length


def record(frame: bytes) -> bytes:
    size = len(frame)
    prefix = header(size).to_bytes(WORD_BYTES, "big")
    padding = bytes((-size) % WORD_BYTES)
    return prefix + frame + padding


@dataclass
class TxAssembler:
    """Consumes the same sequence of 64-bit writes seen by the QEMU device."""

    expected: int = 0
    payload: bytearray | None = None

    def push(self, word: int) -> bytes | None:
        raw = word.to_bytes(WORD_BYTES, "big")
        if self.payload is None:
            self.expected = decode_header(word)
            if self.expected == 0:
                return None
            self.payload = bytearray()
            return None
        self.payload.extend(raw)
        if len(self.payload) < self.expected:
            return None
        frame = bytes(self.payload[: self.expected])
        self.expected = 0
        self.payload = None
        return frame


class RxQueue:
    def __init__(self, limit: int = 64):
        self._records: deque[bytes] = deque(maxlen=limit)
        self._active = b""

    def enqueue(self, frame: bytes) -> bool:
        if not MIN_FRAME <= len(frame) <= MAX_FRAME or len(self._records) == self._records.maxlen:
            return False
        self._records.append(record(frame))
        return True

    def pop_word(self) -> int:
        if not self._active:
            if not self._records:
                return 0
            self._active = self._records.popleft()
        word, self._active = self._active[:WORD_BYTES], self._active[WORD_BYTES:]
        return int.from_bytes(word, "big")

