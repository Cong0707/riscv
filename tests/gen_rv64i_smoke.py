#!/usr/bin/env python3
"""Generate a toolchain-free RV64I smoke-test image.

The image is little-endian and is intended for a core reset PC of 0x80000000.
Each line in the output file contains one byte, which keeps the testbench
memory model independent of simulator-specific word ordering.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple


BASE = 0x8000_0000
IMAGE_SIZE = 0x2000
SIGNATURE = 0x1000


def _u(value: int, bits: int) -> int:
    return value & ((1 << bits) - 1)


def _check_reg(reg: int) -> None:
    if not 0 <= reg < 32:
        raise ValueError(f"register out of range: x{reg}")


def _check_signed(value: int, bits: int) -> None:
    if not -(1 << (bits - 1)) <= value < (1 << (bits - 1)):
        raise ValueError(f"immediate {value} does not fit signed {bits} bits")


def r_type(funct7: int, rs2: int, rs1: int, funct3: int, rd: int, opcode: int = 0x33) -> int:
    for reg in (rs1, rs2, rd):
        _check_reg(reg)
    return (_u(funct7, 7) << 25) | (rs2 << 20) | (rs1 << 15) | (_u(funct3, 3) << 12) | (rd << 7) | opcode


def i_type(imm: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    _check_signed(imm, 12)
    for reg in (rs1, rd):
        _check_reg(reg)
    return (_u(imm, 12) << 20) | (rs1 << 15) | (_u(funct3, 3) << 12) | (rd << 7) | opcode


def s_type(imm: int, rs2: int, rs1: int, funct3: int, opcode: int = 0x23) -> int:
    _check_signed(imm, 12)
    for reg in (rs1, rs2):
        _check_reg(reg)
    value = _u(imm, 12)
    return ((value >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (_u(funct3, 3) << 12) | ((value & 0x1F) << 7) | opcode


def b_type(offset: int, rs2: int, rs1: int, funct3: int, opcode: int = 0x63) -> int:
    if offset & 1:
        raise ValueError("branch target must be 2-byte aligned")
    _check_signed(offset, 13)
    for reg in (rs1, rs2):
        _check_reg(reg)
    value = _u(offset, 13)
    return (((value >> 12) & 1) << 31) | (((value >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | (_u(funct3, 3) << 12) | (((value >> 1) & 0xF) << 8) | (((value >> 11) & 1) << 7) | opcode


def u_type(imm20: int, rd: int, opcode: int) -> int:
    _check_reg(rd)
    return (_u(imm20, 20) << 12) | (rd << 7) | opcode


def j_type(offset: int, rd: int, opcode: int = 0x6F) -> int:
    if offset & 1:
        raise ValueError("jump target must be 2-byte aligned")
    _check_signed(offset, 21)
    _check_reg(rd)
    value = _u(offset, 21)
    return (((value >> 20) & 1) << 31) | (((value >> 1) & 0x3FF) << 21) | (((value >> 11) & 1) << 20) | (((value >> 12) & 0xFF) << 12) | (rd << 7) | opcode


def addi(rd: int, rs1: int, imm: int) -> int:
    return i_type(imm, rs1, 0x0, rd, 0x13)


def andi(rd: int, rs1: int, imm: int) -> int:
    return i_type(imm, rs1, 0x7, rd, 0x13)


def ori(rd: int, rs1: int, imm: int) -> int:
    return i_type(imm, rs1, 0x6, rd, 0x13)


def xori(rd: int, rs1: int, imm: int) -> int:
    return i_type(imm, rs1, 0x4, rd, 0x13)


def add(rd: int, rs1: int, rs2: int) -> int:
    return r_type(0x00, rs2, rs1, 0x0, rd)


def sub(rd: int, rs1: int, rs2: int) -> int:
    return r_type(0x20, rs2, rs1, 0x0, rd)


def sll(rd: int, rs1: int, rs2: int) -> int:
    return r_type(0x00, rs2, rs1, 0x1, rd)


def srl(rd: int, rs1: int, rs2: int) -> int:
    return r_type(0x00, rs2, rs1, 0x5, rd)


def sra(rd: int, rs1: int, rs2: int) -> int:
    return r_type(0x20, rs2, rs1, 0x5, rd)


def slt(rd: int, rs1: int, rs2: int) -> int:
    return r_type(0x00, rs2, rs1, 0x2, rd)


def sltu(rd: int, rs1: int, rs2: int) -> int:
    return r_type(0x00, rs2, rs1, 0x3, rd)


def addw(rd: int, rs1: int, rs2: int) -> int:
    return r_type(0x00, rs2, rs1, 0x0, rd, 0x3B)


def subw(rd: int, rs1: int, rs2: int) -> int:
    return r_type(0x20, rs2, rs1, 0x0, rd, 0x3B)


def sllw(rd: int, rs1: int, rs2: int) -> int:
    return r_type(0x00, rs2, rs1, 0x1, rd, 0x3B)


def srlw(rd: int, rs1: int, rs2: int) -> int:
    return r_type(0x00, rs2, rs1, 0x5, rd, 0x3B)


def sraw(rd: int, rs1: int, rs2: int) -> int:
    return r_type(0x20, rs2, rs1, 0x5, rd, 0x3B)


def addiw(rd: int, rs1: int, imm: int) -> int:
    return i_type(imm, rs1, 0x0, rd, 0x1B)


def shift_i(rd: int, rs1: int, shamt: int, funct6: int, funct3: int, word: bool = False) -> int:
    limit = 32 if word else 64
    if not 0 <= shamt < limit:
        raise ValueError("shift amount out of range")
    opcode = 0x1B if word else 0x13
    return ((_u(funct6, 6) << 6 | shamt) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def slli(rd: int, rs1: int, shamt: int) -> int:
    return shift_i(rd, rs1, shamt, 0x00, 0x1)


def srli(rd: int, rs1: int, shamt: int) -> int:
    return shift_i(rd, rs1, shamt, 0x00, 0x5)


def srai(rd: int, rs1: int, shamt: int) -> int:
    return shift_i(rd, rs1, shamt, 0x10, 0x5)


def slliw(rd: int, rs1: int, shamt: int) -> int:
    return shift_i(rd, rs1, shamt, 0x00, 0x1, True)


def srliw(rd: int, rs1: int, shamt: int) -> int:
    return shift_i(rd, rs1, shamt, 0x00, 0x5, True)


def sraiw(rd: int, rs1: int, shamt: int) -> int:
    return shift_i(rd, rs1, shamt, 0x10, 0x5, True)


def lui(rd: int, imm20: int) -> int:
    return u_type(imm20, rd, 0x37)


def auipc(rd: int, imm20: int) -> int:
    return u_type(imm20, rd, 0x17)


def jal(rd: int, offset: int) -> int:
    return j_type(offset, rd)


def jalr(rd: int, rs1: int, imm: int = 0) -> int:
    return i_type(imm, rs1, 0x0, rd, 0x67)


def branch(rs1: int, rs2: int, offset: int, kind: str) -> int:
    funct3 = {"beq": 0x0, "bne": 0x1, "blt": 0x4, "bge": 0x5, "bltu": 0x6, "bgeu": 0x7}[kind]
    return b_type(offset, rs2, rs1, funct3)


def load(rd: int, rs1: int, imm: int, kind: str) -> int:
    funct3 = {"lb": 0x0, "lh": 0x1, "lw": 0x2, "ld": 0x3, "lbu": 0x4, "lhu": 0x5, "lwu": 0x6}[kind]
    return i_type(imm, rs1, funct3, rd, 0x03)


def store(rs2: int, rs1: int, imm: int, kind: str) -> int:
    funct3 = {"sb": 0x0, "sh": 0x1, "sw": 0x2, "sd": 0x3}[kind]
    return s_type(imm, rs2, rs1, funct3)


def ecall() -> int:
    return 0x0000_0073


@dataclass
class Program:
    words: List[int]
    labels: Dict[str, int]
    fixups: List[Tuple[int, str, str, int]]

    def __init__(self) -> None:
        self.words = []
        self.labels = {}
        self.fixups = []

    @property
    def pc(self) -> int:
        return BASE + len(self.words) * 4

    def emit(self, word: int) -> None:
        self.words.append(word & 0xFFFF_FFFF)

    def label(self, name: str) -> None:
        if name in self.labels:
            raise ValueError(f"duplicate label {name}")
        self.labels[name] = self.pc

    def emit_branch(self, kind: str, rs1: int, rs2: int, label: str) -> None:
        self.fixups.append((len(self.words), label, "branch", (rs1 << 10) | (rs2 << 5) | {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}[kind]))
        self.emit(0)

    def emit_jal(self, rd: int, label: str) -> None:
        self.fixups.append((len(self.words), label, "jal", rd))
        self.emit(0)

    def resolve(self) -> None:
        for index, label, kind, arg in self.fixups:
            if label not in self.labels:
                raise ValueError(f"unknown label {label}")
            offset = self.labels[label] - (BASE + index * 4)
            if kind == "jal":
                self.words[index] = jal(arg, offset)
            else:
                rs1, rs2, funct3 = (arg >> 10) & 0x1F, (arg >> 5) & 0x1F, arg & 0x1F
                self.words[index] = b_type(offset, rs2, rs1, funct3)


def build_program() -> Program:
    p = Program()
    # x20 is a PC-relative pointer to the signature area at BASE + 0x1000.
    p.emit(auipc(20, 1))
    p.emit(addi(1, 0, 5))
    p.emit(addi(2, 1, 7))
    p.emit(add(3, 2, 1))
    p.emit(store(3, 20, 0, "sd"))
    p.emit(load(4, 20, 0, "ld"))
    p.emit(addi(5, 4, 1))
    p.emit(store(5, 20, 8, "sd"))

    p.emit(addi(6, 0, 1))
    p.emit_branch("beq", 6, 6, "branch_taken")
    p.emit(store(6, 20, 0x3F8, "sd"))  # must be flushed
    p.label("branch_taken")
    p.emit(addi(7, 0, 7))
    p.emit(store(7, 20, 16, "sd"))
    p.emit_branch("bne", 7, 7, "failure")
    p.emit(addi(8, 0, 8))

    p.emit_jal(9, "after_jal")
    p.emit(addi(8, 0, 99))  # must be flushed
    p.label("after_jal")
    p.emit(addi(8, 8, 1))
    p.emit(store(8, 20, 24, "sd"))
    p.emit(store(9, 20, 32, "sd"))

    # AUIPC + ADDI + JALR exercises an indirect control transfer.
    jalr_auipc_index = len(p.words)
    p.emit(auipc(10, 0))
    p.emit(0)  # patched ADDI below after target label is known
    p.emit(jalr(11, 10, 0))
    p.emit(store(6, 20, 0x3F0, "sd"))  # must be flushed
    p.label("after_jalr")
    p.emit(addi(12, 0, 12))
    p.emit(store(12, 20, 40, "sd"))
    p.emit(store(11, 20, 48, "sd"))

    # 64-bit ALU and shifts.
    p.emit(addi(13, 0, -8))
    p.emit(srai(14, 13, 2))
    p.emit(srli(15, 13, 2))
    p.emit(slli(16, 1, 33))
    p.emit(sub(21, 5, 1))
    p.emit(and_(22, 5, 3))
    p.emit(or_(23, 5, 3))
    p.emit(xor_(24, 5, 3))
    p.emit(slt(25, 13, 0))
    p.emit(sltu(26, 13, 0))
    for reg, off in ((14, 56), (15, 64), (16, 72), (21, 80), (22, 88), (23, 96), (24, 104), (25, 112), (26, 120)):
        p.emit(store(reg, 20, off, "sd"))

    # RV64 word ALU operations (results are sign-extended from bit 31).
    p.emit(lui(17, 0x80000))
    p.emit(addiw(17, 17, -1))
    p.emit(slliw(18, 1, 31))
    p.emit(srliw(19, 18, 31))
    p.emit(sraiw(27, 18, 31))
    p.emit(addw(28, 17, 6))
    p.emit(subw(29, 17, 6))
    p.emit(sllw(30, 1, 6))
    p.emit(srlw(31, 18, 6))
    # x6 still contains one and supplies the register shift amount.
    for reg, off in ((17, 128), (18, 136), (19, 144), (27, 152), (28, 160), (29, 168), (30, 176), (31, 184)):
        p.emit(store(reg, 20, off, "sd"))

    # Different-width stores and loads, including signed and unsigned forms.
    p.emit(addi(22, 0, -1))
    p.emit(store(22, 20, 256, "sb"))
    p.emit(addi(22, 0, 127))
    p.emit(store(22, 20, 257, "sb"))
    p.emit(addi(22, 0, -2))
    p.emit(store(22, 20, 258, "sh"))
    p.emit(lui(22, 0x12345))
    p.emit(addi(22, 22, 0x678))
    p.emit(store(22, 20, 260, "sw"))
    p.emit(load(23, 20, 256, "lb"))
    p.emit(load(24, 20, 256, "lbu"))
    p.emit(load(25, 20, 258, "lh"))
    p.emit(load(26, 20, 258, "lhu"))
    p.emit(load(27, 20, 260, "lw"))
    p.emit(load(28, 20, 260, "lwu"))
    p.emit(store(18, 20, 268, "sw"))
    p.emit(load(29, 20, 268, "lw"))
    p.emit(load(30, 20, 268, "lwu"))
    for reg, off in ((23, 192), (24, 200), (25, 208), (26, 216), (27, 224), (28, 232), (29, 240), (30, 248)):
        p.emit(store(reg, 20, off, "sd"))
    p.emit_jal(0, "done")
    p.label("failure")
    p.emit(addi(31, 0, -1))
    p.emit(store(31, 20, 0x3F8, "sd"))
    p.label("done")
    p.emit(ecall())

    # The ADDI feeding JALR uses the target's PC relative to the AUIPC.
    target = p.labels["after_jalr"]
    auipc_pc = BASE + jalr_auipc_index * 4
    delta = target - auipc_pc
    if not -2048 <= delta < 2048:
        raise ValueError("JALR target does not fit the smoke image's ADDI")
    p.words[jalr_auipc_index + 1] = addi(10, 10, delta)
    p.resolve()
    return p


def make_image() -> bytes:
    p = build_program()
    image = bytearray(IMAGE_SIZE)
    for index, word in enumerate(p.words):
        image[index * 4 : index * 4 + 4] = word.to_bytes(4, "little")
    return bytes(image)


def write_hex(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = make_image()
    path.write_text("\n".join(f"{byte:02x}" for byte in image) + "\n", encoding="ascii")


def and_(rd: int, rs1: int, rs2: int) -> int:
    return r_type(0x00, rs2, rs1, 0x7, rd)


def or_(rd: int, rs1: int, rs2: int) -> int:
    return r_type(0x00, rs2, rs1, 0x6, rd)


def xor_(rd: int, rs1: int, rs2: int) -> int:
    return r_type(0x00, rs2, rs1, 0x4, rd)


if __name__ == "__main__":
    output = Path(__file__).resolve().parents[1] / "sim" / "generated" / "rv64i_smoke.hex"
    write_hex(output)
    print(f"wrote {output} ({IMAGE_SIZE} bytes, {len(build_program().words)} instructions)")
