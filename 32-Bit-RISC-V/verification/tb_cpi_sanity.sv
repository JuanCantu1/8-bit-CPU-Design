// tb_cpi_sanity.sv
// CPI sanity check, NOT a throughput/speedup benchmark. See
// design-notes.md "Measured throughput" and "CPI sanity check" for why:
// dut_sc and dut_pipe share one clk in simulation, so a cycle-count
// comparison here can only ever measure CPI (cycles per instruction),
// never the clock-frequency advantage that "pipelining is 3-5x faster"
// is actually about — single-cycle's CPI is always exactly 1.0 by
// construction, the theoretical best possible, so the pipeline can only
// approach that same 1.0 from above in simulation, never beat it. What
// THIS test verifies instead: that forwarding actually keeps CPI close
// to 1.0 for an ordinary 0-gap ALU dependency chain (the load-bearing
// case for forwarding_unit's EX/MEM -> EX path), rather than silently
// regressing to something stall-heavy. Run via sim/run_cpi_sanity.ps1

`timescale 1ns / 1ps

module tb_cpi_sanity;
  import riscv_pkg::*;

  logic clk;
  logic rst_n;

  int pass_count = 0;
  int fail_count = 0;

  riscv_core_singlecycle dut_sc (
    .clk   (clk),
    .rst_n (rst_n)
  );

  riscv_core_pipelined dut_pipe (
    .clk   (clk),
    .rst_n (rst_n)
  );

  always #5 clk = ~clk;

  function automatic logic [31:0] enc_i(
    input logic [11:0] imm, input logic [4:0] rs1,
    input logic [2:0] funct3, input logic [4:0] rd, input logic [6:0] opcode);
    return {imm, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] enc_j(
    input logic [20:0] imm, input logic [4:0] rd, input logic [6:0] opcode);
    return {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
  endfunction

  function automatic logic [31:0] halt();
    return enc_j(21'sd0, 5'd0, OPC_JAL);
  endfunction

  // ---- Program: a 41-instruction 0-gap ADDI dependency chain (x1 += 1,
  // each instruction depending on the one immediately before it) — no
  // branches, no loads/stores, nothing but the exact case
  // EX/MEM -> EX forwarding exists to make free. ----
  localparam int N_REAL_INSTR = 41; // idx 0..40, x1: 0 -> 40
  localparam int N_INSTR = N_REAL_INSTR + 1; // + halt()
  logic [31:0] prog [0:N_INSTR-1];

  initial begin
    int i;
    prog[0] = enc_i(12'd0, 5'd0, 3'b000, 5'd1, OPC_OP_IMM); // x1 = 0
    for (i = 1; i < N_REAL_INSTR; i++)
      prog[i] = enc_i(12'd1, 5'd1, 3'b000, 5'd1, OPC_OP_IMM); // x1 += 1
    prog[N_REAL_INSTR] = halt();
  end

  // ---- Cycle counting + completion detection (same technique as
  // tb_full_program.sv: watch the last-written register) ----
  localparam int MAX_CYCLES = 100;
  localparam logic [31:0] EXPECTED_X1 = N_REAL_INSTR - 1; // 40

  int   sc_cycles, pipe_cycles;
  logic sc_done, pipe_done;

  always @(posedge clk) begin
    if (!rst_n) begin
      sc_cycles   <= 0;
      pipe_cycles <= 0;
    end else begin
      if (!sc_done)   sc_cycles   <= sc_cycles + 1;
      if (!pipe_done) pipe_cycles <= pipe_cycles + 1;
    end
  end

  always @(posedge clk) begin
    if (!sc_done && (dut_sc.regfile_inst.regs[1] === EXPECTED_X1))
      sc_done <= 1'b1;
    if (!pipe_done && (dut_pipe.regfile_inst.regs[1] === EXPECTED_X1))
      pipe_done <= 1'b1;
  end

  task automatic run_until_done();
    int i;
    for (i = 0; i < N_INSTR; i++) begin
      dut_sc.imem_inst.mem[i]   = prog[i];
      dut_pipe.imem_inst.mem[i] = prog[i];
    end
    rst_n = 1'b0;
    @(posedge clk);
    #1;
    rst_n = 1'b1;
    while (!(sc_done && pipe_done) &&
           (sc_cycles < MAX_CYCLES) && (pipe_cycles < MAX_CYCLES)) begin
      @(posedge clk);
    end
    #1;
  endtask

  initial begin
    $display("---- CPI sanity check start (NOT a throughput/speedup benchmark) ----");
    clk         = 1'b0;
    rst_n       = 1'b1;
    sc_cycles   = 0;
    pipe_cycles = 0;
    sc_done     = 1'b0;
    pipe_done   = 1'b0;

    run_until_done();

    if (!sc_done) begin
      fail_count++;
      $display("FAIL: single-cycle core did not complete within %0d cycles", MAX_CYCLES);
    end
    if (!pipe_done) begin
      fail_count++;
      $display("FAIL: pipelined core did not complete within %0d cycles", MAX_CYCLES);
    end

    if (dut_sc.regfile_inst.regs[1] === EXPECTED_X1 &&
        dut_pipe.regfile_inst.regs[1] === EXPECTED_X1) begin
      pass_count++;
      $display("PASS: x1 = %0d on both cores", EXPECTED_X1);
    end else begin
      fail_count++;
      $display("FAIL: x1 expected=%0d got sc=%0d pipe=%0d",
                EXPECTED_X1, dut_sc.regfile_inst.regs[1], dut_pipe.regfile_inst.regs[1]);
    end

    // Sanity bound: pipeline fill is a fixed ~4 cycles, so with
    // forwarding correctly eliminating stalls on this pure 0-gap chain,
    // pipe_cycles should be close to N_REAL_INSTR (well under 2x it). A
    // regression back to 3-cycle-per-hazard stall-only timing would blow
    // this bound wide open.
    if (pipe_cycles < (2 * N_REAL_INSTR)) begin
      pass_count++;
      $display("PASS: pipelined cycle count (%0d) stays well under 2x instruction count (%0d) — forwarding is working",
                pipe_cycles, N_REAL_INSTR);
    end else begin
      fail_count++;
      $display("FAIL: pipelined cycle count (%0d) is bloated relative to instruction count (%0d) — forwarding may have regressed",
                pipe_cycles, N_REAL_INSTR);
    end

    $display("---- CPI ----");
    $display("dynamic instructions:  %0d", N_REAL_INSTR);
    $display("single-cycle cycles:   %0d (CPI = %0d.%02d, always ~1.0 by construction)",
              sc_cycles, sc_cycles / N_REAL_INSTR, ((sc_cycles * 100) / N_REAL_INSTR) % 100);
    $display("pipelined cycles:      %0d (CPI = %0d.%02d)",
              pipe_cycles, pipe_cycles / N_REAL_INSTR, ((pipe_cycles * 100) / N_REAL_INSTR) % 100);
    $display("Note: this is a CPI sanity check, not a speedup measurement.");
    $display("Both cores share one simulated clk, so this cannot show the");
    $display("clock-frequency advantage pipelining is actually about — that");
    $display("requires post-synthesis Fmax comparison. See design-notes.md.");

    $display("---- cpi_sanity testbench done: %0d passed, %0d failed ----", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else $display("SOME TESTS FAILED");

    $finish;
  end

endmodule : tb_cpi_sanity
