// tb_full_program.sv
// Cross-cutting integration testbench: a single 63-instruction RV32I
// program (a 10-iteration loop, memory ops of every width with
// signed/unsigned load variants, a JAL/JALR subroutine call, every
// branch condition taken AND two left not-taken, R-type arithmetic) run
// on BOTH riscv_core_singlecycle and riscv_core_pipelined from the SAME
// encoded program. Checks that both cores reach an IDENTICAL final
// architectural state — proving the pipeline is behaviorally equivalent
// to the single-cycle reference on a real(-ish) program, not just the
// small isolated hazard scenarios the per-core testbenches already
// cover — and measures each core's cycle count to completion to compute
// the pipeline's actual measured throughput improvement, since no
// earlier testbench ever ran the same workload on both cores and
// compared. Run via sim/run_full_program.ps1
//
// Program outline (see prog[] below for exact encoding):
//   0-5   : loop summing 1..10 into x1 (backward BLT, exercised ~10x)
//   6-16  : word/byte/half store+load round trips, incl. LB/LBU and
//           LH/LHU on the same stored value to distinguish sign- vs
//           zero-extension
//   17    : AUIPC
//   18-20 : JAL call to a subroutine (idx 61) that doubles x6 via SLLI,
//           JALR return — subroutine is placed after the halt loop
//           (dead code from sequential flow, reached only by the JAL)
//   21-53 : BEQ/BNE/BGE/BLTU/BGEU each taken once (BLT already covered
//           by the loop), plus BEQ and BLTU each left not-taken once
//   54-59 : AND/OR/XOR/SLLI R-type coverage
//   60    : halt() (JAL x0,0 self-loop)
//   61-62 : the subroutine

