#!/usr/bin/env python3
"""Static checks for the generated RV64M integration image."""

import unittest

from gen_rv64m_smoke import build_program, m_op, make_image


class Rv64mImageTests(unittest.TestCase):
    def test_all_standard_m_encodings_are_present(self) -> None:
        program = build_program().words
        operations = {
            (word >> 12) & 0x7
            for word in program
            if ((word >> 25) & 0x7F) == 1 and (word & 0x7F) == 0x33
        }
        word_operations = {
            (word >> 12) & 0x7
            for word in program
            if ((word >> 25) & 0x7F) == 1 and (word & 0x7F) == 0x3B
        }
        self.assertEqual(operations, set(range(8)))
        self.assertEqual(word_operations, {0, 4, 5, 6, 7})

    def test_reference_encodings(self) -> None:
        self.assertEqual(m_op(6, 1, 2, 0), 0x0220_8333)
        self.assertEqual(m_op(10, 1, 2, 4), 0x0220_C533)
        self.assertEqual(m_op(14, 19, 2, 0, word=True), 0x0229_873B)

    def test_image_shape_and_terminal_ecall(self) -> None:
        image = make_image()
        program = build_program()
        self.assertEqual(len(image), 8192)
        self.assertEqual(program.words[-1], 0x0000_0073)
        self.assertEqual(image[4096:4264], bytes(168))


if __name__ == "__main__":
    unittest.main()
