// if_id_reg.sv
// IF/ID pipeline register. On a stall it HOLDS its current value (the
// fetched-but-not-yet-issued instruction is retried next cycle); on a
// flush it clears to a bubble, taking priority over a stall since a
// flushed instruction's own stall request is moot.

module if_id_reg
  import riscv_pkg::*;
(
  input  logic   clk,
  input  logic   rst_n,
  input  logic   stall,
  input  logic   flush,
  input  if_id_t d_in,
  output if_id_t q_out
);

  always_ff @(posedge clk) begin
    if (!rst_n || flush) q_out <= '0;
    else if (!stall)     q_out <= d_in;
  end

endmodule : if_id_reg
