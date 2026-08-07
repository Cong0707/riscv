#!/usr/bin/env python3
"""Generate a deterministic RV64A core-integration smoke image."""

from pathlib import Path

from gen_rv64i_smoke import IMAGE_SIZE, Program, addi, auipc, ecall, store


FUNCT5 = {
    "add": 0b00000,
    "swap": 0b00001,
    "lr": 0b00010,
    "sc": 0b00011,
    "xor": 0b00100,
    "or": 0b01000,
    "and": 0b01100,
    "min": 0b10000,
    "max": 0b10100,
    "minu": 0b11000,
    "maxu": 0b11100,
}


def amo(
    operation: str,
    rd: int,
    rs1: int,
    rs2: int,
    *,
    word: bool,
    aq: int = 0,
    rl: int = 0,
) -> int:
    funct3 = 0b010 if word else 0b011
    return (
        (FUNCT5[operation] << 27)
        | ((aq & 1) << 26)
        | ((rl & 1) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (rd << 7)
        | 0x2F
    )


def emit_address(p: Program, data_index: int) -> None:
    p.emit(addi(6, 20, 0x300 + data_index * 8))


def emit_store_value(p: Program, value: int, *, word: bool) -> None:
    p.emit(addi(7, 0, value))
    p.emit(store(7, 6, 0, "sw" if word else "sd"))


def build_program() -> Program:
    p = Program()
    p.emit(auipc(20, 1))

    # Successful LR/SC.W.
    emit_address(p, 0)
    emit_store_value(p, 17, word=True)
    p.emit(amo("lr", 8, 6, 0, word=True, aq=1))
    p.emit(addi(7, 0, 23))
    p.emit(amo("sc", 9, 6, 7, word=True, rl=1))
    p.emit(store(8, 20, 0, "sd"))
    p.emit(store(9, 20, 8, "sd"))

    # Successful LR/SC.D.
    emit_address(p, 1)
    emit_store_value(p, 17, word=False)
    p.emit(amo("lr", 8, 6, 0, word=False, aq=1, rl=1))
    p.emit(addi(7, 0, 23))
    p.emit(amo("sc", 9, 6, 7, word=False))
    p.emit(store(8, 20, 16, "sd"))
    p.emit(store(9, 20, 24, "sd"))

    # A normal store invalidates the reservation, so SC must return one.
    emit_address(p, 2)
    emit_store_value(p, 31, word=False)
    p.emit(amo("lr", 8, 6, 0, word=False))
    emit_store_value(p, 37, word=False)
    p.emit(addi(7, 0, 41))
    p.emit(amo("sc", 9, 6, 7, word=False))
    p.emit(store(9, 20, 32, "sd"))

    cases = (
        ("swap", 5, 9),
        ("add", 5, 3),
        ("xor", 15, 51),
        ("and", 63, 21),
        ("or", 48, 15),
        ("min", -5, 3),
        ("max", -5, 3),
        ("minu", -1, 1),
        ("maxu", -1, 1),
    )
    signature_index = 5
    data_index = 3
    for operation, old_value, operand in cases:
        for word in (True, False):
            emit_address(p, data_index)
            emit_store_value(p, old_value, word=word)
            p.emit(addi(7, 0, operand))
            p.emit(amo(
                operation, 8, 6, 7, word=word,
                aq=data_index & 1, rl=(data_index >> 1) & 1,
            ))
            p.emit(store(8, 20, signature_index * 8, "sd"))
            signature_index += 1
            data_index += 1

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
    output = Path(__file__).resolve().parents[1] / "sim" / "generated" / "rv64a_smoke.hex"
    write_hex(output)
    print(f"wrote {output} ({IMAGE_SIZE} bytes, {len(build_program().words)} instructions)")
