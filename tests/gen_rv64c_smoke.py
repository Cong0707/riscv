#!/usr/bin/env python3
"""Generate a mixed-width RV64C core-integration smoke image."""

from __future__ import annotations

from pathlib import Path

from gen_rv64i_smoke import BASE, IMAGE_SIZE, addi, auipc, lui, store


MASK64 = (1 << 64) - 1


def _reg(reg: int) -> int:
    if not 0 <= reg < 32:
        raise ValueError(f"register out of range: x{reg}")
    return reg


def _compact(reg: int) -> int:
    if not 8 <= reg <= 15:
        raise ValueError(f"compressed register must be x8..x15: x{reg}")
    return reg - 8


def _signed(value: int, bits: int) -> int:
    if not -(1 << (bits - 1)) <= value < (1 << (bits - 1)):
        raise ValueError(f"immediate {value} does not fit signed {bits} bits")
    return value & ((1 << bits) - 1)


def c_addi4spn(rd: int, imm: int) -> int:
    if imm == 0 or imm & 3 or not 0 <= imm < 1024:
        raise ValueError("C.ADDI4SPN immediate must be a nonzero 10-bit multiple of four")
    return (
        (((imm >> 4) & 0x3) << 11)
        | (((imm >> 6) & 0xF) << 7)
        | (((imm >> 2) & 1) << 6)
        | (((imm >> 3) & 1) << 5)
        | (_compact(rd) << 2)
    )


def _c_load_store(operation: str, reg: int, base: int, imm: int) -> int:
    funct3 = {"lw": 0b010, "ld": 0b011, "sw": 0b110, "sd": 0b111}[operation]
    scale = 4 if operation in {"lw", "sw"} else 8
    limit = 128 if scale == 4 else 256
    if imm & (scale - 1) or not 0 <= imm < limit:
        raise ValueError(f"C.{operation.upper()} offset is invalid: {imm}")
    value = (funct3 << 13) | (_compact(base) << 7) | (_compact(reg) << 2)
    value |= ((imm >> 3) & 0x7) << 10
    if scale == 4:
        value |= ((imm >> 2) & 1) << 6
        value |= ((imm >> 6) & 1) << 5
    else:
        value |= ((imm >> 6) & 0x3) << 5
    return value


def c_lw(rd: int, rs1: int, imm: int) -> int:
    return _c_load_store("lw", rd, rs1, imm)


def c_ld(rd: int, rs1: int, imm: int) -> int:
    return _c_load_store("ld", rd, rs1, imm)


def c_sw(rs2: int, rs1: int, imm: int) -> int:
    return _c_load_store("sw", rs2, rs1, imm)


def c_sd(rs2: int, rs1: int, imm: int) -> int:
    return _c_load_store("sd", rs2, rs1, imm)


def _ci(funct3: int, rd: int, imm: int, quadrant: int = 0b01) -> int:
    value = _signed(imm, 6)
    return (
        (funct3 << 13)
        | (((value >> 5) & 1) << 12)
        | (_reg(rd) << 7)
        | ((value & 0x1F) << 2)
        | quadrant
    )


def c_addi(rd: int, imm: int) -> int:
    return _ci(0b000, rd, imm)


def c_addiw(rd: int, imm: int) -> int:
    if rd == 0:
        raise ValueError("C.ADDIW rd cannot be x0")
    return _ci(0b001, rd, imm)


def c_li(rd: int, imm: int) -> int:
    return _ci(0b010, rd, imm)


def c_lui(rd: int, imm: int) -> int:
    if rd in {0, 2} or imm == 0:
        raise ValueError("C.LUI needs rd other than x0/x2 and a nonzero immediate")
    return _ci(0b011, rd, imm)


def c_addi16sp(imm: int) -> int:
    value = _signed(imm, 10)
    if imm == 0 or imm & 0xF:
        raise ValueError("C.ADDI16SP immediate must be a nonzero multiple of 16")
    return (
        (0b011 << 13)
        | (((value >> 9) & 1) << 12)
        | (2 << 7)
        | (((value >> 4) & 1) << 6)
        | (((value >> 6) & 1) << 5)
        | (((value >> 7) & 0x3) << 3)
        | (((value >> 5) & 1) << 2)
        | 0b01
    )


def _c_shift(kind: str, rd: int, shamt: int) -> int:
    if not 8 <= rd <= 15 or not 0 <= shamt < 64:
        raise ValueError("compressed shift requires x8..x15 and a 6-bit shift")
    selector = {"srli": 0b00, "srai": 0b01}[kind]
    return (
        (0b100 << 13)
        | (((shamt >> 5) & 1) << 12)
        | (selector << 10)
        | (_compact(rd) << 7)
        | ((shamt & 0x1F) << 2)
        | 0b01
    )


