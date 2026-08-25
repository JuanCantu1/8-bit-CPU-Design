# Design notes

## Scope
- ISA: RV32I base only for v1. M extension is a phase-2 stretch goal.
- Target: 5-stage pipeline (IF/ID/EX/MEM/WB), 3-5x throughput over a
  single-cycle baseline.
- Project priorities shifted partway through: the user is targeting
  front-end RTL design/verification roles, not backend/implementation —
  FPGA synthesis and Fmax are lower priority as a result (still on the
  roadmap, just not urgent), and simulation-based verification
  methodology (SVA, functional coverage, constrained-random testing) is
  the higher-value direction to keep investing in for the rest of this
  project.
- Real riscv-tests/riscv-arch-test upstream compliance is deliberately
  on hold for the same reason, plus one more: this is a custom core, not
  one that needs to satisfy strict upstream compliance to be a
  legitimate portfolio piece. The explicit goal for the remainder of
  this project was a coherent stopping point that feels like a complete,
  polished verification story rather than working through every
  conceivable roadmap addition — constrained-random testing against the
  single-cycle reference (done, see "Constrained-random instruction
  testing" below) was the last planned item before that stop. FPGA
  synthesis and real upstream compliance stay on the roadmap as
  deliberately-deferred stretch goals, not abandoned ones.

## Hazard strategy
- Build stall-only interlocking first (simple, correct, slow) — done.
- Upgrade to forwarding (EX/MEM and MEM/WB -> EX) once stall-only passes
  — done; see "Forwarding" below for the full design, including a third
  bypass path stall-only didn't need.
- Load-use hazard still needs one stall cycle even with forwarding.
- Never forward when the source instruction's rd == x0.

## Verification plan
- Per-module directed testbenches first (ALU done, register file done,
  control unit done, decoder done, single-cycle datapath done, hazard
  unit done, naive pipeline done, forwarding unit done, forwarding
  integration done, branch/JAL early-resolution done).
- Full-core testbench: 50+ instruction directed sequence — done
  (tb_full_program.sv).
- Fibonacci program as a functional smoke test — done (tb_fibonacci.sv).
- riscv-tests / riscv-arch-test for ISA-level compliance — attempted;
  no toolchain available, hand-ported compliance-style vectors instead
  (tb_compliance.sv). See "Compliance-style testing" below. Real upstream
  compliance is still wanted eventually — kept as its own separate
  roadmap item rather than folded into the hand-ported version.
- SystemVerilog assertions — done, see "Assertions" below.
- Functional coverage — done, see "Functional coverage" below.
- Constrained-random instruction testing — done, see "Constrained-random
  instruction testing" below. This was the planned final phase before
  treating this project's verification arc as complete — see the
  "Scope" note above.

## Control unit
- Scope: core RV32I only (R/I/S/B/U/J formats). FENCE/ECALL/EBREAK are
  deferred until the riscv-arch-test compliance pass; unrecognized opcodes
  fall through to safe defaults (no register/memory write, no branch/jump).
- Takes opcode/funct3/funct7[5] directly (not the full 32-bit instruction)
  so it's testable in isolation before the decoder exists.
- `result_src` (ALU / MEM / PC+4) lets JAL/JALR write back a link address
  without routing that value through the main ALU — PC+4 is assumed to
  come from a separate incrementer in the fetch stage, standard for
  single-cycle RV32I datapaths.
- `alu_src_a` (RS1 / PC / ZERO) and `alu_src_b` (RS2 / IMM) cover LUI
  (ZERO + IMM) and AUIPC (PC + IMM) without special-casing them outside
  the ALU.
- Branch funct3 maps to alu_op (SUB for BEQ/BNE, SLT for BLT/BGE, SLTU for
  BLTU/BGEU) but does NOT resolve taken/not-taken polarity here — that's
  deferred to the datapath, which combines this alu_op result with funct3
  when the branch comparator/PC-mux logic is built.
- `imm_src` is exposed now (though unused until the decoder exists) since
  it's purely a function of opcode, same as every other control signal.

## Decoder
- Blind bit-slicer: extracts opcode/rd/funct3/rs1/rs2/funct7[5] from fixed
  positions regardless of instruction format, and never interprets them.
  For formats where a slot isn't semantically meaningful (e.g. B-type has
  no rd; U/J-type have no funct3/rs1/rs2), those outputs still carry
  whatever raw bits land in that position — it's the control unit's job
  (via reg_write/branch/jump) to make sure nothing downstream acts on
  them. Caught this the hard way: several directed test cases initially
  assumed those slots would read as 0, which only happened to hold for
  test vectors where the relevant immediate bits were 0.
- `imm_ext` sign-extension is chosen by `imm_src` (from the control unit),
  independent of the blind field slicing above.

## Single-cycle datapath
- Module/file name is `riscv_core_singlecycle` (not just `riscv_core`) on
  purpose — the README's build order keeps this single-cycle version
  around as a reference after the pipelined core exists, so it needed a
  name that won't collide or need renaming later.
- Branches need a second adder separate from the main ALU: for BRANCH
  instructions the ALU is busy computing the rs1/rs2 comparison, so
  `branch_target = pc + imm_ext` is computed independently and only
  muxed into `pc_next` when `branch && branch_taken`. JAL/JALR/AUIPC
  don't have this conflict — control_unit already points
  alu_src_a/alu_src_b at (PC,imm) or (rs1,imm) for those, so the main
  ALU's result IS the jump target / AUIPC value directly, with no extra
  adder needed.
