#!/usr/bin/env python3
"""Static checks for the generated RV64A integration image."""

import unittest

from gen_rv64a_smoke import FUNCT5, amo, build_program, make_image


class Rv64aImageTests(unittest.TestCase):
    def test_all_atomic_operations_and_widths_are_present(self) -> None:
        words = [word for word in build_program().words if (word & 0x7F) == 0x2F]
        seen = {((word >> 27) & 0x1F, (word >> 12) & 0x7) for word in words}
        for funct5 in FUNCT5.values():
            self.assertIn((funct5, 0b010), seen)
            self.assertIn((funct5, 0b011), seen)

    def test_reference_encodings(self) -> None:
        self.assertEqual(amo("lr", 8, 6, 0, word=True), 0x1003_2400 | 0x2F)
        self.assertEqual(amo("sc", 9, 6, 7, word=False), 0x1873_34AF)
        self.assertEqual(amo("add", 8, 6, 7, word=False), 0x0073_342F)

    def test_image_shape_and_terminal_ecall(self) -> None:
        image = make_image()
        self.assertEqual(len(image), 8192)
        self.assertEqual(build_program().words[-1], 0x0000_0073)
        self.assertEqual(image[4096:5056], bytes(960))


if __name__ == "__main__":
    unittest.main()
