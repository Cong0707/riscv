#!/usr/bin/env python3
"""Static tests for the hand-encoded RV64I smoke image."""

import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_rv64i_smoke import BASE, IMAGE_SIZE, SIGNATURE, add, addi, build_program, ecall, jalr, make_image


class Rv64iImageTests(unittest.TestCase):
    def test_image_size_and_little_endian(self) -> None:
        image = make_image()
        self.assertEqual(len(image), IMAGE_SIZE)
        self.assertEqual(image[:4], (0x00001A17).to_bytes(4, "little"))

    def test_all_fixups_resolved(self) -> None:
        program = build_program()
        self.assertTrue(program.words)
        self.assertGreaterEqual(len(program.fixups), 4)
        self.assertTrue(all(label in program.labels for _, label, _, _ in program.fixups))
        self.assertTrue(all(word != 0 for word in program.words))

    def test_reference_encodings(self) -> None:
        self.assertEqual(addi(1, 0, 5), 0x00500093)
        self.assertEqual(add(3, 2, 1), 0x001101B3)
        self.assertEqual(jalr(11, 10), 0x000505E7)
        self.assertEqual(ecall(), 0x00000073)

    def test_image_contains_indirect_jump_and_ecall(self) -> None:
        program = build_program()
        # JALR is the third instruction in the AUIPC/ADDI/JALR sequence.
        jalr_index = (program.labels["after_jalr"] - BASE) // 4 - 2
        self.assertEqual(program.words[jalr_index] & 0x7F, 0x67)
        self.assertEqual(program.words[-1], ecall())
        self.assertIn("after_jal", program.labels)
        self.assertIn("after_jalr", program.labels)
        self.assertIn("done", program.labels)

    def test_signature_area_is_zero_initialized(self) -> None:
        image = make_image()
        self.assertEqual(image[SIGNATURE : SIGNATURE + 0x400], bytes(0x400))

    def test_control_flow_targets_are_in_image(self) -> None:
        program = build_program()
        image_end = BASE + len(program.words) * 4
        for label in ("branch_taken", "after_jal", "after_jalr", "failure", "done"):
            self.assertGreaterEqual(program.labels[label], BASE)
            self.assertLess(program.labels[label], image_end)


if __name__ == "__main__":
    unittest.main()
