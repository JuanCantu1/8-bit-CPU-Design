// riscv_core_singlecycle.sv
// Single-cycle RV32I datapath: the correctness baseline before pipelining.
// Wires together pc_reg, imem, decoder, control_unit, regfile, alu, dmem.
//
// Branch targets need a second adder alongside the main ALU: for BRANCH
// instructions the ALU is busy computing the comparison (rs1 op rs2), so
// PC+imm is computed separately here. JAL/JALR/AUIPC don't have this
// conflict — control_unit already points alu_src_a/alu_src_b at
// (PC,imm) or (rs1,imm) for those, so the main ALU's result IS the
// jump target / AUIPC value directly.

module riscv_core_singlecycle
  import riscv_pkg::*;
(
  input logic clk,
  input logic rst_n
);

  // ---- Fetch ----
  logic [XLEN-1:0] pc, pc_next, pc_plus4, branch_target, jump_target;
  logic [XLEN-1:0] instr;

  pc_reg pc_reg_inst (
    .clk     (clk),
    .rst_n   (rst_n),
    .pc_next (pc_next),
    .pc      (pc)
  );

  assign pc_plus4 = pc + 32'd4;

  imem imem_inst (
    .addr  (pc),
    .instr (instr)
  );

  // ---- Decode ----
  logic [6:0]      opcode;
  logic [4:0]      rd, rs1, rs2;
  logic [2:0]      funct3;
  logic            funct7b5;
  logic [XLEN-1:0] imm_ext;
  imm_src_e        imm_src;

  decoder decoder_inst (
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

  // ---- Control ----
  logic        reg_write, mem_read, mem_write, branch, jump;
  result_src_e result_src;
  alu_src_a_e  alu_src_a;
  alu_src_b_e  alu_src_b;
  alu_op_e     alu_op;

  control_unit control_unit_inst (
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

  // ---- Register file ----
  logic [XLEN-1:0] rs1_data, rs2_data, result;

  regfile regfile_inst (
    .clk      (clk),
    .rs1_addr (rs1),
    .rs2_addr (rs2),
    .rd_addr  (rd),
    .rd_data  (result),
    .we       (reg_write),
    .rs1_data (rs1_data),
    .rs2_data (rs2_data)
  );

  // ---- ALU operand selection ----
  logic [XLEN-1:0] alu_operand_a, alu_operand_b, alu_result;
  logic            alu_zero;

  always_comb begin
    case (alu_src_a)
      SRCA_RS1:  alu_operand_a = rs1_data;
      SRCA_PC:   alu_operand_a = pc;
      SRCA_ZERO: alu_operand_a = '0;
      default:   alu_operand_a = rs1_data;
    endcase
  end

  assign alu_operand_b = (alu_src_b == SRCB_IMM) ? imm_ext : rs2_data;

  alu alu_inst (
    .operand_a (alu_operand_a),
    .operand_b (alu_operand_b),
    .alu_op    (alu_op),
    .result    (alu_result),
    .zero      (alu_zero)
  );

  // ---- Data memory ----
  logic [XLEN-1:0] mem_read_data;

  dmem dmem_inst (
    .clk        (clk),
    .addr       (alu_result),
    .write_data (rs2_data),
    .mem_write  (mem_write),
    .funct3     (funct3),
    .read_data  (mem_read_data)
  );

  // ---- Branch/jump resolution ----
  logic branch_taken;

  always_comb begin
    case (funct3)
      3'b000:  branch_taken = alu_zero;       // BEQ
      3'b001:  branch_taken = ~alu_zero;      // BNE
      3'b100:  branch_taken = alu_result[0];  // BLT  (ALU ran SLT)
      3'b101:  branch_taken = ~alu_result[0]; // BGE
      3'b110:  branch_taken = alu_result[0];  // BLTU (ALU ran SLTU)
      3'b111:  branch_taken = ~alu_result[0]; // BGEU
      default: branch_taken = 1'b0;
    endcase
  end

  assign branch_target = pc + imm_ext;
  assign jump_target   = {alu_result[31:1], 1'b0}; // clears LSB per JALR spec

  always_comb begin
    if (jump)                        pc_next = jump_target;
    else if (branch && branch_taken) pc_next = branch_target;
    else                              pc_next = pc_plus4;
  end

  // ---- Writeback mux ----
  always_comb begin
    case (result_src)
      RESULT_ALU: result = alu_result;
      RESULT_MEM: result = mem_read_data;
      RESULT_PC4: result = pc_plus4;
      default:    result = alu_result;
    endcase
  end

endmodule : riscv_core_singlecycle
