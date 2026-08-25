// tb_alu.sv
// Directed self-checking testbench for the ALU. Run via sim/run_alu.sh

`timescale 1ns / 1ps

module tb_alu;
  import riscv_pkg::*;

  logic [XLEN-1:0] operand_a, operand_b;
  alu_op_e         alu_op;
  logic [XLEN-1:0] result;
  logic            zero;

  int pass_count = 0;
  int fail_count = 0;

  alu dut (
    .operand_a (operand_a),
    .operand_b (operand_b),
    .alu_op    (alu_op),
    .result    (result),
    .zero      (zero)
  );

  task automatic check(
    input logic [XLEN-1:0] a,
    input logic [XLEN-1:0] b,
    input alu_op_e         op,
    input logic [XLEN-1:0] expected,
    input string           test_name
  );
    operand_a = a;
    operand_b = b;
    alu_op    = op;
    #1;
    if (result === expected) begin
      pass_count++;
      $display("PASS: %-28s result=%0d (0x%h)", test_name, result, result);
    end else begin
      fail_count++;
      $display("FAIL: %-28s expected=%0d (0x%h) got=%0d (0x%h)",
                test_name, expected, expected, result, result);
    end
  endtask

  initial begin
    $display("---- ALU testbench start ----");

    check(32'd10,        32'd5,        ALU_ADD,  32'd15,       "add positive");
    check(32'd5,         32'd10,       ALU_ADD,  32'd15,       "add commutative");
    check(-32'sd5,       32'd10,       ALU_ADD,  32'd5,        "add negative+positive");
    check(32'd10,        32'd5,        ALU_SUB,  32'd5,        "sub positive");
    check(32'd5,         32'd10,       ALU_SUB,  -32'sd5,      "sub result negative");
    check(32'hFF00FF00,  32'h0F0F0F0F, ALU_AND,  32'h0F000F00, "and");
    check(32'hFF00FF00,  32'h0F0F0F0F, ALU_OR,   32'hFF0FFF0F, "or");
    check(32'hFF00FF00,  32'h0F0F0F0F, ALU_XOR,  32'hF00FF00F, "xor");
    check(32'h00000001,  32'd4,        ALU_SLL,  32'h00000010, "sll by 4");
    check(32'h00000001,  32'd0,        ALU_SLL,  32'h00000001, "sll by 0");
    check(32'h00000001,  32'd31,       ALU_SLL,  32'h80000000, "sll by 31 (max shamt)");
    check(32'h80000000,  32'd4,        ALU_SRL,  32'h08000000, "srl logical, zero-fill");
    check(32'h80000000,  32'd4,        ALU_SRA,  32'hF8000000, "sra arithmetic, sign-fill");
    check(32'h000000F0,  32'd4,        ALU_SRA,  32'h0000000F, "sra positive number");
    check(-32'sd1,       32'd1,        ALU_SLT,  32'd1,        "slt negative < positive");
    check(32'd7,         32'd7,        ALU_SLT,  32'd0,        "slt equal");
    check(-32'sd1,       32'd1,        ALU_SLTU, 32'd0,        "sltu large unsigned vs small");
    check(32'd7,         32'd7,        ALU_SLTU, 32'd0,        "sltu equal");
    check(32'd5,         -32'sd5,      ALU_ADD,  32'd0,        "add to zero");

    if (zero !== 1'b1) begin
      fail_count++;
      $display("FAIL: %-28s zero flag not set", "zero flag check");
    end else begin
      pass_count++;
      $display("PASS: %-28s zero flag correctly set", "zero flag check");
    end

    $display("---- ALU testbench done: %0d passed, %0d failed ----", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else $display("SOME TESTS FAILED");

    $finish;
  end

endmodule : tb_alu