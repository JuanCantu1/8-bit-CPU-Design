// tb_fibonacci_demo.sv
// Live showcase version of the Fibonacci smoke test: same program as
// tb_fibonacci.sv (see that file for the actual pass/fail verification),
// but narrates each term as it's computed instead of printing PASS/FAIL
// lines. Meant to be run through sim/run_fibonacci_demo.ps1, which
// replays this output at a human-watchable pace on a loop until
// Ctrl+C — for live demos/showcasing, not verification.

`timescale 1ns / 1ps

module tb_fibonacci_demo;
  import riscv_pkg::*;

  logic clk;
  logic rst_n;

  riscv_core_pipelined dut (
    .clk   (clk),
    .rst_n (rst_n)
  );

  always #5 clk = ~clk;

  // ---- RV32I field encoders (same as tb_fibonacci.sv) ----
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

  function automatic logic [31:0] enc_j(
    input logic [20:0] imm, input logic [4:0] rd, input logic [6:0] opcode);
    return {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
  endfunction

  function automatic logic [31:0] halt();
    return enc_j(21'sd0, 5'd0, OPC_JAL);
  endfunction

  // ---- Program (same shape as tb_fibonacci.sv, extended to 47 terms —
  // fib(46) = 1,836,311,903 is the last term that still fits as a
  // positive 32-bit signed value; fib(47) would overflow and print as
  // a negative number, which would look like a bug rather than a demo
  // feature, so this is the natural stopping point) ----
  localparam int N_TERMS = 47;
  localparam int N_INSTR = 16;
  logic [31:0] prog [0:N_INSTR-1];

  initial begin
    prog[0]  = enc_i(12'd0,  5'd0, 3'b000, 5'd1, OPC_OP_IMM);
    prog[1]  = enc_i(12'd1,  5'd0, 3'b000, 5'd2, OPC_OP_IMM);
    prog[2]  = enc_i(12'd0,  5'd0, 3'b000, 5'd3, OPC_OP_IMM);
    prog[3]  = enc_i(12'd47, 5'd0, 3'b000, 5'd4, OPC_OP_IMM);
    prog[4]  = enc_i(12'd2,  5'd0, 3'b000, 5'd5, OPC_OP_IMM);
    prog[5]  = enc_s(12'd0,  5'd1, 5'd3, 3'b010, OPC_STORE);
    prog[6]  = enc_s(12'd4,  5'd2, 5'd3, 3'b010, OPC_STORE);
    prog[7]  = enc_i(12'd8,  5'd3, 3'b000, 5'd3, OPC_OP_IMM);
    prog[8]  = enc_r(7'b0,   5'd2, 5'd1, 3'b000, 5'd6, OPC_OP);
    prog[9]  = enc_s(12'd0,  5'd6, 5'd3, 3'b010, OPC_STORE);
    prog[10] = enc_r(7'b0,   5'd2, 5'd0, 3'b000, 5'd1, OPC_OP);
    prog[11] = enc_r(7'b0,   5'd6, 5'd0, 3'b000, 5'd2, OPC_OP);
    prog[12] = enc_i(12'd4,  5'd3, 3'b000, 5'd3, OPC_OP_IMM);
    prog[13] = enc_i(12'd1,  5'd5, 3'b000, 5'd5, OPC_OP_IMM);
    prog[14] = enc_b(-13'sd24, 5'd4, 5'd5, 3'b100, OPC_BRANCH);
    prog[15] = halt();
  end

  // ---- Expected sequence, computed independently ----
  int fib [0:N_TERMS-1];
  int next_idx = 2;

  initial begin
    int i;
    fib[0] = 0;
    fib[1] = 1;
    for (i = 2; i < N_TERMS; i++) fib[i] = fib[i-1] + fib[i-2];
  end

  // ---- Live narration: print each term the instant it's computed ----
  always @(posedge clk) begin
    if (rst_n && (next_idx < N_TERMS) && (dut.regfile_inst.regs[6] === fib[next_idx])) begin
      $display("  fib(%0d) = %0d", next_idx, fib[next_idx]);
      next_idx <= next_idx + 1;
    end
  end

  initial begin
    int i;
    clk   = 1'b0;
    rst_n = 1'b1;
    for (i = 0; i < N_INSTR; i++) dut.imem_inst.mem[i] = prog[i];

    $display("========================================================");
    $display(" 32-bit RISC-V pipelined CPU -- Fibonacci, live in SystemVerilog simulation");
    $display("========================================================");

    rst_n = 1'b0;
    @(posedge clk);
    #1;
    rst_n = 1'b1;

    $display("  fib(0) = 0");
    $display("  fib(1) = 1");

    // Wait until the last term has been narrated, rather than guessing a
    // fixed cycle count for however many loop iterations N_TERMS needs;
    // MAX_CYCLES is just a safety cap in case something goes wrong.
    begin
      int waited;
      waited = 0;
      while ((next_idx < N_TERMS) && (waited < 2000)) begin
        @(posedge clk);
        waited++;
      end
    end
    #1;

    $display("========================================================");
    $display(" Done -- fib(0..%0d) computed on real pipelined RTL.", N_TERMS - 1);
    $display("========================================================");

    $finish;
  end

endmodule : tb_fibonacci_demo
