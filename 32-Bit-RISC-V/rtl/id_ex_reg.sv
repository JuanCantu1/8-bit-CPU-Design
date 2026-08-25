// id_ex_reg.sv
// ID/EX pipeline register. Unlike IF/ID, a stall here injects a bubble
// (not a hold) — the instruction causing the hazard stays parked in
// IF/ID for another attempt, while EX gets a NOP instead of an
// incompletely-ready instruction. A flush also clears to a bubble.

module id_ex_reg
  import riscv_pkg::*;
(
  input  logic   clk,
  input  logic   rst_n,
  input  logic   stall,
  input  logic   flush,
  input  id_ex_t d_in,
  output id_ex_t q_out
);

  always_ff @(posedge clk) begin
    if (!rst_n || flush || stall) q_out <= '0;
    else                          q_out <= d_in;
  end

endmodule : id_ex_reg
