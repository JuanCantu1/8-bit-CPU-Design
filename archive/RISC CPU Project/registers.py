# registers.py

registers = [0] * 16  # $0–$15, $0 is hardwired to 0

def get(reg_num):
    return 0 if reg_num == 0 else registers[reg_num]

def set_register(reg_num, value):
    if reg_num != 0:
        registers[reg_num] = value

def dump():
    for i, val in enumerate(registers):
        print(f"${i:02}: 0x{val:06X}")

def get(reg_num):
    return 0 if reg_num == 0 else registers[reg_num]
