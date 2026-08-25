// tb_forwarding_unit.sv
// Directed self-checking testbench for the EX-stage forwarding select
// logic. Run via sim/run_forwarding_unit.ps1

`timescale 1ns / 1ps

module tb_forwarding_unit;
  import riscv_pkg::*;

  logic [4:0] rs1_ex, rs2_ex, rd_mem, rd_wb;
  logic       reg_write_mem, reg_write_wb;
  fwd_sel_e   forward_a, forward_b;

  int pass_count = 0;
  int fail_count = 0;

  forwarding_unit dut (
    .rs1_ex        (rs1_ex),
    .rs2_ex        (rs2_ex),
    .reg_write_mem (reg_write_mem),
    .rd_mem        (rd_mem),
    .reg_write_wb  (reg_write_wb),
    .rd_wb         (rd_wb),
    .forward_a     (forward_a),
    .forward_b     (forward_b)
  );

  task automatic check(
    input logic [4:0] a_rs1, input logic [4:0] a_rs2,
    input logic       a_we_mem, input logic [4:0] a_rd_mem,
    input logic       a_we_wb,  input logic [4:0] a_rd_wb,
    input fwd_sel_e   exp_a, input fwd_sel_e exp_b,
    input string      test_name
  );
    rs1_ex        = a_rs1;
    rs2_ex        = a_rs2;
    reg_write_mem = a_we_mem; rd_mem = a_rd_mem;
    reg_write_wb  = a_we_wb;  rd_wb  = a_rd_wb;
    #1;
    if (forward_a === exp_a && forward_b === exp_b) begin
      pass_count++;
      $display("PASS: %-40s forward_a=%0d forward_b=%0d", test_name, forward_a, forward_b);
    end else begin
      fail_count++;
      $display("FAIL: %-40s expected a=%0d b=%0d got a=%0d b=%0d",
                test_name, exp_a, exp_b, forward_a, forward_b);
    end
  endtask

  initial begin
    $display("---- forwarding_unit testbench start ----");

    check(5'd1, 5'd2, 1'b0,5'd0, 1'b0,5'd0, FWD_NONE, FWD_NONE, "no producers active: no forward");
    check(5'd1, 5'd2, 1'b1,5'd3, 1'b1,5'd4, FWD_NONE, FWD_NONE, "producers active, no address match");

    check(5'd3, 5'd2, 1'b1,5'd3, 1'b0,5'd0, FWD_EX_MEM, FWD_NONE, "EX/MEM match on rs1");
    check(5'd1, 5'd3, 1'b1,5'd3, 1'b0,5'd0, FWD_NONE, FWD_EX_MEM, "EX/MEM match on rs2");
    check(5'd4, 5'd2, 1'b0,5'd0, 1'b1,5'd4, FWD_MEM_WB, FWD_NONE, "MEM/WB match on rs1");
    check(5'd1, 5'd4, 1'b0,5'd0, 1'b1,5'd4, FWD_NONE, FWD_MEM_WB, "MEM/WB match on rs2");

    check(5'd5, 5'd5, 1'b1,5'd5, 1'b1,5'd5, FWD_EX_MEM, FWD_EX_MEM, "EX/MEM takes priority over MEM/WB (both match)");

    check(5'd3, 5'd2, 1'b0,5'd3, 1'b0,5'd0, FWD_NONE, FWD_NONE, "matching rd_mem but reg_write_mem=0: no forward");
    check(5'd3, 5'd2, 1'b0,5'd0, 1'b0,5'd3, FWD_NONE, FWD_NONE, "matching rd_wb but reg_write_wb=0: no forward");

    check(5'd3, 5'd2, 1'b1,5'd0, 1'b0,5'd0, FWD_NONE, FWD_NONE, "EX/MEM producer targets x0: no forward");
    check(5'd3, 5'd2, 1'b0,5'd0, 1'b1,5'd0, FWD_NONE, FWD_NONE, "MEM/WB producer targets x0: no forward");
    check(5'd0, 5'd0, 1'b1,5'd0, 1'b1,5'd0, FWD_NONE, FWD_NONE, "consumer reads only x0: no forward");

    check(5'd3, 5'd4, 1'b1,5'd3, 1'b1,5'd4, FWD_EX_MEM, FWD_MEM_WB, "independent forward_a/forward_b from different sources");

    $display("---- forwarding_unit testbench done: %0d passed, %0d failed ----", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else $display("SOME TESTS FAILED");

    $finish;
  end

endmodule : tb_forwarding_unit