def c_srli(rd: int, shamt: int) -> int:
    return _c_shift("srli", rd, shamt)


def c_srai(rd: int, shamt: int) -> int:
    return _c_shift("srai", rd, shamt)


def c_andi(rd: int, imm: int) -> int:
    value = _signed(imm, 6)
    return (
        (0b100 << 13)
        | (((value >> 5) & 1) << 12)
        | (0b10 << 10)
        | (_compact(rd) << 7)
        | ((value & 0x1F) << 2)
        | 0b01
    )


def c_alu(kind: str, rd: int, rs2: int) -> int:
    word = kind in {"subw", "addw"}
    op = {
        "sub": 0b00, "xor": 0b01, "or": 0b10, "and": 0b11,
        "subw": 0b00, "addw": 0b01,
    }[kind]
    return (
        (0b100 << 13)
        | (int(word) << 12)
        | (0b11 << 10)
        | (_compact(rd) << 7)
        | (op << 5)
        | (_compact(rs2) << 2)
        | 0b01
    )


def c_j(offset: int) -> int:
    value = _signed(offset, 12)
    if offset & 1:
        raise ValueError("C.J target must be 2-byte aligned")
    return (
        (0b101 << 13)
        | (((value >> 11) & 1) << 12)
        | (((value >> 4) & 1) << 11)
        | (((value >> 8) & 0x3) << 9)
        | (((value >> 10) & 1) << 8)
        | (((value >> 6) & 1) << 7)
        | (((value >> 7) & 1) << 6)
        | (((value >> 1) & 0x7) << 3)
        | (((value >> 5) & 1) << 2)
        | 0b01
    )


def c_branch(kind: str, rs1: int, offset: int) -> int:
    if kind not in {"beqz", "bnez"}:
        raise ValueError(f"unknown compressed branch: {kind}")
    value = _signed(offset, 9)
    if offset & 1:
        raise ValueError("compressed branch target must be 2-byte aligned")
    funct3 = 0b110 if kind == "beqz" else 0b111
    return (
        (funct3 << 13)
        | (((value >> 8) & 1) << 12)
        | (((value >> 3) & 0x3) << 10)
        | (_compact(rs1) << 7)
        | (((value >> 6) & 0x3) << 5)
        | (((value >> 1) & 0x3) << 3)
        | (((value >> 5) & 1) << 2)
        | 0b01
    )


def c_slli(rd: int, shamt: int) -> int:
    if not 0 <= shamt < 64:
        raise ValueError("C.SLLI needs a 6-bit shift amount")
    return (
        (((shamt >> 5) & 1) << 12)
        | (_reg(rd) << 7)
        | ((shamt & 0x1F) << 2)
        | 0b10
    )


def _c_stack_load(kind: str, rd: int, imm: int) -> int:
    scale = 4 if kind == "lw" else 8
    limit = 256 if kind == "lw" else 512
    if rd == 0 or imm & (scale - 1) or not 0 <= imm < limit:
        raise ValueError(f"C.{kind.upper()}SP operands are invalid")
    value = ((0b010 if kind == "lw" else 0b011) << 13) | (_reg(rd) << 7) | 0b10
    value |= ((imm >> 5) & 1) << 12
    if kind == "lw":
        value |= ((imm >> 2) & 0x7) << 4
        value |= ((imm >> 6) & 0x3) << 2
    else:
        value |= ((imm >> 3) & 0x3) << 5
        value |= ((imm >> 6) & 0x7) << 2
    return value


def c_lwsp(rd: int, imm: int) -> int:
    return _c_stack_load("lw", rd, imm)


def c_ldsp(rd: int, imm: int) -> int:
    return _c_stack_load("ld", rd, imm)


def _c_stack_store(kind: str, rs2: int, imm: int) -> int:
    scale = 4 if kind == "sw" else 8
    limit = 256 if kind == "sw" else 512
    if imm & (scale - 1) or not 0 <= imm < limit:
        raise ValueError(f"C.{kind.upper()}SP offset is invalid")
    value = ((0b110 if kind == "sw" else 0b111) << 13) | (_reg(rs2) << 2) | 0b10
    if kind == "sw":
        value |= ((imm >> 2) & 0xF) << 9
        value |= ((imm >> 6) & 0x3) << 7
    else:
        value |= ((imm >> 3) & 0x7) << 10
        value |= ((imm >> 6) & 0x7) << 7
    return value


def c_swsp(rs2: int, imm: int) -> int:
    return _c_stack_store("sw", rs2, imm)


def c_sdsp(rs2: int, imm: int) -> int:
    return _c_stack_store("sd", rs2, imm)


