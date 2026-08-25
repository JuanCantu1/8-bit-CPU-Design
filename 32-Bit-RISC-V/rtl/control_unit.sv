// control_unit.sv
// Combinational main control unit. Maps opcode/funct3/funct7[5] to the
// control signals the rest of the datapath needs. Scope: core RV32I
// (R/I/S/B/U/J formats) — FENCE/ECALL/EBREAK are out of scope for now and
// fall through to the safe-default (no-op) case.

module control_unit
  import riscv_pkg::*;
(
  input  logic [6:0] opcode,
  input  logic [2:0] funct3,
  input  logic       funct7b5,

  output logic        reg_write,
  output logic        mem_read,
  output logic        mem_write,
  output logic        branch,
  output logic        jump,
  output result_src_e result_src,
  output alu_src_a_e  alu_src_a,
  output alu_src_b_e  alu_src_b,
  output imm_src_e    imm_src,
  output alu_op_e     alu_op
);

  always_comb begin
    // Safe defaults: no writes, no control transfer.
    reg_write  = 1'b0;
    mem_read   = 1'b0;
    mem_write  = 1'b0;
    branch     = 1'b0;
    jump       = 1'b0;
    result_src = RESULT_ALU;
    alu_src_a  = SRCA_RS1;
    alu_src_b  = SRCB_RS2;
    imm_src    = IMM_I;
    alu_op     = ALU_ADD;

    case (opcode)
      OPC_LUI: begin
        reg_write = 1'b1;
        alu_src_a = SRCA_ZERO;
        alu_src_b = SRCB_IMM;
        imm_src   = IMM_U;
        alu_op    = ALU_ADD;
      end

      OPC_AUIPC: begin
        reg_write = 1'b1;
        alu_src_a = SRCA_PC;
        alu_src_b = SRCB_IMM;
        imm_src   = IMM_U;
        alu_op    = ALU_ADD;
      end

      OPC_JAL: begin
        reg_write  = 1'b1;
        jump       = 1'b1;
        result_src = RESULT_PC4;
        alu_src_a  = SRCA_PC;
        alu_src_b  = SRCB_IMM;
        imm_src    = IMM_J;
        alu_op     = ALU_ADD;
      end

      OPC_JALR: begin
        reg_write  = 1'b1;
        jump       = 1'b1;
        result_src = RESULT_PC4;
        alu_src_a  = SRCA_RS1;
        alu_src_b  = SRCB_IMM;
        imm_src    = IMM_I;
        alu_op     = ALU_ADD;
      end

      OPC_BRANCH: begin
        branch    = 1'b1;
        alu_src_a = SRCA_RS1;
        alu_src_b = SRCB_RS2;
        imm_src   = IMM_B;
        case (funct3)
          3'b000, 3'b001: alu_op = ALU_SUB;   // BEQ, BNE
          3'b100, 3'b101: alu_op = ALU_SLT;   // BLT, BGE
          3'b110, 3'b111: alu_op = ALU_SLTU;  // BLTU, BGEU
          default:        alu_op = ALU_SUB;
        endcase
      end

      OPC_LOAD: begin
        reg_write  = 1'b1;
        mem_read   = 1'b1;
        result_src = RESULT_MEM;
        alu_src_a  = SRCA_RS1;
        alu_src_b  = SRCB_IMM;
        imm_src    = IMM_I;
        alu_op     = ALU_ADD;
      end

      OPC_STORE: begin
        mem_write = 1'b1;
        alu_src_a = SRCA_RS1;
        alu_src_b = SRCB_IMM;
        imm_src   = IMM_S;
        alu_op    = ALU_ADD;
      end

      OPC_OP_IMM: begin
        reg_write = 1'b1;
        alu_src_a = SRCA_RS1;
        alu_src_b = SRCB_IMM;
        imm_src   = IMM_I;
        case (funct3)
          3'b000:  alu_op = ALU_ADD;                      // ADDI
          3'b010:  alu_op = ALU_SLT;                       // SLTI
          3'b011:  alu_op = ALU_SLTU;                      // SLTIU
          3'b100:  alu_op = ALU_XOR;                       // XORI
          3'b110:  alu_op = ALU_OR;                        // ORI
          3'b111:  alu_op = ALU_AND;                       // ANDI
          3'b001:  alu_op = ALU_SLL;                       // SLLI
          3'b101:  if (funct7b5) alu_op = ALU_SRA; else alu_op = ALU_SRL; // SRAI / SRLI
          default: alu_op = ALU_ADD;
        endcase
      end

      OPC_OP: begin
        reg_write = 1'b1;
        alu_src_a = SRCA_RS1;
        alu_src_b = SRCB_RS2;
        case (funct3)
          3'b000:  if (funct7b5) alu_op = ALU_SUB; else alu_op = ALU_ADD;  // SUB / ADD
          3'b001:  alu_op = ALU_SLL;
          3'b010:  alu_op = ALU_SLT;
          3'b011:  alu_op = ALU_SLTU;
          3'b100:  alu_op = ALU_XOR;
          3'b101:  if (funct7b5) alu_op = ALU_SRA; else alu_op = ALU_SRL;  // SRA / SRL
          3'b110:  alu_op = ALU_OR;
          3'b111:  alu_op = ALU_AND;
          default: alu_op = ALU_ADD;
        endcase
      end

      default: ; // FENCE/ECALL/EBREAK/unrecognized — defaults above hold.
    endcase
  end

endmodule : control_unit