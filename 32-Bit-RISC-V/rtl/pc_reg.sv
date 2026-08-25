// pc_reg.sv
// Program counter register. Synchronous active-low reset to address 0 —
// the only state element in the core that resets; regfile/memories don't,
// matching real hardware (only the boot address needs a defined value).

module pc_reg
  import riscv_pkg::*;
(
  input  logic            clk,
  input  logic            rst_n,
  input  logic [XLEN-1:0] pc_next,
  output logic [XLEN-1:0] pc
);

  always_ff @(posedge clk) begin
    if (!rst_n) pc <= '0;
    else        pc <= pc_next;
  end

endmodule : pc_reg
