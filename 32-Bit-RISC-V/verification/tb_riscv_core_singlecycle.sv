// tb_riscv_core_singlecycle.sv
// Directed self-checking testbench for the single-cycle RV32I datapath.
// Run via sim/run_riscv_core_singlecycle.ps1
//
// Each test hand-assembles a tiny program with the enc_* helper functions
// below (which mirror the RV32I spec's field encoding directly, same
// approach used in tb_decoder.sv), pokes it into instruction memory via a
// hierarchical reference, runs the core for a fixed number of cycles, and
// checks the resulting register/memory state. Every program ends with
// `JAL x0, 0` (self-loop) so the core halts safely regardless of how many
// extra cycles it's given.

`timescale 1ns / 1ps

module tb_riscv_core_singlecycle;
  import riscv_pkg::*;

  logic clk;
  logic rst_n;

  int pass_count = 0;
  int fail_count = 0;

  riscv_core_singlecycle dut (
    .clk   (clk),
    .rst_n (rst_n)
  );

  always #5 clk = ~clk;

  // ---- RV32I field encoders (independent of decoder.sv's slicing) ----
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

  // ---- Program load + run ----
  logic [31:0] prog [0:31];

  task automatic run_program(input int n_instr, input int n_cycles);
    int i;
    for (i = 0; i < n_instr; i++) dut.imem_inst.mem[i] = prog[i];
    rst_n = 1'b0;
    @(posedge clk);
    #1; // let this edge's NBA reset update settle before de-asserting
    rst_n = 1'b1;
    repeat (n_cycles) @(posedge clk);
    #1;
  endtask

  // ---- Checks ----
  task automatic check_reg(input int reg_num, input logic [31:0] expected, input string test_name);
    logic [31:0] actual;
    actual = dut.regfile_inst.regs[reg_num];
    if (actual === expected) begin
      pass_count++;
      $display("PASS: %-28s x%0d=%0d (0x%h)", test_name, reg_num, actual, actual);
    end else begin
      fail_count++;
      $display("FAIL: %-28s x%0d expected=%0d (0x%h) got=%0d (0x%h)",
                test_name, reg_num, expected, expected, actual, actual);
    end
  endtask

  task automatic check_mem_word(input int addr, input logic [31:0] expected, input string test_name);
    logic [31:0] actual;
    actual = {dut.dmem_inst.mem[addr+3], dut.dmem_inst.mem[addr+2],
              dut.dmem_inst.mem[addr+1], dut.dmem_inst.mem[addr]};
    if (actual === expected) begin
      pass_count++;
      $display("PASS: %-28s mem[%0d]=%0d (0x%h)", test_name, addr, actual, actual);
    end else begin
      fail_count++;
      $display("FAIL: %-28s mem[%0d] expected=%0d (0x%h) got=%0d (0x%h)",
                test_name, addr, expected, expected, actual, actual);
    end
  endtask

  initial begin
    $display("---- riscv_core_singlecycle testbench start ----");
    clk   = 1'b0;
    rst_n = 1'b1;

    // ---- Test 1: R-type / I-type arithmetic ----
    prog[0] = enc_i(12'd5,  5'd0, 3'b000, 5'd1, OPC_OP_IMM);          // ADDI x1,x0,5
    prog[1] = enc_i(12'd10, 5'd0, 3'b000, 5'd2, OPC_OP_IMM);          // ADDI x2,x0,10
    prog[2] = enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, OPC_OP);    // ADD  x3,x1,x2
    prog[3] = enc_r(7'b0100000, 5'd1, 5'd2, 3'b000, 5'd4, OPC_OP);    // SUB  x4,x2,x1
    prog[4] = enc_r(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd5, OPC_OP);    // AND  x5,x1,x2
    prog[5] = enc_r(7'b0000000, 5'd2, 5'd1, 3'b110, 5'd6, OPC_OP);    // OR   x6,x1,x2
    prog[6] = halt();
    run_program(7, 12);
    check_reg(1, 32'd5,  "arith: x1");
    check_reg(2, 32'd10, "arith: x2");
    check_reg(3, 32'd15, "arith: x3=x1+x2");
    check_reg(4, 32'd5,  "arith: x4=x2-x1");
    check_reg(5, 32'd0,  "arith: x5=x1&x2");
    check_reg(6, 32'd15, "arith: x6=x1|x2");

    // ---- Test 2: load/store round trip ----
    prog[0] = enc_i(12'd100, 5'd0, 3'b000, 5'd1, OPC_OP_IMM);  // ADDI x1,x0,100 (value)
    prog[1] = enc_i(12'd0,   5'd0, 3'b000, 5'd2, OPC_OP_IMM);  // ADDI x2,x0,0   (base addr)
    prog[2] = enc_s(12'd0,   5'd1, 5'd2, 3'b010, OPC_STORE);   // SW x1,0(x2)
    prog[3] = enc_i(12'd0,   5'd2, 3'b010, 5'd3, OPC_LOAD);    // LW x3,0(x2)
    prog[4] = halt();
    run_program(5, 10);
    check_reg(3, 32'd100, "load-store: x3 = LW(SW x1)");
    check_mem_word(0, 32'd100, "load-store: mem[0] raw bytes");

    // ---- Test 3: branch taken ----
    prog[0] = enc_i(12'd5, 5'd0, 3'b000, 5'd1, OPC_OP_IMM);      // ADDI x1,x0,5
    prog[1] = enc_i(12'd5, 5'd0, 3'b000, 5'd2, OPC_OP_IMM);      // ADDI x2,x0,5
    prog[2] = enc_b(13'sd8, 5'd2, 5'd1, 3'b000, OPC_BRANCH);     // BEQ x1,x2,+8 (taken)
    prog[3] = enc_i(12'd999, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);    // ADDI x3,x0,999 (skipped)
    prog[4] = enc_i(12'd111, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);    // ADDI x3,x0,111 (branch target)
    prog[5] = halt();
    run_program(6, 12);
    check_reg(3, 32'd111, "branch taken: skips to target");

    // ---- Test 4: branch not taken ----
    prog[0] = enc_i(12'd5, 5'd0, 3'b000, 5'd1, OPC_OP_IMM);      // ADDI x1,x0,5
    prog[1] = enc_i(12'd7, 5'd0, 3'b000, 5'd2, OPC_OP_IMM);      // ADDI x2,x0,7
    prog[2] = enc_b(13'sd8, 5'd2, 5'd1, 3'b000, OPC_BRANCH);     // BEQ x1,x2,+8 (not taken)
    prog[3] = enc_i(12'd999, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);    // ADDI x3,x0,999 (falls through)
    prog[4] = halt();
    run_program(5, 10);
    check_reg(3, 32'd999, "branch not taken: falls through");

    // ---- Test 5: JAL / JALR ----
    prog[0] = enc_j(21'sd8, 5'd1, OPC_JAL);                       // JAL x1,+8 (link=PC+4=4, target=8)
    prog[1] = enc_i(12'd999, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);     // x3=999 (skipped)
    prog[2] = enc_i(12'd42, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);      // x3=42 (jump target)
    prog[3] = halt();
    run_program(4, 10);
    check_reg(1, 32'd4,  "JAL: link value = PC+4");
    check_reg(3, 32'd42, "JAL: jumped to target, skipped fallthrough");

    prog[0] = enc_i(12'd8, 5'd0, 3'b000, 5'd5, OPC_OP_IMM);       // ADDI x5,x0,8 (jalr base)
    prog[1] = enc_i(12'd4, 5'd5, 3'b000, 5'd1, OPC_JALR);         // JALR x1,4(x5): target=12, link=8
    prog[2] = enc_i(12'd999, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);     // x3=999 (skipped)
    prog[3] = enc_i(12'd77, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);      // x3=77 (jump target)
    prog[4] = halt();
    run_program(5, 12);
    check_reg(1, 32'd8,  "JALR: link value = PC+4");
    check_reg(3, 32'd77, "JALR: jumped to rs1+imm target");

    // ---- Test 6: LUI / AUIPC ----
    prog[0] = enc_u(20'h12345, 5'd1, OPC_LUI);    // LUI x1,0x12345
    prog[1] = enc_u(20'h00001, 5'd2, OPC_AUIPC);  // AUIPC x2,1 (at PC=4 -> x2=4+0x1000)
    prog[2] = halt();
    run_program(3, 8);
    check_reg(1, 32'h12345000, "LUI: x1 = imm << 12");
    check_reg(2, 32'h00001004, "AUIPC: x2 = PC + (imm << 12)");

    $display("---- riscv_core_singlecycle testbench done: %0d passed, %0d failed ----", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else $display("SOME TESTS FAILED");

    $finish;
  end

endmodule : tb_riscv_core_singlecycle
