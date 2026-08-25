// tb_decoder.sv
// Directed self-checking testbench for the instruction decoder. Run via
// sim/run_decoder.ps1
//
// Each instruction word is hand-assembled from its fields per the RV32I
// spec encoding (not derived from decoder.sv's own slicing formula), so
// this is an independent check of the sign-extension and bit-field math.

`timescale 1ns / 1ps

module tb_decoder;
  import riscv_pkg::*;

  logic [31:0] instr;
  imm_src_e    imm_src;

  logic [6:0]      opcode;
  logic [4:0]      rd;
  logic [2:0]      funct3;
  logic [4:0]      rs1;
  logic [4:0]      rs2;
  logic            funct7b5;
  logic [XLEN-1:0] imm_ext;

  int pass_count = 0;
  int fail_count = 0;

  decoder dut (
    .instr    (instr),
    .imm_src  (imm_src),
    .opcode   (opcode),
    .rd       (rd),
    .funct3   (funct3),
    .rs1      (rs1),
    .rs2      (rs2),
    .funct7b5 (funct7b5),
    .imm_ext  (imm_ext)
  );

  task automatic check(
    input logic [31:0]     in_instr,
    input imm_src_e        in_imm_src,
    input logic [6:0]      exp_opcode,
    input logic [4:0]      exp_rd,
    input logic [2:0]      exp_funct3,
    input logic [4:0]      exp_rs1,
    input logic [4:0]      exp_rs2,
    input logic            exp_funct7b5,
    input logic [XLEN-1:0] exp_imm_ext,
    input string           test_name
  );
    instr   = in_instr;
    imm_src = in_imm_src;
    #1;
    if (opcode === exp_opcode && rd === exp_rd && funct3 === exp_funct3 &&
        rs1 === exp_rs1 && rs2 === exp_rs2 && funct7b5 === exp_funct7b5 &&
        imm_ext === exp_imm_ext) begin
      pass_count++;
      $display("PASS: %-24s imm_ext=%0d (0x%h)", test_name, $signed(imm_ext), imm_ext);
    end else begin
      fail_count++;
      $display("FAIL: %-24s opcode=%h(exp %h) rd=%0d(exp %0d) funct3=%0d(exp %0d) rs1=%0d(exp %0d) rs2=%0d(exp %0d) funct7b5=%0b(exp %0b) imm_ext=%0d(exp %0d)",
                test_name, opcode, exp_opcode, rd, exp_rd, funct3, exp_funct3,
                rs1, exp_rs1, rs2, exp_rs2, funct7b5, exp_funct7b5,
                $signed(imm_ext), $signed(exp_imm_ext));
    end
  endtask

  initial begin
    $display("---- decoder testbench start ----");

    // R-type: ADD x3, x1, x2 (funct7=0000000 -> funct7b5=0).
    // instr[31:20] happens to read as {funct7,rs2} = 12'h002 when treated
    // as an I-immediate; decoder always computes it regardless of format.
    check({7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, OPC_OP}, IMM_I,
          OPC_OP, 5'd3, 3'b000, 5'd1, 5'd2, 1'b0, 32'sd2, "R-type ADD");

    // R-type: SUB x6, x4, x5 (funct7=0100000 -> funct7b5=1).
    // {funct7,rs2} read as an I-immediate = 0100000_00101 = 1029.
    check({7'b0100000, 5'd5, 5'd4, 3'b000, 5'd6, OPC_OP}, IMM_I,
          OPC_OP, 5'd6, 3'b000, 5'd4, 5'd5, 1'b1, 32'sd1029, "R-type SUB");

    // I-type: ADDI x5, x1, 100. Decoder always slices instr[24:20] as
    // "rs2" too, which here is just imm[4:0] = 4 (not a real register).
    check({12'd100, 5'd1, 3'b000, 5'd5, OPC_OP_IMM}, IMM_I,
          OPC_OP_IMM, 5'd5, 3'b000, 5'd1, 5'd4, 1'b0, 32'sd100, "I-type positive imm");

    // I-type: ADDI x5, x1, -5 (12-bit two's complement of -5 = 0xFFB).
    // "rs2" slice = imm[4:0] = 27.
    check({12'hFFB, 5'd1, 3'b000, 5'd5, OPC_OP_IMM}, IMM_I,
          OPC_OP_IMM, 5'd5, 3'b000, 5'd1, 5'd27, 1'b1, -32'sd5, "I-type negative imm");

    // S-type: SW x2, 40(x1). imm=40 -> imm[11:5]=0000001, imm[4:0]=01000.
    check({7'b0000001, 5'd2, 5'd1, 3'b010, 5'b01000, OPC_STORE}, IMM_S,
          OPC_STORE, 5'b01000, 3'b010, 5'd1, 5'd2, 1'b0, 32'sd40, "S-type positive imm");

    // S-type: SW x2, -40(x1). imm=-40 -> imm[11:5]=1111110, imm[4:0]=11000.
    check({7'b1111110, 5'd2, 5'd1, 3'b010, 5'b11000, OPC_STORE}, IMM_S,
          OPC_STORE, 5'b11000, 3'b010, 5'd1, 5'd2, 1'b1, -32'sd40, "S-type negative imm");

    // B-type: BEQ x1, x2, +16. imm=16 (13-bit: sign=0,imm[10:5]=0,imm[4:1]=1000,imm[0]=0).
    // B-type has no rd field; instr[11:7] slices as {imm[4:1],imm[11]} = 16.
    check({1'b0, 6'b000000, 5'd2, 5'd1, 3'b000, 4'b1000, 1'b0, OPC_BRANCH}, IMM_B,
          OPC_BRANCH, 5'd16, 3'b000, 5'd1, 5'd2, 1'b0, 32'sd16, "B-type positive imm");

    // B-type: BNE x3, x4, -16 (13-bit: sign=1,imm[10:5]=111111,imm[4:1]=1000,imm[0]=0).
    // "rd" slice = {imm[4:1],imm[11]} = {1000,1} = 17.
    check({1'b1, 6'b111111, 5'd4, 5'd3, 3'b001, 4'b1000, 1'b1, OPC_BRANCH}, IMM_B,
          OPC_BRANCH, 5'd17, 3'b001, 5'd3, 5'd4, 1'b1, -32'sd16, "B-type negative imm");

    // U-type: LUI x5, 0x12345. U-type has no funct3/rs1/rs2; those slots
    // fall inside the 20-bit immediate field, so they read as sub-slices
    // of 0x12345 rather than 0: funct3=imm[2:0]=5, rs1=imm[7:3]=8,
    // rs2=imm[12:8]=3.
    check({20'h12345, 5'd5, OPC_LUI}, IMM_U,
          OPC_LUI, 5'd5, 3'b101, 5'd8, 5'd3, 1'b0, 32'h12345000, "U-type imm");

    // J-type: JAL x1, +1024 (21-bit: sign=0,imm[19:12]=0,imm[11]=0,imm[10:1]=1000000000).
    // J-type has no funct3/rs1/rs2 either; here they happen to read as 0
    // because the chosen offset's imm[19:12] and imm[4:1]/imm[11] bits
    // are all zero.
    check({1'b0, 10'b1000000000, 1'b0, 8'b00000000, 5'd1, OPC_JAL}, IMM_J,
          OPC_JAL, 5'd1, 3'b000, 5'd0, 5'd0, 1'b1, 32'sd1024, "J-type positive imm");

    // J-type: JAL x2, -1024 (21-bit: sign=1,imm[19:12]=all1,imm[11]=1,imm[10:1]=1000000000).
    // funct3=imm[19:12][2:0]=7, rs1=imm[19:12][7:3]=31,
    // rs2={imm[4:1],imm[11]}={0000,1}=1.
    check({1'b1, 10'b1000000000, 1'b1, 8'b11111111, 5'd2, OPC_JAL}, IMM_J,
          OPC_JAL, 5'd2, 3'b111, 5'd31, 5'd1, 1'b1, -32'sd1024, "J-type negative imm");

    $display("---- decoder testbench done: %0d passed, %0d failed ----", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else $display("SOME TESTS FAILED");

    $finish;
  end

endmodule : tb_decoder