// tb_compliance.sv
// Hand-ported compliance-style edge case coverage, in the spirit of
// riscv-tests' rv32ui suite. NOT the official upstream suite — no
// RISC-V cross-compiler toolchain is available in this environment, and
// the standard riscv-tests/riscv-arch-test boot harness assumes CSR
// support (mtvec/mstatus/etc.) this core doesn't implement. Instead,
// these are hand-encoded (via the same enc_* helpers used throughout
// this project) instruction sequences targeting the classic RV32I
// compliance bug patterns riscv-tests is built around: signed overflow
// wraparound, shift-amount masking to 5 bits, signed-vs-unsigned
// comparison at the MIN_INT/MAX_INT boundary (for SLT/SLTU and for
// branches), and byte-sign-extension at the exact 0x7F/0x80 boundary.
// These are semantic/architectural edge cases, distinct from the
// hazard-timing scenarios tb_riscv_core_pipelined.sv already covers —
// this file assumes hazards/forwarding are already correct and focuses
// purely on "does each instruction compute the architecturally correct
// result at its trickiest operand values." Run via
// sim/run_compliance.ps1

`timescale 1ns / 1ps

module tb_compliance;
  import riscv_pkg::*;

  logic clk;
  logic rst_n;

  int pass_count = 0;
  int fail_count = 0;

  riscv_core_pipelined dut (
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

  // ---- Program load + run ----
  logic [31:0] prog [0:31];

  task automatic run_program(input int n_instr, input int n_cycles);
    int i;
    for (i = 0; i < n_instr; i++) dut.imem_inst.mem[i] = prog[i];
    rst_n = 1'b0;
    @(posedge clk);
    #1;
    rst_n = 1'b1;
    repeat (n_cycles) @(posedge clk);
    #1;
  endtask

  task automatic check_reg(input int reg_num, input logic [31:0] expected, input string test_name);
    logic [31:0] actual;
    actual = dut.regfile_inst.regs[reg_num];
    if (actual === expected) begin
      pass_count++;
      $display("PASS: %-46s x%0d=0x%h", test_name, reg_num, actual);
    end else begin
      fail_count++;
      $display("FAIL: %-46s x%0d expected=0x%h got=0x%h", test_name, reg_num, expected, actual);
    end
  endtask

  initial begin
    $display("---- compliance-style testbench start ----");
    clk   = 1'b0;
    rst_n = 1'b1;

    // ---- Group 1: ADD/SUB signed overflow wraparound (RV32I add/sub
    // are modular — no overflow trap, MAX_INT+1 wraps to MIN_INT) ----
    prog[0] = enc_u(20'h80000, 5'd1, OPC_LUI);                  // x1 = MIN_INT (0x80000000)
    prog[1] = enc_i(-12'sd1, 5'd1, 3'b000, 5'd2, OPC_OP_IMM);   // x2 = MAX_INT (0x7FFFFFFF)
    prog[2] = enc_i(12'd1, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);     // x3 = 1
    prog[3] = enc_r(7'b0, 5'd3, 5'd2, 3'b000, 5'd4, OPC_OP);    // x4 = MAX_INT + 1
    prog[4] = enc_r(7'b0100000, 5'd3, 5'd1, 3'b000, 5'd5, OPC_OP); // x5 = MIN_INT - 1
    prog[5] = halt();
    run_program(6, 15);
    check_reg(4, 32'h80000000, "ADD: MAX_INT+1 wraps to MIN_INT");
    check_reg(5, 32'h7FFFFFFF, "SUB: MIN_INT-1 wraps to MAX_INT");

    // ---- Group 2: AND/OR/XOR identity/absorbing cases with -1 ----
    prog[0] = enc_i(-12'sd1, 5'd0, 3'b000, 5'd7, OPC_OP_IMM);   // x7 = 0xFFFFFFFF
    prog[1] = enc_i(12'd1234, 5'd0, 3'b000, 5'd8, OPC_OP_IMM);  // x8 = 1234
    prog[2] = enc_r(7'b0, 5'd8, 5'd7, 3'b111, 5'd9, OPC_OP);    // x9  = x7 AND x8 (identity)
    prog[3] = enc_r(7'b0, 5'd8, 5'd7, 3'b110, 5'd10, OPC_OP);   // x10 = x7 OR x8  (all ones)
    prog[4] = enc_r(7'b0, 5'd8, 5'd8, 3'b100, 5'd11, OPC_OP);   // x11 = x8 XOR x8 (zero)
    prog[5] = enc_r(7'b0, 5'd7, 5'd8, 3'b100, 5'd12, OPC_OP);   // x12 = x8 XOR x7 (bitwise NOT)
    prog[6] = halt();
    run_program(7, 15);
    check_reg(9,  32'd1234,      "AND: x AND -1 == x (identity)");
    check_reg(10, 32'hFFFFFFFF,  "OR: x OR -1 == -1 (absorbing)");
    check_reg(11, 32'd0,         "XOR: x XOR x == 0");
    check_reg(12, 32'hFFFFFB2D,  "XOR: x XOR -1 == ~x");

    // ---- Group 3: shift amount masks to 5 bits (shift by 32 == shift
    // by 0, per spec — a naive "shift by the full register value"
    // implementation would get this wrong) ----
    prog[0] = enc_i(12'd1, 5'd0, 3'b000, 5'd1, OPC_OP_IMM);     // x1 = 1
    prog[1] = enc_i(12'd32, 5'd0, 3'b000, 5'd2, OPC_OP_IMM);    // x2 = 32
    prog[2] = enc_r(7'b0, 5'd2, 5'd1, 3'b001, 5'd3, OPC_OP);    // x3 = x1 << (32 & 0x1F) = x1 << 0
    prog[3] = enc_i(12'd33, 5'd0, 3'b000, 5'd4, OPC_OP_IMM);    // x4 = 33
    prog[4] = enc_r(7'b0, 5'd4, 5'd1, 3'b001, 5'd5, OPC_OP);    // x5 = x1 << (33 & 0x1F) = x1 << 1
    prog[5] = halt();
    run_program(6, 15);
    check_reg(3, 32'd1, "SLL: shift by 32 masks to shift by 0");
    check_reg(5, 32'd2, "SLL: shift by 33 masks to shift by 1");

    // ---- Group 4: SRA sign-extension at extremes ----
    prog[0] = enc_u(20'h80000, 5'd1, OPC_LUI);                  // x1 = MIN_INT
    prog[1] = enc_i(12'd31, 5'd0, 3'b000, 5'd2, OPC_OP_IMM);    // x2 = 31
    prog[2] = enc_r(7'b0100000, 5'd2, 5'd1, 3'b101, 5'd3, OPC_OP); // x3 = MIN_INT >>> 31
    prog[3] = enc_i(-12'sd1, 5'd0, 3'b000, 5'd4, OPC_OP_IMM);   // x4 = -1
    prog[4] = enc_i(12'd5, 5'd0, 3'b000, 5'd5, OPC_OP_IMM);     // x5 = 5
    prog[5] = enc_r(7'b0100000, 5'd5, 5'd4, 3'b101, 5'd6, OPC_OP); // x6 = -1 >>> 5
    prog[6] = halt();
    run_program(7, 15);
    check_reg(3, 32'hFFFFFFFF, "SRA: MIN_INT >>> 31 == -1 (all sign bits)");
    check_reg(6, 32'hFFFFFFFF, "SRA: -1 >>> 5 == -1 (sign-extends forever)");

    // ---- Group 5: SLT signed comparison at MIN_INT/MAX_INT boundary ----
    prog[0] = enc_u(20'h80000, 5'd1, OPC_LUI);                  // x1 = MIN_INT
    prog[1] = enc_i(-12'sd1, 5'd1, 3'b000, 5'd2, OPC_OP_IMM);   // x2 = MAX_INT
    prog[2] = enc_r(7'b0, 5'd2, 5'd1, 3'b010, 5'd3, OPC_OP);    // x3 = (MIN_INT < MAX_INT) signed
    prog[3] = enc_r(7'b0, 5'd1, 5'd2, 3'b010, 5'd4, OPC_OP);    // x4 = (MAX_INT < MIN_INT) signed
    prog[4] = halt();
    run_program(5, 15);
    check_reg(3, 32'd1, "SLT: MIN_INT < MAX_INT (signed) is true");
    check_reg(4, 32'd0, "SLT: MAX_INT < MIN_INT (signed) is false");

    // ---- Group 6: SLTU unsigned comparison at the 0 / 0xFFFFFFFF
    // boundary ----
    prog[0] = enc_i(12'd0, 5'd0, 3'b000, 5'd1, OPC_OP_IMM);     // x1 = 0
    prog[1] = enc_i(-12'sd1, 5'd0, 3'b000, 5'd2, OPC_OP_IMM);   // x2 = 0xFFFFFFFF
    prog[2] = enc_r(7'b0, 5'd2, 5'd1, 3'b011, 5'd3, OPC_OP);    // x3 = (0 <u 0xFFFFFFFF)
    prog[3] = enc_r(7'b0, 5'd1, 5'd2, 3'b011, 5'd4, OPC_OP);    // x4 = (0xFFFFFFFF <u 0)
    prog[4] = halt();
    run_program(5, 15);
    check_reg(3, 32'd1, "SLTU: 0 <u 0xFFFFFFFF is true");
    check_reg(4, 32'd0, "SLTU: 0xFFFFFFFF <u 0 is false");

    // ---- Group 7: SLTI vs SLTIU — the SAME bit pattern (MIN_INT)
    // compared against the SAME immediate (0), opposite results ----
    prog[0] = enc_u(20'h80000, 5'd1, OPC_LUI);                  // x1 = MIN_INT (0x80000000)
    prog[1] = enc_i(12'd0, 5'd1, 3'b010, 5'd2, OPC_OP_IMM);     // x2 = (MIN_INT <s 0)
    prog[2] = enc_i(12'd0, 5'd1, 3'b011, 5'd3, OPC_OP_IMM);     // x3 = (MIN_INT <u 0)
    prog[3] = halt();
    run_program(4, 15);
    check_reg(2, 32'd1, "SLTI: MIN_INT < 0 (signed) is true");
    check_reg(3, 32'd0, "SLTIU: MIN_INT < 0 (unsigned) is false");

    // ---- Group 8: branch signed vs unsigned at the same MIN_INT/
    // MAX_INT boundary — BLT and BLTU disagree on the SAME operands ----
    prog[0] = enc_u(20'h80000, 5'd1, OPC_LUI);                  // x1 = MIN_INT
    prog[1] = enc_i(-12'sd1, 5'd1, 3'b000, 5'd2, OPC_OP_IMM);   // x2 = MAX_INT
    prog[2] = enc_b(13'sd8, 5'd2, 5'd1, 3'b100, OPC_BRANCH);    // BLT x1,x2,+8 (taken: signed)
    prog[3] = enc_i(12'd999, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);   // squashed
    prog[4] = enc_i(12'd111, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);   // x3 = 111
    prog[5] = enc_b(13'sd8, 5'd2, 5'd1, 3'b110, OPC_BRANCH);    // BLTU x1,x2,+8 (NOT taken: unsigned)
    prog[6] = enc_i(12'd222, 5'd0, 3'b000, 5'd4, OPC_OP_IMM);   // executed (fallthrough)
    prog[7] = halt();
    run_program(8, 25);
    check_reg(3, 32'd111, "BLT: MIN_INT < MAX_INT (signed) taken");
    check_reg(4, 32'd222, "BLTU: MIN_INT < MAX_INT (unsigned) NOT taken — same operands, opposite outcome");

    // ---- Group 9: byte sign-extension at the exact 0x7F/0x80 boundary ----
    prog[0]  = enc_i(12'd0, 5'd0, 3'b000, 5'd1, OPC_OP_IMM);    // x1 = dmem base
    prog[1]  = enc_i(12'd127, 5'd0, 3'b000, 5'd2, OPC_OP_IMM);  // x2 = 0x7F (max positive byte)
    prog[2]  = enc_s(12'd0, 5'd2, 5'd1, 3'b000, OPC_STORE);     // SB x2,0(x1)
    prog[3]  = enc_i(12'd0, 5'd1, 3'b000, 5'd3, OPC_LOAD);      // LB x3,0(x1) -> stays positive
    prog[4]  = enc_i(-12'sd128, 5'd0, 3'b000, 5'd4, OPC_OP_IMM); // x4 = 0xFFFFFF80 (low byte = 0x80)
    prog[5]  = enc_s(12'd1, 5'd4, 5'd1, 3'b000, OPC_STORE);     // SB x4,1(x1) -> mem[1]=0x80
    prog[6]  = enc_i(12'd1, 5'd1, 3'b000, 5'd5, OPC_LOAD);      // LB  x5,1(x1) -> sign-extends negative
    prog[7]  = enc_i(12'd1, 5'd1, 3'b100, 5'd6, OPC_LOAD);      // LBU x6,1(x1) -> zero-extends positive
    prog[8]  = halt();
    run_program(9, 20);
    check_reg(3, 32'd127,       "LB: 0x7F stays positive (127)");
    check_reg(5, 32'hFFFFFF80,  "LB: 0x80 sign-extends negative");
    check_reg(6, 32'd128,       "LBU: 0x80 zero-extends positive (128)");

    $display("---- compliance-style testbench done: %0d passed, %0d failed ----", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else $display("SOME TESTS FAILED");

    $finish;
  end

endmodule : tb_compliance
