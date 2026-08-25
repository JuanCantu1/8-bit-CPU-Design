// regfile.sv
// 32 x 32-bit register file. x0 hardwired to zero. 2 combinational read
// ports, 1 synchronous write port.

module regfile
  import riscv_pkg::*;
(
  input  logic            clk,
  input  logic [4:0]      rs1_addr,
  input  logic [4:0]      rs2_addr,
  input  logic [4:0]      rd_addr,
  input  logic [XLEN-1:0] rd_data,
  input  logic            we,
  output logic [XLEN-1:0] rs1_data,
  output logic [XLEN-1:0] rs2_data
);

  logic [XLEN-1:0] regs [32];

  always_ff @(posedge clk) begin
    if (we && rd_addr != 5'd0) regs[rd_addr] <= rd_data;
  end

  assign rs1_data = (rs1_addr == 5'd0) ? '0 : regs[rs1_addr];
  assign rs2_data = (rs2_addr == 5'd0) ? '0 : regs[rs2_addr];

  // ---- Assertions (immediate — see design-notes.md "Assertions": this
  // Icarus build silently no-ops `assert property`/concurrent
  // assertions, so these are procedural checks instead) ----
  //
  // x0 must always read as zero. Note this checks the READ MUX's output,
  // independently of the ternary that implements it below — it exists to
  // catch a regression if that mux logic is ever changed, not to prove
  // anything about the mux as written today. Checked synchronously
  // (always_ff, not always @(*)) on purpose: an always @(*) block
  // re-triggers on every glitch of rs1_addr/rs1_data individually, and
  // since rs1_data is combinationally DERIVED from rs1_addr by a
  // separate `assign`, Icarus doesn't guarantee this block re-evaluates
  // AFTER that assign settles — caught this the hard way as false
  // positives reading a stale rs1_data against a just-changed rs1_addr.
  // Checking only at the clock edge, once combinational logic has fully
  // settled, avoids that race.
  //
  // Also skips whenever rs1_addr/rs2_addr is X: this module has no reset
  // (only the boot address needs a defined value, per the project's
  // no-reset convention — see design-notes.md), and callers with their
  // own pipeline registers can briefly present an X address around each
  // of THEIR resets (a testbench that calls run_program() several times
  // resets several times, not just once, so a one-shot "skip the first
  // edge" guard isn't enough — caught this the hard way too). When the
  // address itself is unknown, the assertion's own precondition ("this
  // is specifically an x0 read") can't be established, so skipping is
  // correct, not just noise suppression.
  always_ff @(posedge clk) begin
    if (!$isunknown(rs1_addr))
      assert (rs1_addr != 5'd0 || rs1_data === '0)
        else $error("x0 read via rs1 returned non-zero: 0x%h", rs1_data);
    if (!$isunknown(rs2_addr))
      assert (rs2_addr != 5'd0 || rs2_data === '0)
        else $error("x0 read via rs2 returned non-zero: 0x%h", rs2_data);
  end

  // x0's underlying storage must never actually change, even though a
  // write targeting it is a legal (if architecturally no-op) request —
  // e.g. "addi x0, x1, 5" is valid RV32I and does assert we with
  // rd_addr==0, so the invariant isn't "this is never requested," it's
  // "the write guard above always successfully ignores it." Checked one
  // cycle delayed (Icarus has no working $past()/|=> here) by recording
  // whether an x0 write was attempted and what regs[0] held right
  // before it, then confirming regs[0] is unchanged the cycle after.
  logic            x0_write_attempted_prev;
  logic [XLEN-1:0] regs0_before_prev;

  always_ff @(posedge clk) begin
    if (x0_write_attempted_prev)
      assert (regs[0] === regs0_before_prev)
        else $error("x0 storage changed despite write guard: was=0x%h now=0x%h",
                     regs0_before_prev, regs[0]);

    x0_write_attempted_prev <= (we && rd_addr == 5'd0);
    regs0_before_prev       <= regs[0];
  end

endmodule : regfile