`timescale 1ns / 1ps

module tb_full_program;
  import riscv_pkg::*;

  logic clk;
  logic rst_n;

  int pass_count = 0;
  int fail_count = 0;

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
    return enc_j(21'sd0, 5'd0, OPC_JAL); // JAL x0,0 -- infinite self-loop
  endfunction

  // ---- Program (indices double as label positions; branch/jump
  // immediates are computed as (target_idx - current_idx) * 4) ----
  localparam int N_INSTR = 63;
  logic [31:0] prog [0:N_INSTR-1];

  initial begin
    prog[0]  = enc_i(12'd0,   5'd0,  3'b000, 5'd1,  OPC_OP_IMM); // sum = 0
    prog[1]  = enc_i(12'd1,   5'd0,  3'b000, 5'd2,  OPC_OP_IMM); // i = 1
    prog[2]  = enc_i(12'd11,  5'd0,  3'b000, 5'd3,  OPC_OP_IMM); // limit = 11
    prog[3]  = enc_r(7'b0,    5'd2,  5'd1,   3'b000, 5'd1, OPC_OP);      // LOOP: sum += i
    prog[4]  = enc_i(12'd1,   5'd2,  3'b000, 5'd2,  OPC_OP_IMM); // i += 1
    prog[5]  = enc_b(-13'sd8, 5'd3,  5'd2,   3'b100, OPC_BRANCH); // BLT i,limit,LOOP
    prog[6]  = enc_i(12'd0,   5'd0,  3'b000, 5'd4,  OPC_OP_IMM); // dmem base = 0
    prog[7]  = enc_s(12'd0,   5'd1,  5'd4,   3'b010, OPC_STORE);  // SW sum,0(x4)
    prog[8]  = enc_i(12'd0,   5'd4,  3'b010, 5'd5,  OPC_LOAD);   // LW x5,0(x4)
    prog[9]  = enc_i(12'd170, 5'd0,  3'b000, 5'd9,  OPC_OP_IMM); // x9 = 0xAA
    prog[10] = enc_s(12'd4,   5'd9,  5'd4,   3'b000, OPC_STORE); // SB x9,4(x4)
    prog[11] = enc_i(12'd4,   5'd4,  3'b000, 5'd10, OPC_LOAD);   // LB  x10,4(x4) -> sign-ext
    prog[12] = enc_i(12'd4,   5'd4,  3'b100, 5'd11, OPC_LOAD);   // LBU x11,4(x4) -> zero-ext
    prog[13] = enc_u(20'd8,   5'd12, OPC_LUI);                    // x12 = 0x8000
    prog[14] = enc_s(12'd8,   5'd12, 5'd4,   3'b001, OPC_STORE); // SH x12,8(x4)
    prog[15] = enc_i(12'd8,   5'd4,  3'b001, 5'd13, OPC_LOAD);   // LH  x13,8(x4) -> sign-ext
    prog[16] = enc_i(12'd8,   5'd4,  3'b101, 5'd14, OPC_LOAD);   // LHU x14,8(x4) -> zero-ext
    prog[17] = enc_u(20'd1,   5'd15, OPC_AUIPC);                  // x15 = PC + 0x1000
    prog[18] = enc_i(12'd21,  5'd0,  3'b000, 5'd6,  OPC_OP_IMM); // arg = 21
    prog[19] = enc_j(21'sd168, 5'd31, OPC_JAL);                   // JAL x31, DOUBLE_FN(61)
    prog[20] = enc_i(12'd777, 5'd0,  3'b000, 5'd17, OPC_OP_IMM); // RETURN_PT marker

    prog[21] = enc_i(12'd5,   5'd0,  3'b000, 5'd20, OPC_OP_IMM);
    prog[22] = enc_i(12'd5,   5'd0,  3'b000, 5'd21, OPC_OP_IMM);
    prog[23] = enc_b(13'sd8,  5'd21, 5'd20,  3'b000, OPC_BRANCH); // BEQ taken
    prog[24] = enc_i(12'd999, 5'd0,  3'b000, 5'd22, OPC_OP_IMM); // squashed
    prog[25] = enc_i(12'd111, 5'd0,  3'b000, 5'd22, OPC_OP_IMM);

    prog[26] = enc_i(12'd5,   5'd0,  3'b000, 5'd20, OPC_OP_IMM);
    prog[27] = enc_i(12'd9,   5'd0,  3'b000, 5'd21, OPC_OP_IMM);
    prog[28] = enc_b(13'sd8,  5'd21, 5'd20,  3'b001, OPC_BRANCH); // BNE taken
    prog[29] = enc_i(12'd999, 5'd0,  3'b000, 5'd23, OPC_OP_IMM); // squashed
    prog[30] = enc_i(12'd222, 5'd0,  3'b000, 5'd23, OPC_OP_IMM);

    prog[31] = enc_i(-12'sd5, 5'd0,  3'b000, 5'd20, OPC_OP_IMM);
    prog[32] = enc_i(-12'sd5, 5'd0,  3'b000, 5'd21, OPC_OP_IMM);
    prog[33] = enc_b(13'sd8,  5'd21, 5'd20,  3'b101, OPC_BRANCH); // BGE taken (-5>=-5)
    prog[34] = enc_i(12'd999, 5'd0,  3'b000, 5'd24, OPC_OP_IMM); // squashed
    prog[35] = enc_i(12'd333, 5'd0,  3'b000, 5'd24, OPC_OP_IMM);

    prog[36] = enc_i(12'd3,   5'd0,  3'b000, 5'd20, OPC_OP_IMM);
    prog[37] = enc_i(-12'sd1, 5'd0,  3'b000, 5'd21, OPC_OP_IMM); // 0xFFFFFFFF unsigned
    prog[38] = enc_b(13'sd8,  5'd21, 5'd20,  3'b110, OPC_BRANCH); // BLTU taken (3 <u huge)
    prog[39] = enc_i(12'd999, 5'd0,  3'b000, 5'd25, OPC_OP_IMM); // squashed
    prog[40] = enc_i(12'd444, 5'd0,  3'b000, 5'd25, OPC_OP_IMM);

    prog[41] = enc_i(-12'sd1, 5'd0,  3'b000, 5'd20, OPC_OP_IMM); // 0xFFFFFFFF unsigned
    prog[42] = enc_i(12'd3,   5'd0,  3'b000, 5'd21, OPC_OP_IMM);
    prog[43] = enc_b(13'sd8,  5'd21, 5'd20,  3'b111, OPC_BRANCH); // BGEU taken (huge >=u 3)
    prog[44] = enc_i(12'd999, 5'd0,  3'b000, 5'd26, OPC_OP_IMM); // squashed
    prog[45] = enc_i(12'd555, 5'd0,  3'b000, 5'd26, OPC_OP_IMM);

    prog[46] = enc_i(12'd1,   5'd0,  3'b000, 5'd20, OPC_OP_IMM);
    prog[47] = enc_i(12'd2,   5'd0,  3'b000, 5'd21, OPC_OP_IMM);
    prog[48] = enc_b(13'sd8,  5'd21, 5'd20,  3'b000, OPC_BRANCH); // BEQ NOT taken (1!=2)
    prog[49] = enc_i(12'd666, 5'd0,  3'b000, 5'd27, OPC_OP_IMM); // executed (fallthrough)

    prog[50] = enc_i(12'd9,   5'd0,  3'b000, 5'd20, OPC_OP_IMM);
    prog[51] = enc_i(12'd3,   5'd0,  3'b000, 5'd21, OPC_OP_IMM);
    prog[52] = enc_b(13'sd8,  5'd21, 5'd20,  3'b110, OPC_BRANCH); // BLTU NOT taken (9 not<u 3)
    prog[53] = enc_i(12'd888, 5'd0,  3'b000, 5'd28, OPC_OP_IMM); // executed (fallthrough)

    prog[54] = enc_i(12'd12,  5'd0,  3'b000, 5'd20, OPC_OP_IMM); // ALU scratch a
    prog[55] = enc_i(12'd10,  5'd0,  3'b000, 5'd21, OPC_OP_IMM); // ALU scratch b
    prog[56] = enc_r(7'b0,    5'd21, 5'd20,  3'b111, 5'd8,  OPC_OP); // AND
    prog[57] = enc_r(7'b0,    5'd21, 5'd20,  3'b110, 5'd16, OPC_OP); // OR
    prog[58] = enc_r(7'b0,    5'd21, 5'd20,  3'b100, 5'd18, OPC_OP); // XOR
    prog[59] = enc_i(12'd3,   5'd21, 3'b001, 5'd19, OPC_OP_IMM);     // SLLI x19,x21,3 (last write)

    prog[60] = halt();

    // ---- subroutine: dead code from sequential flow, reached only via
    // the JAL at idx19 ----
    prog[61] = enc_i(12'd1,   5'd6,  3'b001, 5'd7,  OPC_OP_IMM); // DOUBLE_FN: SLLI x7,x6,1
    prog[62] = enc_i(12'd0,   5'd31, 3'b000, 5'd0,  OPC_JALR);   // return via x31
  end

  // ---- Cycle counting + completion detection ----
  // x19 is the last register written in program order (idx59); the
  // cycle it first reads its expected value is when that core has
  // finished executing the whole program.
  localparam int MAX_CYCLES = 400;

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

  always @(posedge clk) begin
    if (!sc_done && (dut_sc.regfile_inst.regs[19] === 32'd80))
      sc_done <= 1'b1;
    if (!pipe_done && (dut_pipe.regfile_inst.regs[19] === 32'd80))
      pipe_done <= 1'b1;
  end

  task automatic run_until_done();
    int i;
    for (i = 0; i < N_INSTR; i++) begin
      dut_sc.imem_inst.mem[i]   = prog[i];
      dut_pipe.imem_inst.mem[i] = prog[i];
    end
    rst_n = 1'b0;
    @(posedge clk);
    #1; // let this edge's NBA reset update settle before de-asserting
    rst_n = 1'b1;
    while (!(sc_done && pipe_done) &&
           (sc_cycles < MAX_CYCLES) && (pipe_cycles < MAX_CYCLES)) begin
      @(posedge clk);
    end
    #1;
  endtask

  task automatic check_both(input int reg_num, input logic [31:0] expected, input string name);
    logic [31:0] sc_val, pipe_val;
    sc_val   = dut_sc.regfile_inst.regs[reg_num];
    pipe_val = dut_pipe.regfile_inst.regs[reg_num];
    if (sc_val === expected && pipe_val === expected) begin
      pass_count++;
      $display("PASS: %-28s x%0d=%0d (0x%h) — both cores agree", name, reg_num, sc_val, sc_val);
    end else begin
      fail_count++;
      $display("FAIL: %-28s x%0d expected=%0d (0x%h) got sc=%0d (0x%h) pipe=%0d (0x%h)",
                name, reg_num, expected, expected, sc_val, sc_val, pipe_val, pipe_val);
    end
  endtask

  initial begin
    $display("---- full_program integration testbench start ----");
    clk       = 1'b0;
    rst_n     = 1'b1;
    sc_cycles = 0;
    pipe_cycles = 0;
    sc_done   = 1'b0;
    pipe_done = 1'b0;

    run_until_done();

    if (!sc_done) begin
      fail_count++;
      $display("FAIL: single-cycle core did not complete within %0d cycles", MAX_CYCLES);
    end
    if (!pipe_done) begin
      fail_count++;
      $display("FAIL: pipelined core did not complete within %0d cycles", MAX_CYCLES);
    end

    check_both(1,  32'd55,         "x1  sum(1..10)");
    check_both(2,  32'd11,         "x2  loop counter final");
    check_both(3,  32'd11,         "x3  loop limit");
    check_both(4,  32'd0,          "x4  dmem base");
    check_both(5,  32'd55,         "x5  LW reload of sum");
    check_both(6,  32'd21,         "x6  subroutine arg");
    check_both(7,  32'd42,         "x7  doubled via subroutine");
    check_both(8,  32'd8,          "x8  AND");
    check_both(9,  32'd170,        "x9  byte test value");
    check_both(10, 32'hFFFFFFAA,   "x10 LB sign-extended");
    check_both(11, 32'd170,        "x11 LBU zero-extended");
    check_both(12, 32'h00008000,   "x12 LUI half test value");
    check_both(13, 32'hFFFF8000,   "x13 LH sign-extended");
    check_both(14, 32'h00008000,   "x14 LHU zero-extended");
    check_both(15, 32'd4164,       "x15 AUIPC");
    check_both(16, 32'd14,         "x16 OR");
    check_both(17, 32'd777,        "x17 marker after JAL/JALR return");
    check_both(18, 32'd6,          "x18 XOR");
    check_both(19, 32'd80,         "x19 SLLI (last write)");
    check_both(20, 32'd12,         "x20 ALU scratch a (final)");
    check_both(21, 32'd10,         "x21 ALU scratch b (final)");
    check_both(22, 32'd111,        "x22 BEQ taken target");
    check_both(23, 32'd222,        "x23 BNE taken target");
    check_both(24, 32'd333,        "x24 BGE taken target");
    check_both(25, 32'd444,        "x25 BLTU taken target");
    check_both(26, 32'd555,        "x26 BGEU taken target");
    check_both(27, 32'd666,        "x27 BEQ not-taken fallthrough");
    check_both(28, 32'd888,        "x28 BLTU not-taken fallthrough");
    check_both(31, 32'd80,         "x31 JAL link value");

    $display("---- throughput ----");
    $display("single-cycle core: %0d cycles", sc_cycles);
    $display("pipelined core:    %0d cycles", pipe_cycles);
    if (pipe_cycles > 0) begin
      int ratio_x100;
      ratio_x100 = (sc_cycles * 100) / pipe_cycles;
      $display("measured speedup:  %0d.%02dx", ratio_x100 / 100, ratio_x100 % 100);
    end

    $display("---- full_program testbench done: %0d passed, %0d failed ----", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else $display("SOME TESTS FAILED");

    $finish;
  end

endmodule : tb_full_program
