// ex_mem_reg.sv
// EX/MEM pipeline register. No stall/flush inputs: once an instruction
// reaches EX it always proceeds — stalling only ever holds back
// instructions still in IF/ID, and flushing only ever discards
// instructions still in IF/ID or ID/EX.

module ex_mem_reg
  import riscv_pkg::*;
(
  input  logic    clk,
  input  logic    rst_n,
  input  ex_mem_t d_in,
  output ex_mem_t q_out
);

  always_ff @(posedge clk) begin
    if (!rst_n) q_out <= '0;
    else        q_out <= d_in;
  end

endmodule : ex_mem_reg