def _cr(rd_rs1: int, rs2: int, bit12: int) -> int:
    return (
        (0b100 << 13)
        | ((bit12 & 1) << 12)
        | (_reg(rd_rs1) << 7)
        | (_reg(rs2) << 2)
        | 0b10
    )


def c_jr(rs1: int) -> int:
    if rs1 == 0:
        raise ValueError("C.JR rs1 cannot be x0")
    return _cr(rs1, 0, 0)


def c_mv(rd: int, rs2: int) -> int:
    if rs2 == 0:
        raise ValueError("C.MV rs2 cannot be x0")
    return _cr(rd, rs2, 0)


def c_jalr(rs1: int) -> int:
    if rs1 == 0:
        raise ValueError("C.JALR rs1 cannot be x0")
    return _cr(rs1, 0, 1)


def c_add(rd: int, rs2: int) -> int:
    if rs2 == 0:
        raise ValueError("C.ADD rs2 cannot be x0")
    return _cr(rd, rs2, 1)


def c_ebreak() -> int:
    return 0x9002


class MixedProgram:
    def __init__(self) -> None:
        self.data = bytearray()
        self.labels: dict[str, int] = {}
        self.fixups: list[tuple] = []
        self.signatures: list[tuple[str, int]] = []

    @property
    def pc(self) -> int:
        return len(self.data)

    def emit16(self, instruction: int) -> None:
        self.data.extend((instruction & 0xFFFF).to_bytes(2, "little"))

    def emit32(self, instruction: int) -> None:
        self.data.extend((instruction & 0xFFFF_FFFF).to_bytes(4, "little"))

    def label(self, name: str) -> None:
        if name in self.labels:
            raise ValueError(f"duplicate label: {name}")
        self.labels[name] = self.pc

    def jump(self, label: str) -> None:
        offset = self.pc
        self.emit16(0)
        self.fixups.append(("jump", offset, label))

    def branch(self, kind: str, rs1: int, label: str) -> None:
        offset = self.pc
        self.emit16(0)
        self.fixups.append(("branch", offset, kind, rs1, label))

    def pcrel_address(self, rd: int, label: str) -> None:
        base = self.pc
        self.emit32(auipc(rd, 0))
        patch = self.pc
        self.emit32(addi(rd, rd, 0))
        self.fixups.append(("pcrel", patch, base, rd, label))

    def signature(self, reg: int, expected: int, name: str) -> None:
        self.emit32(store(reg, 20, len(self.signatures) * 8, "sd"))
        self.signatures.append((name, expected & MASK64))

    def resolve(self) -> None:
        for fixup in self.fixups:
            kind, offset, *args = fixup
            if kind == "jump":
                (label,) = args
                instruction = c_j(self.labels[label] - offset)
                self.data[offset : offset + 2] = instruction.to_bytes(2, "little")
            elif kind == "branch":
                branch_kind, rs1, label = args
                instruction = c_branch(branch_kind, rs1, self.labels[label] - offset)
                self.data[offset : offset + 2] = instruction.to_bytes(2, "little")
            elif kind == "pcrel":
                base, rd, label = args
                instruction = addi(rd, rd, self.labels[label] - base)
                self.data[offset : offset + 4] = instruction.to_bytes(4, "little")
            else:
                raise AssertionError(f"unknown fixup: {kind}")


