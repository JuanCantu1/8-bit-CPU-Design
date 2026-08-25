# pipeline.py

from registers import get, set_register
from memory import data_memory, instruction_memory, fetch
from instructions import OPCODES

PC = 0x0000
IF_ID = {}
ID_EX = {}
EX_MEM = {}
MEM_WB = {}

def fetch_stage():
    global PC, IF_ID, EX_MEM

    # Handle jump
    if EX_MEM.get("opcode") == OPCODES["j"]:
        PC = EX_MEM["jump_addr"]
        print(f"JUMP to address 0x{PC:06X}")
        IF_ID = {}
        return

    # Handle branch
    if EX_MEM.get("opcode") in [OPCODES["beq"], OPCODES["bgtz"]] and EX_MEM.get("should_branch"):
        branch_offset = ID_EX["imm"] * 3
        PC = ID_EX["PC"] + branch_offset
        print(f"BRANCH to address 0x{PC:06X}")
        IF_ID = {}
        return

    # Guard to prevent garbage fetches
    if PC not in instruction_memory:
        print(f"HALT: PC=0x{PC:06X} has no instruction")
        IF_ID = {}
        return

    print(f"FETCH: PC=0x{PC:06X}")
    instr = fetch(PC)
    IF_ID = {"instr": instr, "PC": PC}
    PC += 3



def decode_stage():
    global IF_ID, ID_EX
    instr = IF_ID.get("instr")
    if instr is None:
        ID_EX.clear()
        return

    opcode = (instr >> 19) & 0x1F
    rs = (instr >> 15) & 0xF
    rt = (instr >> 11) & 0xF
    rd = (instr >> 7) & 0xF  # extract rd for R-type
    imm = instr & 0x7FF

    if imm & 0x400:
        imm |= ~0x7FF  # sign extend 11-bit immediate

    ID_EX.update({
        "opcode": opcode,
        "rs": rs,
        "rt": rt,
        "rd": rd,
        "imm": imm,
        "reg_rs_val": get(rs),
        "reg_rt_val": get(rt),
        "PC": IF_ID["PC"]
    })
    

def execute_stage():
    global ID_EX, EX_MEM
    if not ID_EX or ID_EX.get("NOP", False):
        EX_MEM = {"NOP": True}
        return

    opcode = ID_EX["opcode"]
    print(f"EXEC: opcode={opcode} ({[k for k,v in OPCODES.items() if v==opcode][0]})")
    alu_result = 0
    funct = ID_EX.get("funct", 0)
    should_branch = False

    if opcode == OPCODES["addi"]:
        alu_result = ID_EX["reg_rs_val"] + ID_EX["imm"]
    elif opcode == OPCODES["ori"]:
        alu_result = ID_EX["reg_rs_val"] | ID_EX["imm"]
    elif opcode == OPCODES["lw"] or opcode == OPCODES["sw"]:
        alu_result = ID_EX["reg_rs_val"] + ID_EX["imm"]
    elif opcode == OPCODES["bgtz"]:
        should_branch = ID_EX["reg_rs_val"] > 0
    elif opcode == OPCODES["beq"]:
        should_branch = ID_EX["reg_rs_val"] == ID_EX["reg_rt_val"]
    elif opcode == OPCODES["j"]:
        imm = ID_EX["imm"] & 0x7FF  
        PC_offset = imm
        EX_MEM = {"opcode": opcode, "jump_addr": ID_EX["PC"] + PC_offset}
        return
    elif opcode == OPCODES["r_type"]:
        funct = ID_EX["imm"] & 0b1111111  # last 7 bits for funct
        rs_val = ID_EX["reg_rs_val"]
        rt_val = ID_EX["reg_rt_val"]

        if funct == 0b0000010:  # mul
            alu_result = rs_val * rt_val
        elif funct == 0b0000001:  # sub
            alu_result = rs_val - rt_val
        elif funct == 0b0000011:  # xor
            alu_result = rs_val ^ rt_val
        elif funct == 0b0000100:  # srl
            alu_result = rs_val >> 1
        elif funct == 0b0000101:  # sll
            alu_result = rs_val << 1
        elif funct == 0b0000000:  # add
            alu_result = rs_val + rt_val
        elif funct == 0b0001000:  # nor
            alu_result = ~(rs_val | rt_val)
        elif funct == 0b0000110:  # and
            alu_result = rs_val & rt_val
        elif funct == 0b0000111:  # or
            alu_result = rs_val | rt_val
    

    # Determine correct destination register
    dest_reg = ID_EX["rt"]
    if opcode == OPCODES["r_type"]:
        dest_reg = ID_EX["rd"]

    EX_MEM = {
    "opcode": opcode,
    "alu_result": alu_result,
    "reg_rt_val": ID_EX.get("reg_rt_val", 0),
    "dest_reg": dest_reg,
    "should_branch": should_branch,
    "PC": ID_EX.get("PC", 0)
}


def memory_stage():
    global EX_MEM, MEM_WB
    op = EX_MEM.get("opcode")
    addr = EX_MEM.get("alu_result")
    result = None
    if op == OPCODES["lw"]:
        result = data_memory.get(addr, 0)
    elif op == OPCODES["sw"]:
        data_memory[addr] = EX_MEM["reg_rt_val"]
        print(f"MEM: sw 0x{EX_MEM['reg_rt_val']:06X} → [0x{addr:06X}]")
    MEM_WB.update({
        "opcode": op,
        "alu_result": addr,
        "mem_data": result,
        "dest_reg": EX_MEM.get("dest_reg")
    })

def write_back_stage():
    global MEM_WB
    if not MEM_WB or MEM_WB.get("NOP", False):
        print("WB: NOP or empty")
        return

    op = MEM_WB.get("opcode")
    print(f"WB: opcode={op}, dest=${MEM_WB.get('dest_reg')}, result={MEM_WB.get('alu_result')}, mem_data={MEM_WB.get('mem_data')}")

    if op in [OPCODES["addi"], OPCODES["ori"]]:
        set_register(MEM_WB["dest_reg"], MEM_WB["alu_result"])
    elif op == OPCODES["lw"]:
        set_register(MEM_WB["dest_reg"], MEM_WB["mem_data"])
