// tb_fibonacci.sv
// Functional smoke test: an iterative RV32I Fibonacci program (no
// multiply needed — RV32I base doesn't have one, and doesn't need one
// here) computing fib(0)..fib(14), storing each term to memory as it
// goes, checked against known values. This is the "does the whole core
// run a real, recognizable small program correctly" sanity check the
// roadmap calls for, distinct from tb_full_program.sv (which is a
// synthetic hazard/instruction-coverage stress test) and
// tb_compliance.sv (which is architectural edge cases) — this one reads
// like an actual program a person would write. Run via
// sim/run_fibonacci.ps1
//
// Program:
//   x1,x2 = fib(i-2),fib(i-1), seeded with fib(0),fib(1)
//   x3    = next dmem write address
//   x4    = term count (15)
//   x5    = loop index i, starts at 2
//   store fib(0),fib(1) directly, then loop computing/storing
//   fib(2)..fib(14)

`timescale 1ns / 1ps

module tb_fibonacci;
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

  function automatic logic [31:0] enc_j(
    input logic [20:0] imm, input logic [4:0] rd, input logic [6:0] opcode);
    return {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
  endfunction

  function automatic logic [31:0] halt();
    return enc_j(21'sd0, 5'd0, OPC_JAL);
  endfunction

  // ---- Program ----
  localparam int N_TERMS = 15;
  localparam int N_INSTR = 16;
  logic [31:0] prog [0:N_INSTR-1];

  initial begin
    prog[0]  = enc_i(12'd0,  5'd0, 3'b000, 5'd1, OPC_OP_IMM); // x1 = fib(0) = 0
    prog[1]  = enc_i(12'd1,  5'd0, 3'b000, 5'd2, OPC_OP_IMM); // x2 = fib(1) = 1
    prog[2]  = enc_i(12'd0,  5'd0, 3'b000, 5'd3, OPC_OP_IMM); // x3 = write addr = 0
    prog[3]  = enc_i(12'd15, 5'd0, 3'b000, 5'd4, OPC_OP_IMM); // x4 = term count = 15
    prog[4]  = enc_i(12'd2,  5'd0, 3'b000, 5'd5, OPC_OP_IMM); // x5 = i = 2
    prog[5]  = enc_s(12'd0,  5'd1, 5'd3, 3'b010, OPC_STORE);  // mem[0]  = fib(0)
    prog[6]  = enc_s(12'd4,  5'd2, 5'd3, 3'b010, OPC_STORE);  // mem[4]  = fib(1)
    prog[7]  = enc_i(12'd8,  5'd3, 3'b000, 5'd3, OPC_OP_IMM); // x3 += 8
    prog[8]  = enc_r(7'b0,   5'd2, 5'd1, 3'b000, 5'd6, OPC_OP); // LOOP: x6 = fib(i) = x1+x2
    prog[9]  = enc_s(12'd0,  5'd6, 5'd3, 3'b010, OPC_STORE);  // mem[x3] = fib(i)
    prog[10] = enc_r(7'b0,   5'd2, 5'd0, 3'b000, 5'd1, OPC_OP); // x1 = x2
    prog[11] = enc_r(7'b0,   5'd6, 5'd0, 3'b000, 5'd2, OPC_OP); // x2 = x6
    prog[12] = enc_i(12'd4,  5'd3, 3'b000, 5'd3, OPC_OP_IMM); // x3 += 4
    prog[13] = enc_i(12'd1,  5'd5, 3'b000, 5'd5, OPC_OP_IMM); // i += 1
    prog[14] = enc_b(-13'sd24, 5'd4, 5'd5, 3'b100, OPC_BRANCH); // BLT i,count,LOOP
    prog[15] = halt();
  end

  task automatic run_program(input int n_cycles);
    int i;
    for (i = 0; i < N_INSTR; i++) dut.imem_inst.mem[i] = prog[i];
    rst_n = 1'b0;
    @(posedge clk);
    #1;
    rst_n = 1'b1;
    repeat (n_cycles) @(posedge clk);
    #1;
  endtask

  task automatic check_mem_word(input int addr, input logic [31:0] expected, input string name);
    logic [31:0] actual;
    actual = {dut.dmem_inst.mem[addr+3], dut.dmem_inst.mem[addr+2],
              dut.dmem_inst.mem[addr+1], dut.dmem_inst.mem[addr]};
    if (actual === expected) begin
      pass_count++;
      $display("PASS: %-16s mem[%0d]=%0d", name, addr, actual);
    end else begin
      fail_count++;
      $display("FAIL: %-16s mem[%0d] expected=%0d got=%0d", name, addr, expected, actual);
    end
  endtask

  task automatic check_reg(input int reg_num, input logic [31:0] expected, input string name);
    logic [31:0] actual;
    actual = dut.regfile_inst.regs[reg_num];
    if (actual === expected) begin
      pass_count++;
      $display("PASS: %-16s x%0d=%0d", name, reg_num, actual);
    end else begin
      fail_count++;
      $display("FAIL: %-16s x%0d expected=%0d got=%0d", name, reg_num, expected, actual);
    end
  endtask

  initial begin
    int fib [0:N_TERMS-1];
    int i;

    fib[0] = 0;
    fib[1] = 1;
    for (i = 2; i < N_TERMS; i++) fib[i] = fib[i-1] + fib[i-2];

    $display("---- Fibonacci smoke test start ----");
    clk   = 1'b0;
    rst_n = 1'b1;

    run_program(200);

    for (i = 0; i < N_TERMS; i++)
      check_mem_word(i * 4, fib[i], $sformatf("fib(%0d)", i));

    check_reg(1, fib[N_TERMS-2], "x1 final");
    check_reg(2, fib[N_TERMS-1], "x2 final");
    check_reg(5, 32'd15,         "i final");

    $display("---- Fibonacci smoke test done: %0d passed, %0d failed ----", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else $display("SOME TESTS FAILED");

    $finish;
  end

endmodule : tb_fibonacci
