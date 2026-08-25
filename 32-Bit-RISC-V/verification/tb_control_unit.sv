// tb_control_unit.sv
// Directed self-checking testbench for the main control unit. Run via
// sim/run_control_unit.ps1

`timescale 1ns / 1ps

module tb_control_unit;
  import riscv_pkg::*;

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic       funct7b5;

  logic        reg_write, mem_read, mem_write, branch, jump;
  result_src_e result_src;
  alu_src_a_e  alu_src_a;
  alu_src_b_e  alu_src_b;
  imm_src_e    imm_src;
  alu_op_e     alu_op;

  int pass_count = 0;
  int fail_count = 0;

  control_unit dut (
    .opcode     (opcode),
    .funct3     (funct3),
    .funct7b5   (funct7b5),
    .reg_write  (reg_write),
    .mem_read   (mem_read),
    .mem_write  (mem_write),
    .branch     (branch),
    .jump       (jump),
    .result_src (result_src),
    .alu_src_a  (alu_src_a),
    .alu_src_b  (alu_src_b),
    .imm_src    (imm_src),
    .alu_op     (alu_op)
  );

  task automatic check(
    input logic [6:0] op,
    input logic [2:0] f3,
    input logic       f7b5,
    input logic        exp_reg_write,
    input logic        exp_mem_read,
    input logic        exp_mem_write,
    input logic        exp_branch,
    input logic        exp_jump,
    input result_src_e exp_result_src,
    input alu_src_a_e  exp_alu_src_a,
    input alu_src_b_e  exp_alu_src_b,
    input imm_src_e    exp_imm_src,
    input alu_op_e      exp_alu_op,
    input string        test_name
  );
    opcode   = op;
    funct3   = f3;
    funct7b5 = f7b5;
    #1;
    if (reg_write === exp_reg_write && mem_read === exp_mem_read &&
        mem_write === exp_mem_write && branch === exp_branch &&
        jump === exp_jump && result_src === exp_result_src &&
        alu_src_a === exp_alu_src_a && alu_src_b === exp_alu_src_b &&
        imm_src === exp_imm_src && alu_op === exp_alu_op) begin
      pass_count++;
      $display("PASS: %-24s alu_op=%0d", test_name, alu_op);
    end else begin
      fail_count++;
      $display("FAIL: %-24s reg_write=%0b(exp %0b) mem_read=%0b(exp %0b) mem_write=%0b(exp %0b) branch=%0b(exp %0b) jump=%0b(exp %0b) result_src=%0d(exp %0d) alu_src_a=%0d(exp %0d) alu_src_b=%0d(exp %0d) imm_src=%0d(exp %0d) alu_op=%0d(exp %0d)",
                test_name,
                reg_write, exp_reg_write, mem_read, exp_mem_read,
                mem_write, exp_mem_write, branch, exp_branch,
                jump, exp_jump,
                result_src, exp_result_src,
                alu_src_a, exp_alu_src_a,
                alu_src_b, exp_alu_src_b,
                imm_src, exp_imm_src,
                alu_op, exp_alu_op);
    end
  endtask

  initial begin
    $display("---- control_unit testbench start ----");

    // U/J-type.
    check(OPC_LUI,    3'b000, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_ZERO, SRCB_IMM, IMM_U, ALU_ADD, "LUI");
    check(OPC_AUIPC,  3'b000, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_PC,   SRCB_IMM, IMM_U, ALU_ADD, "AUIPC");
    check(OPC_JAL,    3'b000, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b1, RESULT_PC4, SRCA_PC,   SRCB_IMM, IMM_J, ALU_ADD, "JAL");
    check(OPC_JALR,   3'b000, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b1, RESULT_PC4, SRCA_RS1,  SRCB_IMM, IMM_I, ALU_ADD, "JALR");

    // Branches: all 6 funct3 encodings.
    check(OPC_BRANCH, 3'b000, 1'b0, 1'b0,1'b0,1'b0,1'b1,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_B, ALU_SUB,  "BEQ");
    check(OPC_BRANCH, 3'b001, 1'b0, 1'b0,1'b0,1'b0,1'b1,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_B, ALU_SUB,  "BNE");
    check(OPC_BRANCH, 3'b100, 1'b0, 1'b0,1'b0,1'b0,1'b1,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_B, ALU_SLT,  "BLT");
    check(OPC_BRANCH, 3'b101, 1'b0, 1'b0,1'b0,1'b0,1'b1,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_B, ALU_SLT,  "BGE");
    check(OPC_BRANCH, 3'b110, 1'b0, 1'b0,1'b0,1'b0,1'b1,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_B, ALU_SLTU, "BLTU");
    check(OPC_BRANCH, 3'b111, 1'b0, 1'b0,1'b0,1'b0,1'b1,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_B, ALU_SLTU, "BGEU");

    // Loads: control signals are funct3-independent (width is a decoder /
    // memory-stage concern), spot-check two widths.
    check(OPC_LOAD, 3'b010, 1'b0, 1'b1,1'b1,1'b0,1'b0,1'b0, RESULT_MEM, SRCA_RS1, SRCB_IMM, IMM_I, ALU_ADD, "LW");
    check(OPC_LOAD, 3'b000, 1'b0, 1'b1,1'b1,1'b0,1'b0,1'b0, RESULT_MEM, SRCA_RS1, SRCB_IMM, IMM_I, ALU_ADD, "LB");

    // Stores: same reasoning, spot-check two widths.
    check(OPC_STORE, 3'b010, 1'b0, 1'b0,1'b0,1'b1,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_IMM, IMM_S, ALU_ADD, "SW");
    check(OPC_STORE, 3'b000, 1'b0, 1'b0,1'b0,1'b1,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_IMM, IMM_S, ALU_ADD, "SB");

    // OP-IMM: all 8 funct3 encodings, funct7b5 exercised for SRLI/SRAI.
    check(OPC_OP_IMM, 3'b000, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_IMM, IMM_I, ALU_ADD,  "ADDI");
    check(OPC_OP_IMM, 3'b010, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_IMM, IMM_I, ALU_SLT,  "SLTI");
    check(OPC_OP_IMM, 3'b011, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_IMM, IMM_I, ALU_SLTU, "SLTIU");
    check(OPC_OP_IMM, 3'b100, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_IMM, IMM_I, ALU_XOR,  "XORI");
    check(OPC_OP_IMM, 3'b110, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_IMM, IMM_I, ALU_OR,   "ORI");
    check(OPC_OP_IMM, 3'b111, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_IMM, IMM_I, ALU_AND,  "ANDI");
    check(OPC_OP_IMM, 3'b001, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_IMM, IMM_I, ALU_SLL,  "SLLI");
    check(OPC_OP_IMM, 3'b101, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_IMM, IMM_I, ALU_SRL,  "SRLI (funct7b5=0)");
    check(OPC_OP_IMM, 3'b101, 1'b1, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_IMM, IMM_I, ALU_SRA,  "SRAI (funct7b5=1)");

    // OP (R-type): all 10 funct3/funct7b5 encodings.
    check(OPC_OP, 3'b000, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_I, ALU_ADD,  "ADD");
    check(OPC_OP, 3'b000, 1'b1, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_I, ALU_SUB,  "SUB");
    check(OPC_OP, 3'b001, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_I, ALU_SLL,  "SLL");
    check(OPC_OP, 3'b010, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_I, ALU_SLT,  "SLT");
    check(OPC_OP, 3'b011, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_I, ALU_SLTU, "SLTU");
    check(OPC_OP, 3'b100, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_I, ALU_XOR,  "XOR");
    check(OPC_OP, 3'b101, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_I, ALU_SRL,  "SRL");
    check(OPC_OP, 3'b101, 1'b1, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_I, ALU_SRA,  "SRA");
    check(OPC_OP, 3'b110, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_I, ALU_OR,   "OR");
    check(OPC_OP, 3'b111, 1'b0, 1'b1,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_I, ALU_AND,  "AND");

    // Unrecognized opcode (e.g. FENCE) falls through to safe defaults.
    check(7'b0001111, 3'b000, 1'b0, 1'b0,1'b0,1'b0,1'b0,1'b0, RESULT_ALU, SRCA_RS1, SRCB_RS2, IMM_I, ALU_ADD, "unrecognized opcode -> safe defaults");

    $display("---- control_unit testbench done: %0d passed, %0d failed ----", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else $display("SOME TESTS FAILED");

    $finish;
  end

endmodule : tb_control_unit