// decoder.sv
// Instruction decoder. Bit-slices the 32-bit instruction word into the
// fields the control unit and register file need, and sign-extends the
// immediate per the format selected by imm_src (driven by the control
// unit, which derives it from opcode).

module decoder
  import riscv_pkg::*;
(
  input  logic [31:0]     instr,
  input  imm_src_e        imm_src,

  output logic [6:0]      opcode,
  output logic [4:0]      rd,
  output logic [2:0]      funct3,
  output logic [4:0]      rs1,
  output logic [4:0]      rs2,
  output logic            funct7b5,
  output logic [XLEN-1:0] imm_ext
);

  assign opcode   = instr[6:0];
  assign rd       = instr[11:7];
  assign funct3   = instr[14:12];
  assign rs1      = instr[19:15];
  assign rs2      = instr[24:20];
  assign funct7b5 = instr[30];

  always_comb begin
    case (imm_src)
      IMM_I:   imm_ext = {{20{instr[31]}}, instr[31:20]};
      IMM_S:   imm_ext = {{20{instr[31]}}, instr[31:25], instr[11:7]};
      IMM_B:   imm_ext = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
      IMM_U:   imm_ext = {instr[31:12], 12'b0};
      IMM_J:   imm_ext = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
      default: imm_ext = {{20{instr[31]}}, instr[31:20]};
    endcase
  end

endmodule : decoder