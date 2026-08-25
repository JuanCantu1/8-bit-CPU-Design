// mem_wb_reg.sv
// MEM/WB pipeline register. Always passes through, same reasoning as
// ex_mem_reg.

module mem_wb_reg
  import riscv_pkg::*;
(
  input  logic    clk,
  input  logic    rst_n,
  input  mem_wb_t d_in,
  output mem_wb_t q_out
);

  always_ff @(posedge clk) begin
    if (!rst_n) q_out <= '0;
    else        q_out <= d_in;
  end

endmodule : mem_wb_reg
