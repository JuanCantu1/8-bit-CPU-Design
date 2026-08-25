# main.py

from instructions import PROGRAM
from registers import dump, get as reg_get
from memory import load_instructions, data_memory
from pipeline import (
    fetch_stage, decode_stage, execute_stage,
    memory_stage, write_back_stage,
    MEM_WB
)

load_instructions(PROGRAM)

print("Starting simulation...\n")

cycle_count = 0
loop_snapshots = []
prev_loop_val = None

for _ in range(23):
    cycle_count += 1
    print(f"--- Cycle {cycle_count} ---")
    
    # Reverse stage order 
    write_back_stage()
    memory_stage()
    execute_stage()
    decode_stage()
    fetch_stage()

    # Track loop iterations by monitoring $7 (loop counter)
    current_loop_val = reg_get(7)
    if current_loop_val != prev_loop_val and current_loop_val != 0:
        snapshot = {
            "loop": chr(ord('A') + len(loop_snapshots)),
            "cycle": cycle_count,
            "registers": [reg_get(i) for i in range(16)],
            "memory": dict(data_memory)
        }
        loop_snapshots.append(snapshot)
        prev_loop_val = current_loop_val

    # Exit if loop is complete
    if prev_loop_val is not None and current_loop_val == 0:
        break

print("\nFinal Register Dump:")
dump()
print(f"\n✅ Total Clock Cycles Used: {cycle_count}")

# Section 7 - Report Table Format
for snap in loop_snapshots:
    print(f"\n--- Loop {snap['loop']} (After Cycle {snap['cycle']}) ---")
    print("Register File:")
    for i, val in enumerate(snap["registers"]):
        print(f"${i:02}: 0x{val:06X}")
    print("Data Memory:")
    if snap["memory"]:
        for addr, val in sorted(snap["memory"].items()):
            print(f"0x{addr:06X}: 0x{val:06X}")
    else:
        print("(no memory writes)")

print("\nFinal Data Memory Contents:")
if data_memory:
    for addr, val in sorted(data_memory.items()):
        print(f"0x{addr:06X}: 0x{val:06X}")
else:
    print("(no memory writes)")
    
