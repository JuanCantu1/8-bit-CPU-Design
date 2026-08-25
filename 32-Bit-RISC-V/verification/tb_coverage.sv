// tb_coverage.sv
// Coverage-driven testbench: runs a purpose-built instruction stream
// through riscv_core_pipelined while coverage_collector.sv watches its
// internal signals, then lets the collector's `final` block print a
// functional coverage report. No pass/fail checking of its own —
// correctness of this core is already established by
// tb_riscv_core_pipelined.sv and tb_full_program.sv; this testbench's
// only job is to exercise every coverage bin at least once. Run via
// sim/run_coverage.ps1.
//
// The program is built with a running instruction-count variable and
// saved label indices (lbl_* below) rather than hand-computed branch/
// jump offsets, specifically to avoid the off-by-one arithmetic errors
// that hand-counted indices invite once a program gets much past a
// dozen instructions.
//
// Deliberately includes scenarios the broader tb_full_program.sv never
// exercises: SRL/SRA (only ADD/SUB/AND/OR/XOR/SLL/SLT/SLTU show up
// there), a load-use hazard stall, engineered back-to-back and
// one-gap dependencies to force both EX/MEM and MEM/WB forwarding on
// both ALU operands, x0 used explicitly as rs2, and not-taken outcomes
// for BNE/BGE/BGEU (tb_full_program only drove BEQ and BLTU not-taken).
// See design-notes.md "Functional coverage" for why each of these
// turned out to be a real, previously-invisible gap.

