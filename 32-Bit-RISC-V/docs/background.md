# The problem, from the ground up

## RISC vs. CISC

"RISC" = Reduced Instruction Set Computer. The philosophy: instead of giving the CPU a huge, irregular menu of complex instructions (like x86, a CISC design), you give it a small set of simple, fixed-size, uniformly-encoded instructions that each do one small thing (add, load, branch, etc.) and each aim to execute in close to one cycle. The payoff is that a simple, regular instruction format is *much* easier to pipeline efficiently — which is exactly why "RISC" and "pipelining" are basically joined at the hip in every architecture course.

## What RISC-V specifically is

RISC-V is an open (royalty-free, publicly specified) RISC instruction set. It's modular: there's a small mandatory base (RV32I = 32-bit base integer ISA) and then optional extensions bolted on — "M" for multiply/divide, "C" for compressed 16-bit instructions, "F"/"D" for floating point, etc. For a first CPU, RV32I alone is a very reasonable, complete target: 32 general-purpose registers (x0 hardwired to zero), fixed 32-bit instruction width, six instruction formats (R/I/S/B/U/J), load-store architecture (only `lw`/`sw`-style instructions touch memory — everything else operates on registers).

## The six instruction formats

Every RV32I instruction is exactly 32 bits, and there are only six ways those bits get carved up: R-type (register-register ops like `add`), I-type (register-immediate ops like `addi`, plus loads and `jalr`), S-type (stores), B-type (branches), U-type (instructions that just need one big 20-bit immediate, like `lui`), and J-type (`jal`). The genuinely clever part isn't the formats themselves — it's that `opcode`, `rd`, `funct3`, `rs1`, and `rs2` always live in the *same* bit positions across every format that uses them. A decoder never has to ask "which format is this?" before it can find `rs1` — it just always reads bits [19:15]. Only the immediate field gets scrambled around (particularly in B-type and J-type, where the bits are deliberately reordered so the sign bit always lands at position 31, making sign-extension trivial regardless of format). This is a hardware-design decision as much as an ISA one: it's what lets a decoder be a dumb, fast bit-slicer instead of a multi-way branch.

## The single-cycle datapath

The most natural first CPU design executes one instruction per clock cycle, full stop: fetch the instruction, decode it, read registers, run it through the ALU, touch memory if needed, write the result back — all as one long combinational pass, latched into the program counter and register file at the end of the cycle. It's simple to reason about (exactly one instruction is ever "in progress" at a time) and has a clean cost model: CPI (cycles per instruction) is exactly 1.0, always, by construction.

The catch is the clock period. Every instruction — even a trivial register-to-register `add` — has to wait out a clock cycle long enough for the *slowest* instruction to finish its entire trip through fetch, decode, ALU, memory, and writeback, because the hardware doesn't know in advance which instruction is coming. A load, which has to wait on a memory access on top of everything else, sets the clock period for every single instruction, including the ones that never touch memory at all. That wasted slack is the whole reason pipelining exists.

## Why pipeline

The fix looks like a factory assembly line: instead of one instruction occupying the *entire* datapath for a whole cycle, split the datapath into stages (fetch, decode, execute, memory, writeback) and let a *different* instruction occupy each stage at the same time. Instruction 1 is in memory-access while instruction 2 is in the ALU while instruction 3 is being decoded while instruction 4 is being fetched — four instructions in flight simultaneously, one per stage.

This doesn't make any single instruction finish faster — in fact an individual instruction now takes 5 cycles start to finish instead of 1, which is strictly *more* latency. What it buys is throughput: once the pipeline is full, a new instruction can start every single cycle instead of waiting for the previous one to completely retire. And because each stage now only has to do a fifth of the original work, each stage's logic is shorter, which means the clock period can shrink to roughly match the slowest *stage* instead of the slowest whole-instruction path. That shorter clock period — not doing more work per cycle, but doing each cycle faster — is where a pipeline's real speedup comes from. It also means CPI can only ever approach 1.0 from above in a simple scalar pipeline like this one; the win is a higher clock frequency, not a lower cycle count, which is a distinction worth holding onto since it's easy to accidentally look for the speedup in the wrong place.

## Hazards: the cost of overlapping

Overlap isn't free, though — the moment two instructions are "in flight" at once, they can interfere with each other, and there are three classic ways that happens:

- **Structural hazards** — two instructions need the same piece of hardware at the same time. The obvious one here: if instruction fetch and a data load/store both had to go through a single shared memory, they'd collide every time a load overlaps with fetching a later instruction. The standard fix, used here, is just giving fetch and data access their own separate memories (a Harvard-style split) so the conflict can't happen in the first place.
- **Data hazards** — a later instruction needs a value a still-in-flight earlier instruction hasn't produced yet (the read-after-write, or RAW, case — by far the common one in a simple in-order pipeline like this).
- **Control hazards** — a branch or jump's outcome isn't known until it reaches whichever pipeline stage evaluates the condition, but the pipeline has already been happily fetching whatever comes sequentially after it in the meantime, on the assumption that nothing was about to redirect the PC.

## Data hazards and forwarding

The concrete RAW scenario: `add x1, x2, x3` immediately followed by `sub x4, x1, x5`. By the time the `sub` reaches the stage where it needs `x1`, the `add` hasn't finished writing `x1` back to the register file yet — it's still further down the pipeline. The brute-force fix is to just stall the `sub` (and everything behind it) until the `add`'s result is safely written back and readable, which works but wastes cycles on an extremely common pattern (back-to-back dependent instructions show up constantly in real code).

The better fix is forwarding (also called bypassing): instead of making the `sub` wait for the register file, route the `add`'s result directly from wherever it currently sits in the pipeline (its own execute-stage output, or the stage after that) straight into the `sub`'s ALU input, bypassing the register file entirely for that one read. Done right, this closes almost every RAW hazard with zero stall cost. The one case forwarding structurally can't close on its own is load-use: a loaded value isn't available until the memory-access stage completes, one stage later than an ALU result would be, so an instruction that immediately consumes a just-loaded register still needs exactly one stall cycle before forwarding can supply it.

## Control hazards and why branches are expensive

Branches are the hazard type without a clean fix, only trade-offs. The pipeline has to keep fetching *something* every cycle, and it doesn't find out whether a branch was taken — or what a jump's computed target even is — until that instruction reaches whichever stage resolves it. Every instruction fetched in the meantime, on the assumption of straight-line sequential execution, has to be thrown away (flushed) if the branch turns out to redirect the PC.

The stage a design chooses to resolve branches in is a genuine trade-off, not a solved problem: resolving earlier in the pipeline means fewer instructions get speculatively fetched and flushed on a taken branch, but it also means the branch has to make its decision before some of the pipeline's other machinery (like forwarding paths that only become available in later stages) is ready to help it — so an earlier resolution point can end up *costing* more than it saves, depending on what kind of code is actually running. Real CPUs sidestep the trade-off with branch prediction — guessing the outcome instead of waiting to resolve it, and only paying the flush cost when the guess is wrong — but prediction is its own substantial design space and out of scope here; this project always pays the flush cost on a taken branch or jump, deterministically.

