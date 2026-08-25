# instructions.py

OPCODES = {
    "addi": 0b00001,
    "ori":  0b00010,
    "slti": 0b00011,
    "lw":   0b00100,
    "sw":   0b00101,
    "beq":  0b00110,
    "bgtz": 0b00111,
    "j":    0b01000,
    "r_type": 0b00000
}

def encode_i_type(opcode, rs, rt, imm):
    imm &= 0x7FF
    return (opcode << 19) | (rs << 15) | (rt << 11) | imm

def encode_r_type(opcode, rs, rt, rd, funct):
    return (opcode << 19) | (rs << 15) | (rt << 11) | (rd << 7) | (funct & 0x7F)

def encode_j_type(opcode, offset):
    addr = (offset * 3) & 0x7FF  # 11-bit immediate
    return (opcode << 19) | addr

PROGRAM = [
    encode_i_type(OPCODES["addi"], 0, 1, 1),
    encode_i_type(OPCODES["addi"], 0, 2, 1),
    encode_i_type(OPCODES["ori"],  0, 3, 255),
    encode_i_type(OPCODES["addi"], 0, 4, 15),
    encode_i_type(OPCODES["addi"], 0, 5, 0),
    encode_i_type(OPCODES["addi"], 0, 6, 16),
    encode_i_type(OPCODES["addi"], 0, 7, 5),
    encode_i_type(OPCODES["lw"],   0, 8, 256),
    encode_i_type(OPCODES["bgtz"], 7, 0, 2),
    encode_j_type(OPCODES["j"], 4),         # j exit
    encode_i_type(OPCODES["addi"], 7, 7, -1),
    encode_i_type(OPCODES["lw"],   6, 5, 0),
    encode_i_type(OPCODES["addi"], 6, 6, 3),
    encode_i_type(OPCODES["bgtz"], 5, 0, 2),
    encode_j_type(OPCODES["j"], 6),         # j else
    encode_r_type(OPCODES["r_type"], 1, 9, 1, 0b0000010),  # mul
    encode_r_type(OPCODES["r_type"], 2, 5, 2, 0b0000011),  # xor
    encode_i_type(OPCODES["sw"],   6, 8, -3),
    encode_j_type(OPCODES["j"], -31),       # j loop
    encode_r_type(OPCODES["r_type"], 3, 1, 3, 0b0000100),  # srl
    encode_r_type(OPCODES["r_type"], 4, 5, 4, 0b0000001),  # sub
    encode_i_type(OPCODES["sw"],   6, 8, -3),
    encode_j_type(OPCODES["j"], -33)        # j loop
]
