#!/usr/bin/env python3
"""Generate a deterministic RV64M core-integration smoke image."""

from pathlib import Path

from gen_rv64i_smoke import (
    BASE,
    IMAGE_SIZE,
    Program,
    addi,
    auipc,
    ecall,
    lui,
    r_type,
    slli,
    store,
)


def m_op(rd: int, rs1: int, rs2: int, funct3: int, *, word: bool = False) -> int:
    return r_type(0x01, rs2, rs1, funct3, rd, 0x3B if word else 0x33)


def build_program() -> Program:
    p = Program()
    p.emit(auipc(20, 1))
    p.emit(addi(1, 0, -7))
    p.emit(addi(2, 0, 3))
    p.emit(addi(3, 0, -1))
    p.emit(addi(4, 0, 2))
    p.emit(addi(5, 0, 16))
    p.emit(lui(19, 0x80000))
    p.emit(addi(27, 0, 1))
    p.emit(slli(27, 27, 63))

    vectors = (
        (m_op(6, 1, 2, 0), 6, 0),          # MUL
        (m_op(7, 1, 2, 1), 7, 8),          # MULH
        (m_op(8, 1, 3, 2), 8, 16),         # MULHSU
        (m_op(9, 3, 3, 3), 9, 24),         # MULHU
        (m_op(10, 1, 2, 4), 10, 32),       # DIV
        (m_op(11, 3, 4, 5), 11, 40),       # DIVU
        (m_op(12, 1, 2, 6), 12, 48),       # REM
        (m_op(13, 3, 5, 7), 13, 56),       # REMU
        (m_op(14, 19, 2, 0, word=True), 14, 64),  # MULW
        (m_op(15, 1, 2, 4, word=True), 15, 72),   # DIVW
        (m_op(16, 3, 4, 5, word=True), 16, 80),   # DIVUW
        (m_op(17, 1, 2, 6, word=True), 17, 88),   # REMW
        (m_op(18, 3, 19, 7, word=True), 18, 96),  # REMUW
        (m_op(21, 1, 0, 4), 21, 104),      # DIV by zero
        (m_op(22, 1, 0, 6), 22, 112),      # REM by zero
        (m_op(23, 27, 3, 4), 23, 120),     # INT64_MIN / -1
        (m_op(24, 27, 3, 6), 24, 128),     # INT64_MIN % -1
        (m_op(25, 19, 3, 4, word=True), 25, 136),  # INT32_MIN / -1
        (m_op(26, 19, 3, 6, word=True), 26, 144),  # INT32_MIN % -1
    )
    for instruction, rd, offset in vectors:
        p.emit(instruction)
        p.emit(store(rd, 20, offset, "sd"))

    # M result consumed immediately by an integer instruction.
    p.emit(m_op(28, 2, 4, 0))
    p.emit(addi(28, 28, 1))
    p.emit(store(28, 20, 152, "sd"))

    # Back-to-back M instructions exercise MDU input forwarding.
    p.emit(m_op(29, 2, 4, 0))
    p.emit(m_op(30, 29, 4, 0))
    p.emit(store(30, 20, 160, "sd"))
    p.emit(ecall())
    p.resolve()
    return p


def make_image() -> bytes:
    program = build_program()
    image = bytearray(IMAGE_SIZE)
    for index, word in enumerate(program.words):
        image[index * 4 : index * 4 + 4] = word.to_bytes(4, "little")
    return bytes(image)


def write_hex(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = make_image()
    path.write_text("\n".join(f"{byte:02x}" for byte in image) + "\n", encoding="ascii")


if __name__ == "__main__":
    output = Path(__file__).resolve().parents[1] / "sim" / "generated" / "rv64m_smoke.hex"
    write_hex(output)
    print(f"wrote {output} ({IMAGE_SIZE} bytes, {len(build_program().words)} instructions)")
