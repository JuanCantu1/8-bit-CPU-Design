// alu.sv
// Combinational 32-bit ALU covering the RV32I base operations.

module alu
  import riscv_pkg::*;
(
  input  logic [XLEN-1:0] operand_a,
  input  logic [XLEN-1:0] operand_b,
  input  alu_op_e         alu_op,
  output logic [XLEN-1:0] result,
  output logic            zero
);

  always_comb begin
    case (alu_op)
      ALU_ADD  : result = operand_a + operand_b;
      ALU_SUB  : result = operand_a - operand_b;
      ALU_AND  : result = operand_a & operand_b;
      ALU_OR   : result = operand_a | operand_b;
      ALU_XOR  : result = operand_a ^ operand_b;
      ALU_SLL  : result = operand_a << operand_b[4:0];
      ALU_SRL  : result = operand_a >> operand_b[4:0];
      ALU_SRA  : result = $signed(operand_a) >>> operand_b[4:0];
      ALU_SLT  : result = ($signed(operand_a) < $signed(operand_b)) ? 32'd1 : 32'd0;
      ALU_SLTU : result = (operand_a < operand_b) ? 32'd1 : 32'd0;
      default  : result = '0;
    endcase
  end

  assign zero = (result == '0);

endmodule : alu