def build_program() -> MixedProgram:
    p = MixedProgram()
    p.emit32(auipc(20, 1))
    p.emit32(addi(2, 20, 0x300))
    p.emit16(c_addi(0, 0))  # C.NOP; forces the next 32-bit instruction to straddle.
    p.emit32(addi(3, 0, 5))
    p.signature(3, 5, "cross-word addi")

    p.emit16(c_addi(3, 3))
    p.signature(3, 8, "c.addi")
    p.emit16(c_addiw(3, -1))
    p.signature(3, 7, "c.addiw")
    p.emit16(c_li(4, -5))
    p.signature(4, -5, "c.li")
    p.emit16(c_lui(5, 1))
    p.signature(5, 0x1000, "c.lui")

    p.emit16(c_addi16sp(16))
    p.signature(2, BASE + 0x1310, "c.addi16sp")
    p.emit16(c_addi16sp(-16))
    p.emit16(c_addi4spn(8, 32))
    p.signature(8, BASE + 0x1320, "c.addi4spn")

    p.emit16(c_li(9, 21))
    p.emit16(c_sd(9, 8, 0))
    p.emit16(c_ld(10, 8, 0))
    p.signature(10, 21, "c.sd/c.ld")
    p.emit16(c_li(11, -1))
    p.emit16(c_sw(11, 8, 8))
    p.emit16(c_lw(12, 8, 8))
    p.signature(12, -1, "c.sw/c.lw")

    p.emit16(c_li(13, 31))
    p.emit16(c_addi(13, 2))
    p.emit16(c_sdsp(13, 64))
    p.emit16(c_ldsp(14, 64))
    p.signature(14, 33, "c.sdsp/c.ldsp")
    p.emit16(c_li(13, -2))
    p.emit16(c_swsp(13, 72))
    p.emit16(c_lwsp(15, 72))
    p.signature(15, -2, "c.swsp/c.lwsp")

    p.emit16(c_li(8, 1))
    p.emit16(c_slli(8, 5))
    p.signature(8, 32, "c.slli")
    p.emit16(c_srli(8, 2))
    p.signature(8, 8, "c.srli")
    p.emit16(c_li(8, -16))
    p.emit16(c_srai(8, 2))
    p.signature(8, -4, "c.srai")
    p.emit16(c_andi(8, 6))
    p.signature(8, 4, "c.andi")

    for kind, expected in (("sub", 17), ("xor", 23), ("or", 23), ("and", 0)):
        p.emit16(c_li(8, 20))
        p.emit16(c_li(9, 3))
        p.emit16(c_alu(kind, 8, 9))
        p.signature(8, expected, f"c.{kind}")

    p.emit32(lui(8, 0x80000))
    p.emit16(c_li(9, 1))
    p.emit16(c_alu("subw", 8, 9))
    p.signature(8, 0x7FFF_FFFF, "c.subw")
    p.emit32(lui(8, 0x80000))
    p.emit16(c_alu("addw", 8, 9))
    p.signature(8, 0xFFFF_FFFF_8000_0001, "c.addw")

    p.emit16(c_mv(6, 9))
    p.signature(6, 1, "c.mv")
    p.emit16(c_add(6, 9))
    p.signature(6, 2, "c.add")

    p.emit16(c_li(8, 0))
    p.branch("beqz", 8, "beqz_taken")
    p.emit16(c_li(7, -7))
    p.jump("beqz_done")
    p.label("beqz_taken")
    p.emit16(c_li(7, 1))
    p.label("beqz_done")
    p.signature(7, 1, "c.beqz taken")

    p.emit16(c_li(8, 1))
    p.branch("bnez", 8, "bnez_taken")
    p.emit16(c_li(7, -7))
    p.jump("bnez_done")
    p.label("bnez_taken")
    p.emit16(c_li(7, 2))
    p.label("bnez_done")
    p.signature(7, 2, "c.bnez taken")

    p.emit16(c_li(8, 1))
    p.branch("beqz", 8, "beqz_bad")
    p.emit16(c_li(7, 3))
    p.jump("beqz_not_done")
    p.label("beqz_bad")
    p.emit16(c_li(7, -7))
    p.label("beqz_not_done")
    p.signature(7, 3, "c.beqz not taken")

    p.emit16(c_li(8, 0))
    p.branch("bnez", 8, "bnez_bad")
    p.emit16(c_li(7, 4))
    p.jump("bnez_not_done")
    p.label("bnez_bad")
    p.emit16(c_li(7, -7))
    p.label("bnez_not_done")
    p.signature(7, 4, "c.bnez not taken")

    p.jump("jump_taken")
    p.emit16(c_li(7, -7))
    p.jump("jump_done")
    p.label("jump_taken")
    p.emit16(c_li(7, 5))
    p.label("jump_done")
    p.signature(7, 5, "c.j")

    p.pcrel_address(5, "call_target")
    p.emit16(c_jalr(5))
    p.label("call_return")
    p.signature(7, 42, "c.jalr/c.jr")
    p.signature(1, BASE + p.labels["call_return"], "c.jalr link")
    p.jump("call_done")
    p.label("call_target")
    p.emit16(c_li(7, 31))
    p.emit16(c_addi(7, 11))
    p.emit16(c_jr(1))
    p.label("call_done")

    p.emit16(c_ebreak())
    p.resolve()
    return p


def make_image() -> bytes:
    program = build_program()
    if len(program.data) >= 0x1000:
        raise ValueError("RV64C program overlaps the signature area")
    image = bytearray(IMAGE_SIZE)
    image[: len(program.data)] = program.data
    return bytes(image)


def write_hex(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = make_image()
    path.write_text("\n".join(f"{byte:02x}" for byte in image) + "\n", encoding="ascii")


if __name__ == "__main__":
    output = Path(__file__).resolve().parents[1] / "sim" / "generated" / "rv64c_smoke.hex"
    program = build_program()
    write_hex(output)
    print(
        f"wrote {output} ({IMAGE_SIZE} bytes, {len(program.data)} program bytes, "
        f"{len(program.signatures)} signatures)"
    )
