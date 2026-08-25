# memory.py

data_memory = {}            # word-addressable
instruction_memory = {}     # PC-indexed

def load_instructions(instrs):
    addr = 0
    for instr in instrs:
        instruction_memory[addr] = instr
        addr += 3  # word-aligned for 24-bit

def fetch(pc):
    return instruction_memory.get(pc, None)
