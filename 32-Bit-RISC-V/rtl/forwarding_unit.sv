// forwarding_unit.sv
// EX-stage forwarding select for the ALU operands. Compares the
// EX-stage instruction's rs1/rs2 against the destinations of the
// instructions currently in MEM and WB, preferring EX/MEM (the more
// recent producer) over MEM/WB when both match the same register.
//
// This only ever needs to supply ex_mem_q.alu_result (never
// mem_read_data or pc_plus4) for the EX/MEM source: a load producer at
// this exact alignment is always caught first by hazard_unit's 1-cycle
// stall (so its un-read memory data is never the thing being forwarded
// here), and a jump producer's link register is always at least 2 stages
// retired from any dependent instruction by the time it could reach this
// alignment, because resolving jumps in EX flushes the 2 instructions
// fetched behind it — see design-notes.md for the full timing trace.

module forwarding_unit
  import riscv_pkg::*;
(
  input  logic [4:0] rs1_ex,
  input  logic [4:0] rs2_ex,
  input  logic       reg_write_mem,
  input  logic [4:0] rd_mem,
  input  logic       reg_write_wb,
  input  logic [4:0] rd_wb,
  output fwd_sel_e   forward_a,
  output fwd_sel_e   forward_b
);

  always_comb begin
    if (reg_write_mem && (rd_mem != 5'd0) && (rd_mem == rs1_ex))
      forward_a = FWD_EX_MEM;
    else if (reg_write_wb && (rd_wb != 5'd0) && (rd_wb == rs1_ex))
      forward_a = FWD_MEM_WB;
    else
      forward_a = FWD_NONE;
  end

  always_comb begin
    if (reg_write_mem && (rd_mem != 5'd0) && (rd_mem == rs2_ex))
      forward_b = FWD_EX_MEM;
    else if (reg_write_wb && (rd_wb != 5'd0) && (rd_wb == rs2_ex))
      forward_b = FWD_MEM_WB;
    else
      forward_b = FWD_NONE;
  end

endmodule : forwarding_unit
