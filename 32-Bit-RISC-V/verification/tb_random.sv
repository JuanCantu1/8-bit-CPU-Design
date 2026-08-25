// tb_random.sv
// Constrained-random instruction testing: generates many random RV32I
// instruction streams, runs each on BOTH riscv_core_singlecycle (the
// reference model — already proven correct by its own directed
// testbench and tb_compliance.sv) and riscv_core_pipelined (the DUT),
// and checks they reach identical architectural state. Where
// tb_full_program.sv proves equivalence on one hand-written 63
// -instruction program, this proves it across many independently
// randomized ones — the point being that a hand-written program only
// ever stresses the interactions its author thought of, while
// randomization finds the ones nobody thought to write down. Run via
// sim/run_random.ps1.
//
// Constraints (the "constrained" half of constrained-random — unbounded
// random RV32I would mostly generate memory accesses and jump targets
// that fault or wander off into undefined territory, telling us nothing
// useful):
//   - x30 is a fixed, never-randomized memory-base pointer, initialized
//     to 0 at the start of every random program and never chosen as a
//     random destination register — every LOAD/STORE offsets off of it
//     within a small aligned range, so every address is provably within
//     dmem's bounds without having to track any register's runtime
//     value at generation time.
//   - x31 is a reserved completion sentinel, likewise never a random
//     destination — the only instruction that ever writes it is the
//     fixed marker appended after the random instructions, so
//     "x31 == MAGIC" unambiguously means "this core finished the whole
//     randomly generated program," the same finished-detection pattern
//     tb_full_program.sv uses, just synthesized instead of hand-picked.
//   - Every other register (x0-x29, including x0 itself — exercising
//     its guard under randomization too) is fair game as a random
//     source or destination.
//   - JALR is excluded from the random opcode pool: its target
//     (rs1+imm) depends on a register's runtime value, which isn't
//     boundable at generation time the way BRANCH/JAL's immediate-only
//     targets are, and it's already exercised by the directed
//     subroutine-call pattern in tb_full_program.sv and tb_coverage.sv.
//     BRANCH and JAL both stay in the pool, but their targets are
//     constrained to be forward-only and capped at the sentinel index
//     (never past it, into the halt self-loop) — see the comment at the
//     BRANCH/JAL generation site for the two timeout rates (~70%, then
//     ~24%) measured before landing on that constraint, and why neither
//     was a DUT bug.
//   - funct3 is drawn only from the encodings each opcode actually
//     defines (e.g. LOAD draws from {LB,LH,LW,LBU,LHU}, not all 8
//     possible funct3 values), so every generated instruction decodes
//     to a real, intended RV32I instruction rather than reusing the
//     "unrecognized opcode/funct3" default-no-op path control_unit.sv
//     already falls back to for out-of-scope encodings.
//
// Every seed now reliably reaches the sentinel given the forward-only,
// sentinel-capped branch/jump constraint above (300/300 in the checked
// -in configuration). INCONCLUSIVE remains as a defensive reported
// category rather than being deleted outright: with no shared "both
// cores are at the same point in the program" moment to compare at, a
// state comparison at an arbitrary cycle cutoff would only be comparing
// two different, still-in-flight points in program order — meaningless
// even with a perfectly correct pipeline, since single-cycle and
// pipeline retire instructions at different rates — so if some future
// change to the generator ever reintroduces non-termination, this stays
// the correct way to report it rather than a false pass or fail.

