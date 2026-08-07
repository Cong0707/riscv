#!/usr/bin/env python3
"""Boundary tests for the RV64M arithmetic reference behavior."""

import unittest


MASK32 = (1 << 32) - 1
MASK64 = (1 << 64) - 1
INT32_MIN = -(1 << 31)
INT64_MIN = -(1 << 63)


def unsigned(value: int, bits: int) -> int:
    return value & ((1 << bits) - 1)


def signed(value: int, bits: int) -> int:
    value = unsigned(value, bits)
    sign_bit = 1 << (bits - 1)
    return value - (1 << bits) if value & sign_bit else value


def sign_extend_word(value: int) -> int:
    return unsigned(signed(value, 32), 64)


def quotient_toward_zero(dividend: int, divisor: int) -> int:
    quotient = abs(dividend) // abs(divisor)
    return -quotient if (dividend < 0) != (divisor < 0) else quotient


def signed_divrem(a: int, b: int, bits: int) -> tuple[int, int]:
    dividend = signed(a, bits)
    divisor = signed(b, bits)
    minimum = -(1 << (bits - 1))
    if divisor == 0:
        return -1, dividend
    if dividend == minimum and divisor == -1:
        return minimum, 0
    quotient = quotient_toward_zero(dividend, divisor)
    return quotient, dividend - quotient * divisor


def rv64m_reference(operation: str, a: int, b: int) -> int:
    a &= MASK64
    b &= MASK64

    if operation == "MUL":
        return (a * b) & MASK64
    if operation == "MULH":
        return unsigned((signed(a, 64) * signed(b, 64)) >> 64, 64)
    if operation == "MULHSU":
        return unsigned((signed(a, 64) * b) >> 64, 64)
    if operation == "MULHU":
        return ((a * b) >> 64) & MASK64
    if operation in ("DIV", "REM"):
        quotient, remainder = signed_divrem(a, b, 64)
        return unsigned(quotient if operation == "DIV" else remainder, 64)
    if operation == "DIVU":
        return MASK64 if b == 0 else a // b
    if operation == "REMU":
        return a if b == 0 else a % b
    if operation == "MULW":
        return sign_extend_word((a & MASK32) * (b & MASK32))
    if operation in ("DIVW", "REMW"):
        quotient, remainder = signed_divrem(a, b, 32)
        return sign_extend_word(quotient if operation == "DIVW" else remainder)
    if operation == "DIVUW":
        divisor = b & MASK32
        quotient = MASK32 if divisor == 0 else (a & MASK32) // divisor
        return sign_extend_word(quotient)
    if operation == "REMUW":
        divisor = b & MASK32
        remainder = (a & MASK32) if divisor == 0 else (a & MASK32) % divisor
        return sign_extend_word(remainder)
    raise ValueError(f"unknown RV64M operation: {operation}")


class Rv64mReferenceTests(unittest.TestCase):
    def assert_operation(self, operation: str, a: int, b: int, expected: int) -> None:
        self.assertEqual(rv64m_reference(operation, a, b), expected & MASK64)

    def test_multiply_low_and_high_boundaries(self) -> None:
        self.assert_operation("MUL", MASK64, 2, MASK64 - 1)
        self.assert_operation("MULH", -2, 3, MASK64)
        self.assert_operation("MULH", INT64_MIN, -1, 0)
        self.assert_operation("MULHSU", -2, MASK64, MASK64 - 1)
        self.assert_operation("MULHU", MASK64, MASK64, MASK64 - 1)

    def test_signed_division_rounds_toward_zero(self) -> None:
        self.assert_operation("DIV", 7, -3, -2)
        self.assert_operation("DIV", -7, 3, -2)
        self.assert_operation("REM", -7, 3, -1)
        self.assert_operation("REM", 7, -3, 1)

    def test_64_bit_division_exceptional_results(self) -> None:
        self.assert_operation("DIV", 123, 0, MASK64)
        self.assert_operation("DIV", INT64_MIN, -1, INT64_MIN)
        self.assert_operation("REM", -123, 0, -123)
        self.assert_operation("REM", INT64_MIN, -1, 0)
        self.assert_operation("DIVU", MASK64, 0, MASK64)
        self.assert_operation("DIVU", MASK64, 2, (1 << 63) - 1)
        self.assert_operation("REMU", MASK64 - 1, 0, MASK64 - 1)
        self.assert_operation("REMU", MASK64, 16, 15)

    def test_word_multiply_and_ignored_upper_bits(self) -> None:
        self.assert_operation("MULW", 0xaaaa_aaaa_8000_0000, 1, 0xffff_ffff_8000_0000)
        self.assert_operation("MULW", 0xffff_ffff_0000_0002, 3, 6)

    def test_signed_word_division_boundaries(self) -> None:
        self.assert_operation("DIVW", INT32_MIN, -1, 0xffff_ffff_8000_0000)
        self.assert_operation("DIVW", -7, 3, -2)
        self.assert_operation("DIVW", 123, 0, MASK64)
        self.assert_operation("REMW", INT32_MIN, -1, 0)
        self.assert_operation("REMW", -7, 3, -1)
        self.assert_operation("REMW", 0x1234_5678_8000_0001, 0, 0xffff_ffff_8000_0001)

    def test_unsigned_word_results_are_sign_extended(self) -> None:
        self.assert_operation("DIVUW", MASK32, 1, MASK64)
        self.assert_operation("DIVUW", MASK32, 2, 0x0000_0000_7fff_ffff)
        self.assert_operation("DIVUW", 123, 0, MASK64)
        self.assert_operation("REMUW", MASK32, 0x8000_0000, 0x0000_0000_7fff_ffff)
        self.assert_operation("REMUW", 0xaaaa_aaaa_8000_0001, 0, 0xffff_ffff_8000_0001)

    def test_unknown_operation_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "unknown RV64M operation"):
            rv64m_reference("INVALID", 0, 0)


if __name__ == "__main__":
    unittest.main()
