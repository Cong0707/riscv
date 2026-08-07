#!/usr/bin/env python3
"""Reference behavior for RV64A arithmetic memory operations."""

import unittest


MASK32 = (1 << 32) - 1
MASK64 = (1 << 64) - 1


def signed(value: int, bits: int) -> int:
    value &= (1 << bits) - 1
    sign = 1 << (bits - 1)
    return value - (1 << bits) if value & sign else value


def amo_new_value(operation: str, old: int, operand: int, bits: int) -> int:
    mask = (1 << bits) - 1
    old &= mask
    operand &= mask
    if operation == "swap":
        result = operand
    elif operation == "add":
        result = old + operand
    elif operation == "xor":
        result = old ^ operand
    elif operation == "and":
        result = old & operand
    elif operation == "or":
        result = old | operand
    elif operation == "min":
        result = old if signed(old, bits) < signed(operand, bits) else operand
    elif operation == "max":
        result = old if signed(old, bits) > signed(operand, bits) else operand
    elif operation == "minu":
        result = min(old, operand)
    elif operation == "maxu":
        result = max(old, operand)
    else:
        raise ValueError(f"unknown AMO operation: {operation}")
    return result & mask


class Rv64aReferenceTests(unittest.TestCase):
    def test_word_and_double_results(self) -> None:
        cases = {
            "swap": 9,
            "add": 8,
            "xor": 0x3C,
            "and": 0x15,
            "or": 0x3F,
            "min": (-5) & MASK64,
            "max": 3,
            "minu": 1,
            "maxu": MASK64,
        }
        operands = {
            "swap": (5, 9), "add": (5, 3), "xor": (15, 51),
            "and": (63, 21), "or": (48, 15), "min": (-5, 3),
            "max": (-5, 3), "minu": (-1, 1), "maxu": (-1, 1),
        }
        for operation, expected in cases.items():
            old, operand = operands[operation]
            self.assertEqual(amo_new_value(operation, old, operand, 64), expected)
            self.assertEqual(
                amo_new_value(operation, old, operand, 32), expected & MASK32
            )

    def test_unknown_operation_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "unknown AMO operation"):
            amo_new_value("invalid", 0, 0, 64)


if __name__ == "__main__":
    unittest.main()