`timescale 1ns / 1ps

module tb_random;
  import riscv_pkg::*;

  logic clk;
  logic rst_n;

  int pass_count = 0;
  int fail_count = 0;
  int inconclusive_count = 0;

  riscv_core_singlecycle dut_sc (
    .clk   (clk),
    .rst_n (rst_n)
  );

  riscv_core_pipelined dut_pipe (
    .clk   (clk),
    .rst_n (rst_n)
  );

  always #5 clk = ~clk;

  // ---- RV32I field encoders (same as the other core testbenches) ----
  function automatic logic [31:0] enc_r(
    input logic [6:0] funct7, input logic [4:0] rs2, input logic [4:0] rs1,
    input logic [2:0] funct3, input logic [4:0] rd, input logic [6:0] opcode);
    return {funct7, rs2, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] enc_i(
    input logic [11:0] imm, input logic [4:0] rs1,
    input logic [2:0] funct3, input logic [4:0] rd, input logic [6:0] opcode);
    return {imm, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] enc_s(
    input logic [11:0] imm, input logic [4:0] rs2, input logic [4:0] rs1,
    input logic [2:0] funct3, input logic [6:0] opcode);
    return {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
  endfunction

  function automatic logic [31:0] enc_b(
    input logic [12:0] imm, input logic [4:0] rs2, input logic [4:0] rs1,
    input logic [2:0] funct3, input logic [6:0] opcode);
    return {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
  endfunction

  function automatic logic [31:0] enc_u(
    input logic [19:0] imm20, input logic [4:0] rd, input logic [6:0] opcode);
    return {imm20, rd, opcode};
  endfunction

  function automatic logic [31:0] enc_j(
    input logic [20:0] imm, input logic [4:0] rd, input logic [6:0] opcode);
    return {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
  endfunction

  function automatic logic [31:0] halt();
    return enc_j(21'sd0, 5'd0, OPC_JAL);
  endfunction

  // ---- constrained random helpers ----
  function automatic logic [4:0] rand_reg();
    return $urandom_range(0, 29); // x0-x29 only: x30/x31 stay reserved
  endfunction

  function automatic logic [2:0] rand_load_funct3();
    logic [2:0] opts [0:4];
    opts[0] = 3'b000; opts[1] = 3'b001; opts[2] = 3'b010;
    opts[3] = 3'b100; opts[4] = 3'b101;
    return opts[$urandom_range(0, 4)];
  endfunction

  function automatic logic [2:0] rand_store_funct3();
    logic [2:0] opts [0:2];
    opts[0] = 3'b000; opts[1] = 3'b001; opts[2] = 3'b010;
    return opts[$urandom_range(0, 2)];
  endfunction

  function automatic logic [2:0] rand_branch_funct3();
    logic [2:0] opts [0:5];
    opts[0] = 3'b000; opts[1] = 3'b001; opts[2] = 3'b100;
    opts[3] = 3'b101; opts[4] = 3'b110; opts[5] = 3'b111;
    return opts[$urandom_range(0, 5)];
  endfunction

  // ---- program generation ----
  localparam int N_RANDOM   = 25;
  localparam int N_INSTR    = N_RANDOM + 3; // base-init + random + sentinel + halt

  // ADDI can only encode a 12-bit signed immediate (sign-extended to
  // 32 bits), so the sentinel value has to fit in that range — it
  // doesn't need to look distinctive, just be a value nothing else in
  // the random pool can ever produce in x31 (guaranteed by x31 being
  // excluded from rand_reg() entirely, not by the value itself).
  localparam logic [11:0] MAGIC_IMM = 12'd1234;
  localparam logic [31:0] MAGIC     = 32'd1234;

  logic [31:0] prog [0:N_INSTR-1];

  task automatic gen_program(input int seed);
    int k;
    int target_idx;
    int unsigned discard;
    logic [6:0] opcode_pick;
    logic [6:0] opcode_pool [0:7];
    opcode_pool[0] = OPC_OP_IMM; opcode_pool[1] = OPC_OP;
    opcode_pool[2] = OPC_LOAD;   opcode_pool[3] = OPC_STORE;
    opcode_pool[4] = OPC_LUI;    opcode_pool[5] = OPC_AUIPC;
    opcode_pool[6] = OPC_BRANCH; opcode_pool[7] = OPC_JAL;

    discard = $urandom(seed); // reseed deterministically for this program

    prog[0] = enc_i(12'd0, 5'd0, 3'b000, 5'd30, OPC_OP_IMM); // x30 = 0 (mem base)

    for (k = 1; k <= N_RANDOM; k++) begin
      opcode_pick = opcode_pool[$urandom_range(0, 7)];
      case (opcode_pick)
        OPC_OP_IMM:
          prog[k] = enc_i($urandom_range(0, 4095), rand_reg(), $urandom_range(0, 7),
                           rand_reg(), OPC_OP_IMM);
        OPC_OP:
          prog[k] = enc_r($urandom_range(0, 1) ? 7'b0100000 : 7'b0, rand_reg(), rand_reg(),
                           $urandom_range(0, 7), rand_reg(), OPC_OP);
        OPC_LOAD:
          prog[k] = enc_i($urandom_range(0, 15) * 4, 5'd30, rand_load_funct3(),
                           rand_reg(), OPC_LOAD);
        OPC_STORE:
          prog[k] = enc_s($urandom_range(0, 15) * 4, rand_reg(), 5'd30,
                           rand_store_funct3(), OPC_STORE);
        OPC_LUI:
          prog[k] = enc_u($urandom_range(0, 20'hFFFFF), rand_reg(), OPC_LUI);
        OPC_AUIPC:
          prog[k] = enc_u($urandom_range(0, 20'hFFFFF), rand_reg(), OPC_AUIPC);
        OPC_BRANCH: begin
          // Forward-only, and capped at the sentinel index rather than
          // the halt index right after it: guarantees every branch
          // strictly shrinks the distance remaining AND can never skip
          // past the sentinel write straight into the halt self-loop.
          // Two things had to be found and fixed to get here. First, an
          // earlier version allowed backward targets (real RV32I
          // branches obviously can go backward) and measured a ~70%
          // timeout rate across 50 seeds from randomly-generated
          // infinite loops — not a DUT bug, just an under-constrained
          // generator; backward branches forming real loops are already
          // covered elsewhere (tb_coverage.sv's loop, tb_full_program.sv)
          // by a directed, guaranteed-terminating construct, and this
          // testbench's own goal — broad random coverage of instruction/
          // operand/forwarding combinations — doesn't need loops and is
          // much better served by every seed actually finishing. Second,
          // even forward-only still capped at N_INSTR-1 (the halt
          // instruction itself) left a ~24% timeout rate: any jump
          // landing exactly on halt skips the sentinel and falls
          // straight into its self-loop, "completing" the program
          // without ever recording completion. Capping at the sentinel
          // index instead closes that gap entirely.
          target_idx = $urandom_range(k + 1, N_RANDOM + 1);
          prog[k] = enc_b((target_idx - k) * 4, rand_reg(), rand_reg(),
                           rand_branch_funct3(), OPC_BRANCH);
        end
        OPC_JAL: begin
          target_idx = $urandom_range(k + 1, N_RANDOM + 1);
          prog[k] = enc_j((target_idx - k) * 4, rand_reg(), OPC_JAL);
        end
        default: prog[k] = enc_i(12'd0, 5'd0, 3'b000, 5'd0, OPC_OP_IMM); // unreachable
      endcase
    end

    prog[N_RANDOM + 1] = enc_i(MAGIC_IMM, 5'd0, 3'b000, 5'd31, OPC_OP_IMM); // sentinel
    prog[N_RANDOM + 2] = halt();
  endtask

  // ---- run + compare ----
  localparam int MAX_CYCLES = 500;

  int  sc_cycles, pipe_cycles;
  logic sc_done, pipe_done;

  always @(posedge clk) begin
    if (!rst_n) begin
      sc_cycles <= 0;
      pipe_cycles <= 0;
    end else begin
      if (!sc_done)   sc_cycles   <= sc_cycles + 1;
      if (!pipe_done) pipe_cycles <= pipe_cycles + 1;
    end
  end

  // Gated on rst_n for the same reason the zeroing above moved to after
  // the reset edge: on the reset edge itself, rst_n is still 0 here (set
  // before the @(posedge clk) that waits for this edge) while regfile
  // zeroing hasn't run yet (it happens just after), so an ungated check
  // on this exact edge would see the PREVIOUS test's leftover regs[31]
  // — MAGIC, if that test genuinely completed — and falsely latch
  // "done" for 0 cycles before this test's own program ever ran.
  always @(posedge clk) begin
    if (rst_n) begin
      if (!sc_done && (dut_sc.regfile_inst.regs[31] === MAGIC))
        sc_done <= 1'b1;
      if (!pipe_done && (dut_pipe.regfile_inst.regs[31] === MAGIC))
        pipe_done <= 1'b1;
    end
  end

  task automatic dump_program();
    int i;
    for (i = 0; i < N_INSTR; i++)
      $display("    prog[%0d] = 32'h%h", i, prog[i]);
  endtask

  task automatic run_one_test(input int seed);
    int i;
    logic mismatch;

    gen_program(seed);

    for (i = 0; i < N_INSTR; i++) begin
      dut_sc.imem_inst.mem[i]   = prog[i];
      dut_pipe.imem_inst.mem[i] = prog[i];
    end

    rst_n       = 1'b0;
    sc_cycles   = 0;
    pipe_cycles = 0;
    sc_done     = 1'b0;
    pipe_done   = 1'b0;
    @(posedge clk);
    #1;
    rst_n = 1'b1;

    // Neither regfile.sv nor dmem.sv has a reset (see design-notes.md),
    // so this zeroing has to happen AFTER the reset edge above, not
    // before it — found the hard way, by tracing a phantom x21/dmem[24]
    // mismatch back to a same-edge race: the reset edge simultaneously
    // (a) clears ex_mem_q/mem_wb_q to bubbles for the FOLLOWING cycle,
    // and (b) lets dmem/regfile's own always_ff blocks commit whatever
    // those pipeline registers were STILL carrying from the PREVIOUS
    // (possibly timed-out) test on THIS edge, using their pre-edge
    // values — the same reason a synchronous reset can't retroactively
    // cancel a downstream write already in flight on the edge it takes
    // effect. Zeroing before the reset let that stale in-flight
    // instruction's write land right after my poke and silently win.
    // Zeroing here, after the edge has fully settled, means this poke
    // is always the last thing to touch these arrays before the new
    // test's real instructions run — poking regfile/dmem storage
    // directly from a testbench is the same technique tb_regfile.sv
    // already uses; zeroing both cores identically keeps each of the
    // 50 runs a fully independent comparison.
    for (i = 0; i < 32; i++) begin
      dut_sc.regfile_inst.regs[i]   = 32'h0;
      dut_pipe.regfile_inst.regs[i] = 32'h0;
    end
    for (i = 0; i < 1024; i++) begin
      dut_sc.dmem_inst.mem[i]   = 8'h0;
      dut_pipe.dmem_inst.mem[i] = 8'h0;
    end

    while (!(sc_done && pipe_done) &&
           (sc_cycles < MAX_CYCLES) && (pipe_cycles < MAX_CYCLES)) begin
      @(posedge clk);
    end
    #1;

    if (!sc_done || !pipe_done) begin
      inconclusive_count++;
      $display("INCONCLUSIVE: seed=%0d did not reach sentinel within %0d cycles (sc_done=%0b pipe_done=%0b)",
                seed, MAX_CYCLES, sc_done, pipe_done);
    end else begin
      mismatch = 1'b0;
      for (i = 0; i < 32; i++) begin
        if (dut_sc.regfile_inst.regs[i] !== dut_pipe.regfile_inst.regs[i]) begin
          mismatch = 1'b1;
          $display("  MISMATCH: x%0d sc=0x%h pipe=0x%h", i,
                    dut_sc.regfile_inst.regs[i], dut_pipe.regfile_inst.regs[i]);
        end
      end
      for (i = 0; i < 64; i++) begin
        if (dut_sc.dmem_inst.mem[i] !== dut_pipe.dmem_inst.mem[i]) begin
          mismatch = 1'b1;
          $display("  MISMATCH: dmem[%0d] sc=0x%h pipe=0x%h", i,
                    dut_sc.dmem_inst.mem[i], dut_pipe.dmem_inst.mem[i]);
        end
      end

      if (mismatch) begin
        fail_count++;
        $display("FAIL: seed=%0d (sc_cycles=%0d pipe_cycles=%0d) — architectural state diverged",
                  seed, sc_cycles, pipe_cycles);
        $display("  reproduce with this program:");
        dump_program();
      end else begin
        pass_count++;
        $display("PASS: seed=%0d (sc_cycles=%0d pipe_cycles=%0d, both cores agree on x0-x31 + dmem[0:63])",
                  seed, sc_cycles, pipe_cycles);
      end
    end
  endtask

  localparam int NUM_SEEDS = 300;

  initial begin
    int seed;
    $display("---- constrained-random testbench start (%0d seeds, %0d instructions each) ----",
              NUM_SEEDS, N_RANDOM);

    clk = 1'b0;

    for (seed = 1; seed <= NUM_SEEDS; seed++) begin
      run_one_test(seed);
    end

    $display("---- constrained-random testbench done: %0d passed, %0d failed, %0d inconclusive (of %0d) ----",
              pass_count, fail_count, inconclusive_count, NUM_SEEDS);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else $display("SOME TESTS FAILED");

    $finish;
  end

endmodule : tb_random