`timescale 1ns / 1ps

module tb_coverage;
  import riscv_pkg::*;

  logic clk;
  logic rst_n;

  riscv_core_pipelined dut (
    .clk   (clk),
    .rst_n (rst_n)
  );

  coverage_collector cov_inst (
    .clk            (clk),
    .rst_n          (rst_n),
    .id_opcode      (dut.id_opcode),
    .if_id_valid    (dut.if_id_q.valid),
    .hazard_stall   (dut.hazard_stall),
    .id_ex_q        (dut.id_ex_q),
    .forward_a      (dut.forward_a),
    .forward_b      (dut.forward_b),
    .ex_branch_taken(dut.ex_branch_taken)
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

  // ---- Program, built with a running index + saved labels ----
  logic [31:0] prog [0:127];
  int k;
  int lbl_loop, lbl_double_fn, jal_idx;
  int n_instr;

  initial begin
    k = 0;

    // -- sum loop: BLT taken x3, not-taken x1 on exit --
    prog[k] = enc_i(12'd0, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); k++; // sum=0
    prog[k] = enc_i(12'd1, 5'd0, 3'b000, 5'd2, OPC_OP_IMM); k++; // i=1
    prog[k] = enc_i(12'd4, 5'd0, 3'b000, 5'd3, OPC_OP_IMM); k++; // limit=4
    lbl_loop = k;
    prog[k] = enc_r(7'b0, 5'd2, 5'd1, 3'b000, 5'd1, OPC_OP); k++; // sum+=i
    prog[k] = enc_i(12'd1, 5'd2, 3'b000, 5'd2, OPC_OP_IMM); k++;  // i+=1
    prog[k] = enc_b((lbl_loop - k) * 4, 5'd3, 5'd2, 3'b100, OPC_BRANCH); k++; // BLT i,limit,LOOP

    // -- memory round trips: word/byte/half store+load, LUI, AUIPC --
    prog[k] = enc_i(12'd0, 5'd0, 3'b000, 5'd4, OPC_OP_IMM); k++; // dmem base=0
    prog[k] = enc_s(12'd0, 5'd1, 5'd4, 3'b010, OPC_STORE); k++;  // SW sum,0(x4)
    prog[k] = enc_i(12'd0, 5'd4, 3'b010, 5'd5, OPC_LOAD); k++;   // LW x5,0(x4)
    prog[k] = enc_i(12'd170, 5'd0, 3'b000, 5'd9, OPC_OP_IMM); k++;
    prog[k] = enc_s(12'd4, 5'd9, 5'd4, 3'b000, OPC_STORE); k++;  // SB
    prog[k] = enc_i(12'd4, 5'd4, 3'b000, 5'd10, OPC_LOAD); k++;  // LB
    prog[k] = enc_i(12'd4, 5'd4, 3'b100, 5'd11, OPC_LOAD); k++;  // LBU
    prog[k] = enc_u(20'd8, 5'd12, OPC_LUI); k++;                 // LUI
    prog[k] = enc_s(12'd8, 5'd12, 5'd4, 3'b001, OPC_STORE); k++; // SH
    prog[k] = enc_i(12'd8, 5'd4, 3'b001, 5'd13, OPC_LOAD); k++;  // LH
    prog[k] = enc_i(12'd8, 5'd4, 3'b101, 5'd14, OPC_LOAD); k++;  // LHU
    prog[k] = enc_u(20'd1, 5'd15, OPC_AUIPC); k++;               // AUIPC

    // -- JAL/JALR subroutine call (target patched in after we know it) --
    prog[k] = enc_i(12'd21, 5'd0, 3'b000, 5'd6, OPC_OP_IMM); k++; // arg
    jal_idx = k; k++; // reserved, patched below once lbl_double_fn is known
    prog[k] = enc_i(12'd777, 5'd0, 3'b000, 5'd17, OPC_OP_IMM); k++; // return marker

    // -- load-use hazard stall: LW immediately consumed --
    prog[k] = enc_i(12'd0, 5'd4, 3'b010, 5'd22, OPC_LOAD); k++;   // LW x22,0(x4)
    prog[k] = enc_i(12'd1, 5'd22, 3'b000, 5'd21, OPC_OP_IMM); k++; // ADDI x21,x22,1 -> stall

    // -- forwarding, forced EX/MEM (0-instruction gap) on both operands --
    prog[k] = enc_i(12'd5, 5'd0, 3'b000, 5'd30, OPC_OP_IMM); k++; // producer
    prog[k] = enc_i(12'd1, 5'd30, 3'b000, 5'd29, OPC_OP_IMM); k++; // rs1 <- forward_a EX/MEM
    prog[k] = enc_i(12'd7, 5'd0, 3'b000, 5'd28, OPC_OP_IMM); k++; // producer
    prog[k] = enc_r(7'b0, 5'd28, 5'd0, 3'b000, 5'd27, OPC_OP); k++; // rs2 <- forward_b EX/MEM

    // -- forwarding, forced MEM/WB (1-instruction gap) on both operands --
    prog[k] = enc_i(12'd9, 5'd0, 3'b000, 5'd26, OPC_OP_IMM); k++;  // producer
    prog[k] = enc_i(12'd0, 5'd0, 3'b000, 5'd0, OPC_OP_IMM); k++;   // filler (also x0-as-rd)
    prog[k] = enc_i(12'd1, 5'd26, 3'b000, 5'd25, OPC_OP_IMM); k++; // rs1 <- forward_a MEM/WB
    prog[k] = enc_i(12'd11, 5'd0, 3'b000, 5'd24, OPC_OP_IMM); k++; // producer
    prog[k] = enc_i(12'd0, 5'd0, 3'b000, 5'd0, OPC_OP_IMM); k++;   // filler
    prog[k] = enc_r(7'b0, 5'd24, 5'd0, 3'b000, 5'd23, OPC_OP); k++; // rs2 <- forward_b MEM/WB

    // -- x0 explicitly as rs2 --
    prog[k] = enc_i(12'd4, 5'd0, 3'b000, 5'd18, OPC_OP_IMM); k++;
    prog[k] = enc_r(7'b0, 5'd0, 5'd18, 3'b000, 5'd19, OPC_OP); k++; // rs2=x0

    // -- R-type ALU bank: AND/OR/XOR/SLL/SRL/SRA --
    prog[k] = enc_i(12'd12, 5'd0, 3'b000, 5'd20, OPC_OP_IMM); k++;
    prog[k] = enc_i(12'd3,  5'd0, 3'b000, 5'd21, OPC_OP_IMM); k++;
    prog[k] = enc_r(7'b0,       5'd21, 5'd20, 3'b111, 5'd8,  OPC_OP); k++; // AND
    prog[k] = enc_r(7'b0,       5'd21, 5'd20, 3'b110, 5'd16, OPC_OP); k++; // OR
    prog[k] = enc_r(7'b0,       5'd21, 5'd20, 3'b100, 5'd17, OPC_OP); k++; // XOR
    prog[k] = enc_r(7'b0,       5'd21, 5'd20, 3'b001, 5'd19, OPC_OP); k++; // SLL
    prog[k] = enc_r(7'b0,       5'd21, 5'd20, 3'b101, 5'd2,  OPC_OP); k++; // SRL
    prog[k] = enc_r(7'b0100000, 5'd21, 5'd20, 3'b101, 5'd3,  OPC_OP); k++; // SRA

    // -- branch bank: BEQ/BNE/BGE/BLTU/BGEU each taken + not-taken
    // (BLT already closed both ways by the loop above) --
    prog[k] = enc_i(12'd5, 5'd0, 3'b000, 5'd20, OPC_OP_IMM); k++;
    prog[k] = enc_i(12'd5, 5'd0, 3'b000, 5'd21, OPC_OP_IMM); k++;
    prog[k] = enc_b(13'sd8, 5'd21, 5'd20, 3'b000, OPC_BRANCH); k++; // BEQ taken
    prog[k] = enc_i(12'd999, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); k++; // squashed
    prog[k] = enc_i(12'd111, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); k++;

    prog[k] = enc_i(12'd5, 5'd0, 3'b000, 5'd20, OPC_OP_IMM); k++;
    prog[k] = enc_i(12'd9, 5'd0, 3'b000, 5'd21, OPC_OP_IMM); k++;
    prog[k] = enc_b(13'sd8, 5'd21, 5'd20, 3'b001, OPC_BRANCH); k++; // BNE taken
    prog[k] = enc_i(12'd999, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); k++;
    prog[k] = enc_i(12'd222, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); k++;

    prog[k] = enc_i(-12'sd5, 5'd0, 3'b000, 5'd20, OPC_OP_IMM); k++;
    prog[k] = enc_i(-12'sd5, 5'd0, 3'b000, 5'd21, OPC_OP_IMM); k++;
    prog[k] = enc_b(13'sd8, 5'd21, 5'd20, 3'b101, OPC_BRANCH); k++; // BGE taken (-5>=-5)
    prog[k] = enc_i(12'd999, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); k++;
    prog[k] = enc_i(12'd333, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); k++;

    prog[k] = enc_i(12'd3, 5'd0, 3'b000, 5'd20, OPC_OP_IMM); k++;
    prog[k] = enc_i(-12'sd1, 5'd0, 3'b000, 5'd21, OPC_OP_IMM); k++; // 0xFFFFFFFF unsigned
    prog[k] = enc_b(13'sd8, 5'd21, 5'd20, 3'b110, OPC_BRANCH); k++; // BLTU taken
    prog[k] = enc_i(12'd999, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); k++;
    prog[k] = enc_i(12'd444, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); k++;

    prog[k] = enc_i(-12'sd1, 5'd0, 3'b000, 5'd20, OPC_OP_IMM); k++; // 0xFFFFFFFF unsigned
    prog[k] = enc_i(12'd3, 5'd0, 3'b000, 5'd21, OPC_OP_IMM); k++;
    prog[k] = enc_b(13'sd8, 5'd21, 5'd20, 3'b111, OPC_BRANCH); k++; // BGEU taken
    prog[k] = enc_i(12'd999, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); k++;
    prog[k] = enc_i(12'd555, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); k++;

    prog[k] = enc_i(12'd1, 5'd0, 3'b000, 5'd20, OPC_OP_IMM); k++;
    prog[k] = enc_i(12'd2, 5'd0, 3'b000, 5'd21, OPC_OP_IMM); k++;
    prog[k] = enc_b(13'sd8, 5'd21, 5'd20, 3'b000, OPC_BRANCH); k++; // BEQ NOT taken
    prog[k] = enc_i(12'd666, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); k++; // fallthrough

    prog[k] = enc_i(12'd5, 5'd0, 3'b000, 5'd20, OPC_OP_IMM); k++;
    prog[k] = enc_i(12'd5, 5'd0, 3'b000, 5'd21, OPC_OP_IMM); k++;
    prog[k] = enc_b(13'sd8, 5'd21, 5'd20, 3'b001, OPC_BRANCH); k++; // BNE NOT taken
    prog[k] = enc_i(12'd777, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); k++; // fallthrough

    prog[k] = enc_i(-12'sd5, 5'd0, 3'b000, 5'd20, OPC_OP_IMM); k++;
    prog[k] = enc_i(12'd3, 5'd0, 3'b000, 5'd21, OPC_OP_IMM); k++;
    prog[k] = enc_b(13'sd8, 5'd21, 5'd20, 3'b101, OPC_BRANCH); k++; // BGE NOT taken (-5<3)
    prog[k] = enc_i(12'd888, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); k++; // fallthrough

    prog[k] = enc_i(12'd9, 5'd0, 3'b000, 5'd20, OPC_OP_IMM); k++;
    prog[k] = enc_i(12'd3, 5'd0, 3'b000, 5'd21, OPC_OP_IMM); k++;
    prog[k] = enc_b(13'sd8, 5'd21, 5'd20, 3'b110, OPC_BRANCH); k++; // BLTU NOT taken (9 !<u 3)
    prog[k] = enc_i(12'd111, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); k++; // fallthrough

    prog[k] = enc_i(12'd3, 5'd0, 3'b000, 5'd20, OPC_OP_IMM); k++;
    prog[k] = enc_i(12'd9, 5'd0, 3'b000, 5'd21, OPC_OP_IMM); k++;
    prog[k] = enc_b(13'sd8, 5'd21, 5'd20, 3'b111, OPC_BRANCH); k++; // BGEU NOT taken (3 !>=u 9)
    prog[k] = enc_i(12'd222, 5'd0, 3'b000, 5'd22, OPC_OP_IMM); k++; // fallthrough

    prog[k] = halt(); k++;

    // -- subroutine: dead code from sequential flow, reached only via JAL --
    lbl_double_fn = k;
    prog[k] = enc_i(12'd1, 5'd6, 3'b001, 5'd7, OPC_OP_IMM); k++;   // SLLI x7,x6,1
    prog[k] = enc_i(12'd0, 5'd31, 3'b000, 5'd0, OPC_JALR); k++;    // return via x31

    prog[jal_idx] = enc_j((lbl_double_fn - jal_idx) * 4, 5'd31, OPC_JAL);

    n_instr = k;
  end

  // ---- run for a fixed, generous cycle budget then stop ----
  localparam int MAX_CYCLES = 600;

  task automatic run_program();
    int i;
    for (i = 0; i < n_instr; i++) dut.imem_inst.mem[i] = prog[i];
    rst_n = 1'b0;
    @(posedge clk);
    #1;
    rst_n = 1'b1;
    repeat (MAX_CYCLES) @(posedge clk);
  endtask

  initial begin
    $display("---- coverage testbench start (%0d-instruction stimulus) ----", n_instr);
    clk   = 1'b0;
    rst_n = 1'b1;
    #1; // let the initial block above finish building prog[]/n_instr first
    run_program();
    $display("---- coverage testbench done (%0d cycles) ----", MAX_CYCLES);
    cov_inst.print_report();
    $finish;
  end

endmodule : tb_coverage
