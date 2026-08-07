#!/usr/bin/env python3
"""Static checks for the generated mixed-width RV64C image."""

import unittest

from gen_rv64c_smoke import (
    build_program,
    c_add,
    c_addi,
    c_branch,
    c_ebreak,
    c_j,
    c_jr,
    c_li,
    c_mv,
    make_image,
)


class Rv64cImageTests(unittest.TestCase):
    def test_reference_encodings(self) -> None:
        self.assertEqual(c_addi(0, 0), 0x0001)  # C.NOP
        self.assertEqual(c_addi(1, 1), 0x0085)
        self.assertEqual(c_li(1, 1), 0x4085)
        self.assertEqual(c_j(0), 0xA001)
        self.assertEqual(c_branch("beqz", 8, 0), 0xC001)
        self.assertEqual(c_jr(1), 0x8082)
        self.assertEqual(c_mv(1, 2), 0x808A)
        self.assertEqual(c_add(1, 2), 0x908A)
        self.assertEqual(c_ebreak(), 0x9002)

    def test_all_integer_compressed_groups_are_present(self) -> None:
        program = build_program()
        compressed = []
        offset = 0
        while offset < len(program.data):
            halfword = int.from_bytes(program.data[offset : offset + 2], "little")
            if (halfword & 0x3) == 0x3:
                offset += 4
            else:
                compressed.append(halfword)
                offset += 2
        groups = {(word & 0x3, (word >> 13) & 0x7) for word in compressed}
        for funct3 in (0b000, 0b010, 0b011, 0b110, 0b111):
            self.assertIn((0b00, funct3), groups)
        for funct3 in range(8):
            self.assertIn((0b01, funct3), groups)
        for funct3 in (0b000, 0b010, 0b011, 0b100, 0b110, 0b111):
            self.assertIn((0b10, funct3), groups)

    def test_cross_word_instruction_and_image_layout(self) -> None:
        program = build_program()
        image = make_image()
        self.assertEqual(len(image), 8192)
        self.assertEqual(len(program.signatures), 30)
        self.assertEqual(program.data[-2:], c_ebreak().to_bytes(2, "little"))
        self.assertEqual(int.from_bytes(program.data[10:14], "little") & 0x7F, 0x13)
        self.assertEqual(10 & 0x3, 2)
        self.assertEqual(image[0x1000:0x1300], bytes(0x300))


if __name__ == "__main__":
    unittest.main()
