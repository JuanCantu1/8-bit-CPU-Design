// imem.sv
// Instruction memory. Word-addressed, combinational read. Simulation-only:
// contents are poked directly into `mem` from the testbench via a
// hierarchical reference — no synthesis-time initialization here.

module imem
  import riscv_pkg::*;
#(
  parameter int DEPTH_WORDS = 256
) (
  input  logic [XLEN-1:0] addr,
  output logic [XLEN-1:0] instr
);

  logic [XLEN-1:0] mem [0:DEPTH_WORDS-1];

  assign instr = mem[addr[XLEN-1:2]];

endmodule : imem
