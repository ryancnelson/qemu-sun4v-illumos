import unittest

from protocol import MAX_FRAME, RxQueue, TxAssembler, decode_header, header, record


class ProtocolTest(unittest.TestCase):
    def test_header_round_trip(self):
        self.assertEqual(decode_header(header(60)), 60)
        self.assertEqual(decode_header(0), 0)

    def test_record_is_word_aligned(self):
        encoded = record(bytes(range(61)))
        self.assertEqual(len(encoded) % 8, 0)
        self.assertEqual(encoded[8:69], bytes(range(61)))

    def test_fragmented_tx_reassembles_exact_frame(self):
        frame = bytes(range(60))
        assembler = TxAssembler()
        words = record(frame)
        result = None
        for offset in range(0, len(words), 8):
            result = assembler.push(int.from_bytes(words[offset:offset + 8], "big"))
        self.assertEqual(result, frame)

    def test_rx_empty_and_queue_bound(self):
        queue = RxQueue(limit=1)
        self.assertEqual(queue.pop_word(), 0)
        self.assertTrue(queue.enqueue(bytes(60)))
        self.assertFalse(queue.enqueue(bytes(60)))
        self.assertEqual(decode_header(queue.pop_word()), 60)

    def test_bad_header_resets_cleanly(self):
        assembler = TxAssembler()
        with self.assertRaises(ValueError):
            assembler.push(0xDEADBEEF)
        self.assertEqual(assembler.push(header(60)), None)

    def test_length_limits(self):
        with self.assertRaises(ValueError):
            header(13)
        with self.assertRaises(ValueError):
            header(MAX_FRAME + 1)


if __name__ == "__main__":
    unittest.main()