- Branch taken/not-taken polarity (deferred from the control unit,
  per the note above) is resolved here from `alu_zero` (BEQ/BNE) or
  `alu_result[0]` (BLT/BGE/BLTU/BGEU, since the ALU already ran
  SLT/SLTU for those per control_unit's alu_op mapping).
- JALR target clears the LSB (`{alu_result[31:1], 1'b0}`) per spec;
  harmless no-op for JAL since its immediate's bit 0 is always 0.
- Only `pc_reg` resets (to address 0); regfile/imem/dmem don't, matching
  the existing no-reset convention — only the boot address needs a
  defined value.
- imem/dmem are simulation-only for now: no `$readmemh`, contents are
  poked directly into their `mem` arrays via a testbench hierarchical
  reference (`dut.imem_inst.mem[i] = ...`). Fine for directed per-module
  testing; will need a real program-loading path (hex file or similar)
  once the Fibonacci/riscv-tests phases need to load real binaries.
- Testbench gotcha worth remembering for every future clocked testbench:
  `rst_n = 0; @(posedge clk); rst_n = 1;` races the DUT's own
  `posedge`-triggered reset logic, since both the deassertion and the
  DUT's sampling happen in the same simulation time step with
  unspecified relative order. Icarus resolved that race by letting the
  deassertion win, so the DUT's register never saw rst_n low and every
  register stayed X forever. Fix: insert `#1` between the `@(posedge
  clk)` and the deassertion, exactly like the existing `#1` settle delay
  already used in `tb_regfile.sv`'s write task.

## Naive 5-stage pipeline
- Inter-stage registers use packed structs (`if_id_t`/`id_ex_t`/
  `ex_mem_t`/`mem_wb_t` in riscv_pkg.sv) instead of long individual port
  lists — confirmed Icarus supports packed structs (including enum
  members) through clocked module ports before committing to the design.
- Stall-only hazard check (hazard_unit.sv) looks at producers in EX, MEM,
  *and* WB, not just EX/MEM. A producer sitting in WB this cycle hasn't
  committed its regfile write yet (writes are synchronous), so an ID-stage
  read this same cycle would still see the stale value — confirmed by
  tb_regfile.sv's own write-timing tests. This is why an immediately-
  following dependent instruction costs exactly 3 stall cycles: hazard
  clears one stage later each cycle as the producer advances toward WB
  and finally exits the pipeline.
- Deliberately doesn't distinguish loads from other reg_write producers
  (no `mem_read`-gated special case) — that distinction only matters once
  forwarding exists (forwarding eliminates stalls for non-load producers
  but loads still need one stall cycle even then, per the hazard strategy
  above). Stall-only treats every producer identically, so `mem_read`
  stays unconnected at the top level, same as in the single-cycle core.
- IF/ID and ID/EX respond to a stall differently on purpose: IF/ID HOLDS
  (keeps the not-yet-safe instruction parked for a retry), ID/EX BUBBLES
  (so EX doesn't see a stale half-ready instruction while its predecessor
  is stuck in ID). EX/MEM and MEM/WB never stall or bubble — once an
  instruction reaches EX it always proceeds; only IF/ID and ID/EX are
  ever held back.
- A taken branch/jump, resolved in EX (see single-cycle notes above for
  why — same ALU reuse reasoning applies here), flushes IF/ID and ID/EX
  to bubbles and redirects PC, costing a fixed 2-bubble penalty (the
  instructions already fetched into IF and ID were fetched on the wrong
  sequential assumption). Flush takes priority over any same-cycle stall
  request from the ID-stage instruction, since that instruction is being
  discarded anyway. Reducing the 2-bubble penalty (earlier resolution,
  prediction) is left for the later "branch/control hazard handling"
  phase — this phase only needed flush-on-resolve for correctness.
- Icarus gotcha: assignment-pattern literals (`'{field: value, ...}` or
  positional `'{a, b, c}`) are NOT supported for packed structs in this
  Icarus build — named form errors with "sorry: I do not know how to
  elaborate assignment patterns", positional form crashes the elaborator
  outright, and neither works in a continuous `assign` OR inside
  `always_comb`. Whole-struct operations (`dst = src;`, zero-fill
  `dst = '0;`) work fine — it's specifically the field-list literal
  syntax that's broken. Every "build the next-state bundle" assignment in
  riscv_core_pipelined.sv is written as one `assign bundle.field = ...;`
  per field instead.

## Forwarding
- Three bypass paths were needed, not the two textbook diagrams usually
  show, because regfile.sv deliberately has no same-cycle write-then-read
  bypass (confirmed by tb_regfile.sv's timing tests). Many textbook
  pipelines give the register file that bypass for free (write in the
  first half of the cycle, read in the second), which quietly absorbs a
  hazard case their forwarding logic never has to handle. Ours doesn't,
  so that case needed an explicit third path:
  - EX/MEM -> EX (forwarding_unit.sv): a producer 1 instruction ahead —
    when the consumer reaches EX, the producer is in MEM and its ALU
    result is sitting in ex_mem_q.
  - MEM/WB -> EX (forwarding_unit.sv): a producer 2 instructions ahead,
    OR a load producer 1 instruction ahead that already cost its 1-cycle
    load-use stall (the stall shifts the alignment by exactly one stage,
    turning what would've been an EX/MEM case into a MEM/WB case) — when
    the consumer reaches EX, the producer is in WB.
  - MEM/WB -> ID (inline in riscv_core_pipelined.sv, feeding
    id_ex_d.rs1_data/rs2_data before they're latched): a producer exactly
    2 instructions ahead lands its WB-stage write in the SAME cycle the
    consumer does its ID-stage regfile read — one cycle before either
    EX-stage path would see it. Only checks mem_wb_q, not ex_mem_q too;
    proven safe below.
  - EX/MEM takes priority over MEM/WB when both match (the more recent
    write wins), same for the ID-stage bypass never needing to check
    ex_mem_q: any producer that's closer than mem_wb_q at ID-time is
    *not yet done computing* at that point anyway, and gets a completely
    independent, always-fresh re-check one cycle later when the consumer
    itself reaches EX (using ex_mem_q/mem_wb_q's state AT THAT cycle,
    not whatever the ID-stage bypass guessed). Traced this through a
    P1-then-P2-same-register adversarial case by hand before trusting it:
    the EX-stage check always has the last word right before the value
    is actually used, so an imperfect ID-stage guess never survives to
    affect the ALU.
  - EX/MEM -> EX only ever needs to supply `alu_result` (never
    `mem_read_data` or `pc_plus4`), and this isn't a convenience
    assumption — it's physically guaranteed: a load producer can never
    reach that alignment because hazard_unit's stall always catches it
    one cycle earlier (while the load is still in EX, before it could
    ever be the EX/MEM entry a consumer forwards from), and a jump
    producer can't either, because resolving jumps in EX flushes the 2
    instructions behind it, which pushes any real dependent instruction
    at least 2 stages further out — straight past the EX/MEM alignment
    into the MEM/WB-or-ID-bypass territory. Store data (`rs2_data` on its
    way into `ex_mem_d`) also needs forwarding, easy to miss since it's
    not an ALU operand — a store's own data operand can be a
    just-computed value like anything else.
- hazard_unit narrowed from checking EX/MEM/WB producers to checking only
  whether the EX-stage instruction is a load
  (`id_ex_q.result_src == RESULT_MEM`, a perfect proxy — control_unit
  only ever sets RESULT_MEM for LOAD) with a matching rd. Forwarding
  handles every other RAW hazard now; only a load's data genuinely isn't
  ready in time for the ALU operand mux one cycle later, since dmem
  hasn't been read yet at that point.
- Icarus gotcha, cost real debugging time: an enum comparison written
  directly as a module port-connection expression
  (`.load_ex (id_ex_q.result_src == RESULT_MEM)`) silently evaluated to
  X at runtime, even while every operand feeding it was a defined,
  non-X value in the waveform/$strobe trace at the same instant — no
  compile error or warning, just wrong simulation results that looked
  exactly like a real hazard-logic bug (traced for a while assuming the
  RTL logic itself was broken before suspecting the port-connection
  syntax). Pulling the same expression out into its own
  `logic id_ex_is_load; assign id_ex_is_load = (...);` and connecting
  that signal instead fixed it immediately. Lesson: don't put non-trivial
  expressions (especially enum comparisons) directly in a port
  connection list on this Icarus build — always stage them through an
  explicit intermediate signal.
- Testbench technique for actually proving forwarding reduces stalls
  (not just "still correct, possibly still slow"): the RAW-chain and
  load-use tests in tb_riscv_core_pipelined.sv run with a deliberately
  tight cycle budget — one only reachable if the hazards are resolved by
  forwarding rather than a 3-cycle stall-only-style wait. If forwarding
  ever silently regressed to stalling, these two tests would time out
  before the dependent instruction's writeback and fail on a stale
  register value, instead of just quietly passing slower.

## Branch/control hazard handling (tried, then reverted)
- Tried moving BRANCH and JAL resolution to ID instead of EX, to cut the
  flush penalty from 2 bubbles to 1 on every taken branch/jump: only the
  IF-stage instruction (fetched under the wrong sequential assumption)
  needed squashing, since the redirect was computed in the same cycle PC
  would otherwise have advanced sequentially. JALR was left resolving in
  EX (rs1+imm needs its own ID-stage bypass to resolve early without
  stalling; scoped out to keep that phase to one bounded change).
- The trade-off going in was known and deliberate: resolving in ID means
  EX-stage forwarding runs one stage too late to help, so a branch
  depending on a producer still in EX or MEM has to stall (up to 2
  cycles) instead of being forwarded — regardless of whether the branch
  is even taken, unlike the flush penalty which only applies when it is.
  Both sides of that trade were verified correct at the time (a 0-gap
  test exercising the stall, a 2-instruction-gap test resolving through
  the bypass with no stall, both tightened to a budget only reachable
  with a 1-bubble flush).
- Reverted after tb_full_program.sv measured the trade as a net loss: see
  "Measured throughput" below. For a tight counting loop — `ADD
  sum,sum,i` / `ADDI i,i,1` / `BLT i,limit,LOOP`, an extremely common
  real pattern — the branch's dependency on the just-incremented counter
  is 0-gap, exactly the case ID-resolution can't forward. The OLD
  EX-stage design already resolved that same 0-gap case for free via the
  EXISTING EX/MEM -> EX forwarding path, paying only the (larger) flush
  on taken iterations — cheaper overall than ID-resolution's stall.
  Moving resolution earlier made the common case worse, not better.
- Reverted cleanly: `id_ex_t.branch` restored, `id_ex_t.jump` back to
  meaning any jump (JAL or JALR) again, hazard_unit back to load-use-only
  (the branch-use stall check removed), riscv_core_pipelined.sv back to
  a single EX-stage `pc_redirect_taken`/`pc_redirect_target` pair, and
  the tb_riscv_core_pipelined.sv branch/JAL tests restored to their
  original generous (non-tight) budgets — this history is kept here
  rather than deleted so a future session doesn't rediscover the same
  dead end by trying ID-stage resolution again from scratch.

## Measured throughput (tb_full_program.sv)
- Built a 63-instruction integration program (10-iteration sum loop,
  every load/store width incl. signed/unsigned variants, a JAL/JALR
  subroutine call, every branch condition, R-type coverage) and ran it on
  `riscv_core_singlecycle` and `riscv_core_pipelined` side by side from
  identical encoded instructions. All 29 final-register checks match
  between both cores on every measurement below — strong evidence the
  pipeline is behaviorally equivalent to the single-cycle reference on
  real(-ish) code, not just the small isolated hazard scenarios the
  per-core testbenches already covered individually. Only the cycle
  counts (throughput), never correctness, changed across the revert.
- With ID-stage branch/JAL resolution: single-cycle 85 cycles, pipelined
  140 — 0.60x, slower than single-cycle. This measurement is what
  triggered the revert above.
- After reverting to EX-stage resolution: single-cycle 85 cycles,
  pipelined 121 — 0.70x. Better (fewer wasted stall cycles on the loop,
  as predicted), but still slower than single-cycle, nowhere near the
  targeted 3-5x.
- Why it's still slow even with the better design: this test program is
  a bad workload for a fair throughput measurement, despite being a good
  one for correctness. It was built to hit every hazard/branch/
  instruction-type path at least once for verification purposes, which
  makes it far more branch-DENSE than typical code — roughly 15 taken
  control-flow events (9 loop iterations + 5 other branches + 1 JAL)
  across ~85-90 dynamic instructions, each costing a fixed 2-bubble
  flush with EX-stage resolution. Real code has a much lower ratio of
  taken branches to straight-line arithmetic/memory work. A fair 3-5x
  check needs a separately-designed, less branch-dense benchmark — the
  upcoming Fibonacci smoke test is a natural candidate, being closer to
  a real, typical small program than a correctness stress test.
- Status: not yet resolved by this measurement, but see "CPI sanity
  check" below — it turns out no RTL-simulation cycle-count comparison
  between these two cores could ever settle it, regardless of what
  program is used.

## CPI sanity check (tb_cpi_sanity.sv) — why cycle counts can't prove 3-5x
- Before building a second, less branch-dense throughput benchmark to
  chase a fairer number, realized the whole approach was measuring the
  wrong thing. "Pipelining gives a 3-5x speedup" is a claim about clock
  FREQUENCY, not cycles-per-instruction: a single-cycle CPU's clock
  period has to be long enough for the slowest instruction's entire
  fetch-through-writeback combinational path to settle in one cycle; a
  pipelined CPU splits that same path into 5 shorter stages, each able to
  run at a much higher frequency in real hardware. The speedup comes from
  cycles-per-SECOND going up, not cycles-per-instruction going down — in
  the best case (zero hazards), a pipeline's CPI only approaches 1.0 from
  above, the same 1.0 single-cycle always hits exactly, by construction.
  Single-cycle is already CPI-optimal; it's just clocked slowly.
- `dut_sc` and `dut_pipe` share one `clk` in every testbench in this
  project — the same simulated frequency. That setup is structurally
  incapable of showing a frequency-based speedup, no matter how the test
  program is tuned. Tuning branch density (as tb_full_program.sv's
  measurement effectively did across the branch-resolution revert) only
  ever moves CPI closer to or further from 1.0; it can't make simulated
  pipelined cycle count beat simulated single-cycle cycle count, because
  single-cycle's cycle count for N instructions is always exactly N.
- This means the 3-5x claim can only actually be checked post-synthesis,
  comparing each design's achievable Fmax from a timing report — i.e.
  the still-untouched "FPGA synthesis pass" roadmap item, not anything
  buildable in Icarus.
- What's still legitimately useful to verify in simulation: that
  forwarding/hazard logic doesn't secretly blow up CPI with hidden
  stalls for ordinary code. tb_cpi_sanity.sv checks this with a 41
  dynamic-instruction 0-gap ADDI dependency chain (x1 += 1, each
  instruction depending on the one immediately before it — the exact
  case EX/MEM -> EX forwarding exists to make free) and no branches at
  all. Measured: single-cycle CPI 1.02, pipelined CPI 1.12 — the
  pipeline sits close to the 1.0 floor, meaning forwarding is correctly
  eliminating stalls for the case it exists for, with only fixed
  pipeline-fill overhead (~4-5 cycles) showing up. Explicitly documented
  in the testbench's own output as a sanity check, not a speedup
  measurement, so it can't be misread as answering the 3-5x question.

## Compliance-style testing (tb_compliance.sv)
- Checked the environment before attempting the official riscv-tests /
  riscv-arch-test suites: no RISC-V cross-compiler toolchain is
  installed (`riscv32-unknown-elf-gcc`, `riscv-none-elf-gcc`, `spike` —
  none present; no winget package either), and neither suite's standard
  boot harness would run on this core even with one, since both do
  machine-mode CSR setup (mtvec/mstatus/etc.) before the actual test
  body, and this core has zero CSR support — `FENCE`/`ECALL`/`EBREAK`
  were explicitly deferred from the start (see control_unit's scope
  note), and no CSR instructions exist at all. Running the literal
  upstream suites would mean: installing a large third-party toolchain,
  adding real CSR/trap RTL, building an ELF/hex program-loading path
  (every testbench so far pokes instructions directly via a hierarchical
  reference — there's no loader), and a signature/tohost pass-fail
  mechanism. Flagged to the user as a genuine multi-part undertaking
  rather than started unprompted; the user chose the scoped-down
  alternative below instead of the full toolchain path.
- What was built instead: tb_compliance.sv hand-ports the classic RV32I
  edge cases riscv-tests' rv32ui suite is built around, encoded with the
  same enc_* helpers used everywhere else in this project — no new
  toolchain, no CSR support needed. 21 cases across 9 groups: signed
  ADD/SUB overflow wraparound (MAX_INT+1 wraps to MIN_INT, not a trap —
  RV32I arithmetic is modular), AND/OR/XOR identity/absorbing cases with
  -1, shift-amount masking to 5 bits (shift by 32 == shift by 0 per
  spec, not shift-to-zero — a classic bug if an implementation shifts by
  the full 32-bit register value instead of masking), SRA
  sign-extension at MIN_INT/-1 extremes, SLT vs SLTU and SLTI vs SLTIU
  giving OPPOSITE results on the identical MIN_INT bit pattern (proving
  signed/unsigned comparison logic isn't accidentally shared), BLT vs
  BLTU disagreeing on the same MIN_INT/MAX_INT operands (same idea, for
  branches), and LB/LBU sign- vs zero-extension at the exact 0x7F/0x80
  byte boundary. All 21 pass on the first run.
- Distinction worth keeping clear going forward: this is NOT literally
  "the official riscv-tests suite passing" — it's compliance-STYLE
  coverage targeting the same known bug patterns, hand-verified against
  RV32I semantics rather than against a golden reference model. Genuinely
  useful added confidence, but if true upstream compliance certification
  is ever needed, the toolchain + CSR + harness work above is still the
  real path there.

## Fibonacci smoke test (tb_fibonacci.sv)
- Iterative, not recursive — RV32I has no call-stack convention set up
  yet (no stack pointer initialization, no calling convention decided),
  and iteration is simpler and sufficient for a smoke test. Also no
  multiply used or needed: RV32I base doesn't have one (M extension is
  the phase-2 stretch goal), and Fibonacci is pure addition anyway.
- Distinct in purpose from the other two integration testbenches:
  tb_full_program.sv is a synthetic hazard/instruction-coverage stress
  test, tb_compliance.sv is architectural edge cases — this one is meant
  to read like an actual small program a person would write (seed
  fib(0)/fib(1), loop computing+storing each subsequent term), the
  "does the whole core run recognizable real code correctly" check the
  roadmap calls for.
- Checks every stored term (fib(0) through fib(14)) against
  independently-computed expected values (a `for` loop in the testbench
  itself, not hand-copied constants) plus final register state, so a
  bug landing on any single iteration would be caught precisely rather
  than only surfacing as a wrong final answer.
- Bug caught immediately on the first run, but a testbench bug, not an
  RTL one: the initial cycle budget (120) was one loop iteration short —
  fib(0) through fib(13) all checked out correctly, only fib(14) and the
  final register checks failed, with the register values landing exactly
  one iteration behind (x1/x2 holding fib(12)/fib(13) instead of
  fib(13)/fib(14), loop index at 14 instead of 15). That specific
  failure shape — everything correct up to a clean cutoff, final state
  exactly one step behind — is the signature of a budget that's simply
  too tight, not a logic error; raising it to 200 cycles fixed it with
  no RTL changes.
- A separate live-narration variant (tb_fibonacci_demo.sv, run via
  run_fibonacci_demo.ps1) exists purely for showcasing — prints each
  term as it's computed instead of pass/fail lines, replayed at a
  human-watchable pace on a loop by the PowerShell wrapper (the RTL
  simulation itself is instantaneous either way; the pacing is applied
  to the captured output afterward, not to the simulation). Extended to
  47 terms (fib(0..46)) rather than the checked test's 15 — fib(46) =
  1,836,311,903 is the largest term that still fits as a positive
  32-bit signed value; fib(47) would overflow and print as a negative
  number, which would look like a bug to a demo audience rather than
  the deliberate stopping point it is.

## Assertions
- Icarus gotcha, discovered by testing deliberately before writing
  anything real: concurrent assertions (`assert property (@(posedge
  clk) ...)`) parse without error under `-gsupported-assertions` but
  never actually evaluate at runtime — confirmed by writing an
  assertion with an obviously-false condition and watching it stay
  silent through the whole simulation. No error, no warning at the
  point of failure — just silently wrong, which is worse than a hard
  error would have been. `bind` (the standard way to attach a separate
  checker module to a DUT without touching its source) is a plain
  syntax error, not supported at all. Both found via small throwaway
  test files before committing to an approach, given how many other
  Icarus-specific gaps this project has already hit.
- What actually works and was used instead: immediate assertions
  (`assert (expr) else $error(...);`, procedural, checked at the point
  of execution — a real part of the SVA language, just the
  same-cycle/non-temporal half of it, not concurrent properties).
  Confirmed both that they parse AND that they actually fire on a
  violation before trusting them. `$error` gives a well-formatted,
  file/line/time-stamped message, nicer than `$display` for this.
- Where they live: embedded directly in regfile.sv and
  riscv_core_pipelined.sv, since `bind` isn't available to keep them in
  a separate checker file. Checks added: x0 always reads 0 (both ports)
  and x0's storage never actually changes (regfile.sv); PC is always
  word-aligned; every pipeline bubble (valid=0) has reg_write/mem_write
  clear; a taken branch/jump redirect always wins PC-next priority over
  a same-cycle stall request; forwarding never selects a producer
  targeting x0 (both forward_a and forward_b, both sources) —
  formalizing the "never forward when rd == x0" rule from the hazard
  strategy at the top of this file, at the point where it's actually
  used, not just where it's implemented; and one temporal check
  (below).
- Temporal properties without concurrent assertions: Icarus's dead
  `assert property` meant no `|->`/`|=>` implication operators either.
  Hand-rolled the one genuinely temporal check needed (a load-use stall
  this cycle must produce a bubble in id_ex_q the following cycle) by
  registering a one-cycle-delayed shadow of `hazard_stall` and checking
  `id_ex_q.valid` against it the cycle after. This pattern — capture a
  signal via a plain register, check the CONSEQUENCE against it one
  cycle later inside a normal `always_ff` — turns out to be exactly how
  regfile.sv's x0-storage-stability check already worked (built earlier
  in this same session), so it wasn't a new technique so much as
  recognizing the same one applied to a second problem.
- Two real bugs surfaced in the assertions themselves before they were
  trustworthy — both caught by running the full regression immediately
  after adding them, rather than assuming clean logic meant clean
  results:
  1. The first version of the x0-always-reads-0 check used `always @(*)`
     (a combinational, level-sensitive block) reading both `rs1_addr`
     and `rs1_data`, where `rs1_data` is itself combinationally DERIVED
     from `rs1_addr` by a separate `assign`. When `rs1_addr` changes,
     Icarus doesn't guarantee this assertion block re-evaluates AFTER
     that derived `assign` has settled — it can (and did, constantly:
     hundreds of firings across the regression) catch a stale
     mid-delta-cycle `rs1_data` against the already-updated `rs1_addr`.
     This is exactly the class of same-timestep glitch that concurrent
     assertions (sampled only at clock edges) exist to avoid, and
     immediate assertions don't get that protection for free. Fixed by
     moving the check into `always_ff @(posedge clk)`: checking only at
     the clock edge means every combinational input has already fully
     settled by construction, the same reasoning synchronous design
     itself relies on.
  2. Even after that fix, `riscv_core_pipelined`-based testbenches still
     showed firings, all X-valued ("returned non-zero: 0xxxxxxxxx"),
     traced to `rs1_addr`/`rs2_addr` genuinely being X for a cycle or
     two around EVERY reset, not just the first — and testbenches like
     tb_riscv_core_pipelined.sv reset several times in one simulation
     (once per Test), so a one-shot "skip the first edge" `warm` flag
     only covered the very first reset, not the later ones. Fixed by
     gating each check on `!$isunknown(rs1_addr)` instead of a global
     one-time flag — skip whenever the address itself is unknown, since
     the assertion's own precondition ("this is specifically an x0
     read") can't be established when the address isn't known to BE
     x0 or not. This is the more principled fix, not just a
     broader-coverage patch: it's correct regardless of how many times
     or when the surrounding core resets.
- Proved the assertions actually have teeth, not just that they compile
  and stay quiet, with two deliberate negative tests (temporarily
  breaking real RTL, confirming the assertion fires, then restoring
  it): removing regfile's `rd_addr != 0` write guard, and removing
  forwarding_unit's `rd_mem != 0` guard on the EX/MEM forwarding path.
  Both caught immediately. Notably, in BOTH cases every existing
  black-box directed test kept reporting 100% pass throughout — x0 is
  independently re-masked to 0 by the regfile's own read-side mux
  regardless of what's stored, and forwarding a producer that targets
  x0 doesn't corrupt anything else observable in these specific test
  scenarios — so purely external, architectural-state-only testing
  would never have caught either regression. Only the new white-box
  assertions, checking internal signals directly, did. That gap is the
  concrete case for why assertions add real verification value beyond
  directed testing, not just a demonstration of syntax.

## Functional coverage (coverage_collector.sv, tb_coverage.sv)
- Icarus gotcha, discovered the same way as the SVA one before writing
  anything real: a two-bin `covergroup`/`coverpoint` scratch file fails
  to even parse ("invalid module item" on the `covergroup` keyword
  itself) — no partial support at all, unlike `assert property` which at
  least parses. Associative arrays don't work either: `int arr[string]`
  and `int arr[int]` elaborate as bogus fixed-size arrays with indices
  silently truncated to garbage numbers (`hit_count[1280262468]` from a
  `string` key that should never have become a number at all), and
  `.num()` isn't a recognized method on them. Fixed-size arrays indexed
  by a plain `int`/enum, by contrast, work fine — confirmed with a
  throwaway probe before committing to a design.
- What was built instead: every coverpoint is a set of named `int
  unsigned` hit counters (one per bin) incremented by an explicit
  case/if classifier standing in for `bins {...}`, and a `print_report()`
  task standing in for `get_coverage()`. This mirrors the same
  methodology real coverage-driven verification uses, just without the
  language construct — arguably a more honest demonstration of
  understanding *why* functional coverage works than leaning on
  `covergroup` syntax would have been.
- Where it lives: `coverage_collector.sv` is a standalone module, kept
  out of `rtl/` since it's test-only infrastructure, never instantiated
  from synthesizable code. It's wired to `riscv_core_pipelined`'s
  internal signals (`id_ex_q`, `forward_a`/`forward_b`, `hazard_stall`,
  `ex_branch_taken`, the ID-stage opcode) via hierarchical reference from
  `tb_coverage.sv` rather than new DUT ports — confirmed with a scratch
  probe that Icarus supports hierarchical references as *live*,
  continuously-updating port connections across module boundaries (not
  just a one-time snapshot read), which is what makes this safe to rely
  on for cycle-by-cycle sampling.
- `final` blocks can't call tasks in this Icarus build ("final
  procedures cannot enable/call tasks") — found by trying the obvious
  design first (auto-print the report from a `final` block in the
  collector, so any testbench that instantiates it gets a report for
  free regardless of which one calls `$finish`). Fell back to
  `tb_coverage.sv` calling `cov_inst.print_report()` explicitly right
  before its own `$finish` instead — less automatic, but the only option
  that compiles.
- 39 bins across six coverpoints, chosen to track "did we exercise the
  interesting cases" rather than exhaustively cross every signal: all 9
  RV32I opcodes, all 10 ALU operations, both forwarding paths (EX/MEM
  and MEM/WB) on both ALU operands (FWD_NONE isn't tracked — it's the
  default/majority case for any instruction with no nearby producer, not
  a meaningful verification target), the load-use hazard stall, all 6
  branch types crossed with taken/not-taken (12 bins), and x0 used as
  rs1/rs2/rd — the last one gated on the instruction's control signals
  actually giving it a semantic rs1/rs2 (`alu_src_a == SRCA_RS1` for
  rs1; `alu_src_b == SRCB_RS2 || mem_write || branch` for rs2), since
  decoder.sv blind-slices rs1/rs2 bits out of every instruction
  regardless of format and U/J-type instructions' "rs1 field" is
  meaningless immediate bits, not a real operand.
- `tb_coverage.sv` runs a single purpose-built ~90-instruction stream
  (loop, memory round-trips, JAL/JALR subroutine call, a full branch
  bank, an R-type ALU bank, and — unlike any prior testbench — engineered
  back-to-back and one-instruction-gap dependencies specifically to force
  both EX/MEM and MEM/WB forwarding on both operands, plus an explicit
  load-use hazard) built with a running instruction-count variable and
  saved label indices rather than hand-counted branch/jump offsets, to
  avoid the off-by-one arithmetic errors hand-counted indices invite once
  a program gets much past a dozen instructions. It has no pass/fail
  checking of its own — correctness of this core is already established
  by tb_riscv_core_pipelined.sv and tb_full_program.sv — its only job is
  hitting every bin, and it reached 39/39 (100%) on its first real run.
- The coverage-driven design process still surfaced two real, previously
  invisible gaps in the existing test suite before this testbench closed
  them: **SRL and SRA were never exercised anywhere** — tb_full_program.sv's
  R-type ALU bank only covers AND/OR/XOR/SLL, and its branches only ever
  drive ALU_ADD/SUB/SLT/SLTU, so two of ten ALU operations had zero
  coverage across the entire prior regression despite the ALU's own
  directed testbench (tb_alu.sv) exercising them fine in isolation. And
  **no testbench ever drove a load-use hazard stall through the full
  pipelined core** — tb_hazard_unit.sv tests the standalone hazard_unit
  module directly, and tb_forwarding_unit.sv tests forwarding_unit in
  isolation, but nothing had ever put a load immediately followed by a
  dependent instruction through the actual assembled datapath before this
  testbench added one. Both are exactly the kind of gap functional
  coverage exists to surface: individually-correct components whose
  interaction was simply never stimulated end-to-end.
- Confirmed zero regressions and zero assertion firings: this is a brand
  new ~90-instruction stream distinct from every prior testbench's
  program, run against a core carrying all of the Assertions-section
  checks above, and it passed clean on the first try alongside the full
  existing 12-testbench regression.

## Constrained-random instruction testing (tb_random.sv)
- Methodology: riscv_core_singlecycle serves as the reference model
  (correctness already established by its own directed testbench and
  tb_compliance.sv) and riscv_core_pipelined is the DUT. Many
  independently randomized instruction streams are generated, each run
  on both cores from a clean, identical starting state, and their final
  architectural state (all 32 registers, plus a window of dmem) is
  compared. Where tb_full_program.sv proves equivalence on one
  hand-written 63-instruction program, this proves it across many
  randomized ones — a hand-written program only ever stresses the
  interactions its author thought of, while randomization finds the ones
  nobody thought to write down.
- Constraints (the "constrained" half of constrained-random — fully
  unbounded random RV32I would mostly generate memory accesses and jump
  targets that wander into undefined territory or never terminate,
  telling us nothing useful): x30 is a fixed, never-randomized
  memory-base pointer (initialized to 0 at the start of every random
  program, never a random destination), so every LOAD/STORE address is
  provably in-bounds without tracking any register's runtime value at
  generation time; x31 is a reserved completion sentinel (also never a
  random destination), written only by a fixed marker instruction
  appended after the random ones, giving an unambiguous "this core
  finished the whole program" signal — the same finished-detection
  pattern tb_full_program.sv uses, synthesized instead of hand-picked;
  JALR is excluded from the random opcode pool since its target
  (rs1+imm) depends on a register's runtime value and isn't boundable at
  generation time the way BRANCH/JAL's immediate-only targets are (it's
  already exercised by the directed subroutine-call pattern elsewhere);
  and funct3 is drawn only from the encodings each opcode actually
  defines, so every generated instruction decodes to a real intended
  RV32I instruction.
- Three testbench bugs surfaced and were fixed while building this,
  before the results could be trusted — none were DUT bugs, but each
  would have produced misleading pass/fail/timeout results if left in
  place:
  1. **Vacuous 0-cycle passes.** The very first version zeroed x31
     before loading a new random program but never re-zeroed it between
     runs otherwise, and regfile.sv has no reset by design (see "Hazard
     strategy" / the regfile assertions above). x31 still held the
     PREVIOUS test's sentinel value the instant the next test began, so
     the done-detection fired instantly — 49 of 50 seeds "passed" in 0
     cycles, having never actually run their generated program. Fixed
     by zeroing the entire regfile and dmem (both cores) at the start of
     every test, not just x31.
  2. **A same-edge race that clobbered the fix above.** With the zeroing
     moved to before the reset pulse, a NEW failure mode appeared:
     specific seeds showed genuine-looking register/memory mismatches
     (e.g. x21 diverging between the two cores) on registers the
     generated program never even wrote. A cycle-by-cycle replay of the
     exact failing program in isolation (dumped from the "reproduce with
     this program" output the FAIL path prints) showed NO mismatch at
     all — proving the bug depended on test history, not the program
     itself. The actual mechanism: on the reset edge, `ex_mem_reg.sv`/
     `mem_wb_reg.sv` clear to a bubble for the FOLLOWING cycle, but
     `dmem.sv`/`regfile.sv`'s own `always_ff` write ports fire on that
     SAME edge using whatever those pipeline registers held going INTO
     the edge — a leftover in-flight instruction from the previous
     (possibly timed-out) test could still commit its write on the reset
     edge itself, landing after a zero-poke sequenced before that edge
     and silently overwriting it. A synchronous reset can't retroactively
     cancel a downstream write already in flight on the edge it takes
     effect. Fixed by moving the zeroing to after the reset edge settles,
     so it's provably the last thing to touch these arrays.
  3. **The done-detection block itself raced the fix above.** Moving the
     zeroing to after the reset edge reintroduced a narrower version of
     bug 1: the done-detection `always @(posedge clk)` block had no
     `rst_n` gate, so on the reset edge itself — before the (now
     correctly-ordered but not-yet-executed) zeroing ran — it could see
     the previous test's leftover `regs[31] === MAGIC`, if that test had
     genuinely completed, and latch "done" one edge early. Fixed by
     gating the block on `rst_n`, so it simply doesn't look during the
     reset cycle.
- Two more rounds of tuning were needed after correctness was
  established, both concerning the generator's completion rate rather
  than any bug: an early version let BRANCH/JAL targets land anywhere in
  the program including backward, and measured a ~70% timeout rate
  across 50 seeds from randomly-generated infinite loops — an
  under-constrained generator, not a DUT defect (backward branches
  forming real loops are already covered elsewhere, by directed,
  guaranteed-terminating constructs in tb_coverage.sv and
  tb_full_program.sv, and this testbench's actual goal — broad coverage
  of instruction/operand/forwarding combinations — doesn't need loops at
  all). Constraining targets to be forward-only cut that to ~24%: any
  jump could still land exactly on the halt self-loop instruction,
  skipping the sentinel write and looping forever without ever recording
  completion. Capping targets at the sentinel index itself (never past
  it) closed the gap entirely.
- Final state: 300 independently randomized 25-instruction programs,
  300 passed, 0 failed, 0 inconclusive — both cores reach identical
  architectural state (all 32 registers + a 64-byte dmem window) on
  every one, run alongside the full existing 12-testbench regression
  with zero assertion firings.

## Toolchain
- Icarus Verilog for quick per-module tests.
- Verilator for full-core regression once instruction count grows.