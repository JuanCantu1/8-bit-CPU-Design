// tb_riscv_core_pipelined.sv
// Directed self-checking testbench for the naive 5-stage RV32I pipeline.
// Run via sim/run_riscv_core_pipelined.ps1
//
// Same hand-assembly approach as tb_riscv_core_singlecycle.sv (enc_*
// helpers mirror the RV32I spec directly, halt() self-loops at the end
// of every program). Most cycle counts are generous margin, not a tight
// bound. The RAW-chain and load-use tests are the exception: their
// budgets are deliberately tightened to a value only reachable if
// forwarding is actually eliminating non-load stalls — if forwarding
// silently regressed to stall-only timing (3 extra cycles per hazard),
// those two tests would time out before the dependent instruction's
// writeback and fail on a stale/incorrect register value. That's the
// point: correctness alone doesn't prove forwarding is doing its job,
// since a stalling fallback would also be correct, just slower.
//
// Branch/jump resolution is in EX (2-bubble flush on every taken
// branch/jump) — an earlier revision moved BRANCH/JAL to ID for a
// 1-bubble flush, reverted after tb_full_program.sv measured it as a net
// throughput loss on loop-shaped code (see design-notes.md). Branch/JAL
// test budgets here are generous margin again, not tight bounds.

`timescale 1ns / 1ps

module tb_riscv_core_pipelined;
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

  // ---- RV32I field encoders (same as tb_riscv_core_singlecycle.sv) ----
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
      $display("PASS: %-40s x%0d=%0d (0x%h)", test_name, reg_num, actual, actual);
    end else begin
      fail_count++;
      $display("FAIL: %-40s x%0d expected=%0d (0x%h) got=%0d (0x%h)",
                test_name, reg_num, expected, expected, actual, actual);
    end
  endtask

  initial begin
    $display("---- riscv_core_pipelined testbench start ----");
    clk   = 1'b0;
    rst_n = 1'b1;

    // ---- Test 1: independent instructions, no hazards ----
    prog[0] = enc_i(12'd5,  5'd0, 3'b000, 5'd1, OPC_OP_IMM);          // ADDI x1,x0,5
    prog[1] = enc_i(12'd10, 5'd0, 3'b000, 5'd2, OPC_OP_IMM);          // ADDI x2,x0,10
    prog[2] = enc_i(12'd20, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);          // ADDI x3,x0,20
    prog[3] = halt();
    run_program(4, 15);
    check_reg(1, 32'd5,  "independent: x1");
    check_reg(2, 32'd10, "independent: x2");
    check_reg(3, 32'd20, "independent: x3");

    // ---- Test 2: back-to-back RAW hazard chain (the point of this phase) ----
    prog[0] = enc_i(12'd5, 5'd0, 3'b000, 5'd1, OPC_OP_IMM);           // ADDI x1,x0,5
    prog[1] = enc_r(7'b0, 5'd1, 5'd1, 3'b000, 5'd2, OPC_OP);          // ADD  x2,x1,x1 (RAW on x1, 0-gap)
    prog[2] = enc_i(12'd1, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);           // ADDI x3,x0,1  (independent)
    prog[3] = enc_r(7'b0, 5'd3, 5'd2, 3'b000, 5'd4, OPC_OP);          // ADD  x4,x2,x3 (RAW on x2, 0-gap)
    prog[4] = halt();
    run_program(5, 12); // tight: only reachable if both hazards forward, not stall
    check_reg(1, 32'd5,  "RAW chain: x1");
    check_reg(2, 32'd10, "RAW chain: x2=x1+x1 (stalled for x1)");
    check_reg(3, 32'd1,  "RAW chain: x3");
    check_reg(4, 32'd11, "RAW chain: x4=x2+x3 (stalled for x2)");

    // ---- Test 3: load-use hazard (producer is a LOAD, not an ALU op) ----
    prog[0] = enc_i(12'd100, 5'd0, 3'b000, 5'd1, OPC_OP_IMM);  // ADDI x1,x0,100 (value)
    prog[1] = enc_i(12'd0,   5'd0, 3'b000, 5'd2, OPC_OP_IMM);  // ADDI x2,x0,0   (base addr)
    prog[2] = enc_s(12'd0,   5'd1, 5'd2, 3'b010, OPC_STORE);   // SW x1,0(x2)
    prog[3] = enc_i(12'd0,   5'd2, 3'b010, 5'd3, OPC_LOAD);    // LW x3,0(x2)
    prog[4] = enc_r(7'b0, 5'd3, 5'd3, 3'b000, 5'd4, OPC_OP);   // ADD x4,x3,x3 (RAW on loaded x3, 0-gap)
    prog[5] = halt();
    run_program(6, 15); // tight: only reachable with exactly the 1-cycle load-use stall
    check_reg(3, 32'd100, "load-use: x3 = LW result");
    check_reg(4, 32'd200, "load-use: x4=x3+x3 (stalled for loaded value)");

    // ---- Test 4: branch taken (verifies flush squashes wrong-path instrs) ----
    prog[0] = enc_i(12'd5, 5'd0, 3'b000, 5'd1, OPC_OP_IMM);      // ADDI x1,x0,5
    prog[1] = enc_i(12'd5, 5'd0, 3'b000, 5'd2, OPC_OP_IMM);      // ADDI x2,x0,5
    prog[2] = enc_b(13'sd8, 5'd2, 5'd1, 3'b000, OPC_BRANCH);     // BEQ x1,x2,+8 (taken)
    prog[3] = enc_i(12'd999, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);    // ADDI x3,x0,999 (must be squashed)
    prog[4] = enc_i(12'd111, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);    // ADDI x3,x0,111 (branch target)
    prog[5] = halt();
    run_program(6, 25);
    check_reg(3, 32'd111, "branch taken: flush squashes fallthrough, lands on target");

    // ---- Test 5: branch not taken ----
    prog[0] = enc_i(12'd5, 5'd0, 3'b000, 5'd1, OPC_OP_IMM);      // ADDI x1,x0,5
    prog[1] = enc_i(12'd7, 5'd0, 3'b000, 5'd2, OPC_OP_IMM);      // ADDI x2,x0,7
    prog[2] = enc_b(13'sd8, 5'd2, 5'd1, 3'b000, OPC_BRANCH);     // BEQ x1,x2,+8 (not taken)
    prog[3] = enc_i(12'd999, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);    // ADDI x3,x0,999 (falls through)
    prog[4] = halt();
    run_program(5, 20);
    check_reg(3, 32'd999, "branch not taken: falls through normally");

    // ---- Test 6: JAL / JALR ----
    prog[0] = enc_j(21'sd8, 5'd1, OPC_JAL);                       // JAL x1,+8 (link=PC+4=4, target=8)
    prog[1] = enc_i(12'd999, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);     // x3=999 (must be squashed)
    prog[2] = enc_i(12'd42, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);      // x3=42 (jump target)
    prog[3] = halt();
    run_program(4, 20);
    check_reg(1, 32'd4,  "JAL: link value = PC+4");
    check_reg(3, 32'd42, "JAL: flush squashes fallthrough, lands on target");

    prog[0] = enc_i(12'd8, 5'd0, 3'b000, 5'd5, OPC_OP_IMM);       // ADDI x5,x0,8 (jalr base)
    prog[1] = enc_i(12'd4, 5'd5, 3'b000, 5'd1, OPC_JALR);         // JALR x1,4(x5): target=12, link=8
    prog[2] = enc_i(12'd999, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);     // x3=999 (must be squashed)
    prog[3] = enc_i(12'd77, 5'd0, 3'b000, 5'd3, OPC_OP_IMM);      // x3=77 (jump target)
    prog[4] = halt();
    run_program(5, 25);
    check_reg(1, 32'd8,  "JALR: link value = PC+4");
    check_reg(3, 32'd77, "JALR: flush squashes fallthrough, lands on target");

    // ---- Test 7: LUI / AUIPC ----
    prog[0] = enc_u(20'h12345, 5'd1, OPC_LUI);    // LUI x1,0x12345
    prog[1] = enc_u(20'h00001, 5'd2, OPC_AUIPC);  // AUIPC x2,1 (at PC=4 -> x2=4+0x1000)
    prog[2] = halt();
    run_program(3, 15);
    check_reg(1, 32'h12345000, "LUI: x1 = imm << 12");
    check_reg(2, 32'h00001004, "AUIPC: x2 = PC + (imm << 12)");

    $display("---- riscv_core_pipelined testbench done: %0d passed, %0d failed ----", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else $display("SOME TESTS FAILED");

    $finish;
  end

endmodule : tb_riscv_core_pipelined
