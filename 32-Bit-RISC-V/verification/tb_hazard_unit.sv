// tb_hazard_unit.sv
// Directed self-checking testbench for the load-use hazard detection
// unit (narrowed scope now that forwarding_unit handles every other RAW
// hazard, and branches resolve in EX like everything else). Run via
// sim/run_hazard_unit.ps1

`timescale 1ns / 1ps

module tb_hazard_unit;

  logic [4:0] rs1_id, rs2_id, rd_ex;
  logic       load_ex;
  logic       stall;

  int pass_count = 0;
  int fail_count = 0;

  hazard_unit dut (
    .rs1_id  (rs1_id),
    .rs2_id  (rs2_id),
    .load_ex (load_ex),
    .rd_ex   (rd_ex),
    .stall   (stall)
  );

  task automatic check(
    input logic [4:0] a_rs1, input logic [4:0] a_rs2,
    input logic       a_load_ex, input logic [4:0] a_rd_ex,
    input logic       expected, input string test_name
  );
    rs1_id  = a_rs1;
    rs2_id  = a_rs2;
    load_ex = a_load_ex;
    rd_ex   = a_rd_ex;
    #1;
    if (stall === expected) begin
      pass_count++;
      $display("PASS: %-40s stall=%0b", test_name, stall);
    end else begin
      fail_count++;
      $display("FAIL: %-40s expected=%0b got=%0b", test_name, expected, stall);
    end
  endtask

  initial begin
    $display("---- hazard_unit testbench start ----");

    check(5'd1, 5'd2, 1'b0, 5'd0, 1'b0, "no EX-stage instruction: no stall");
    check(5'd1, 5'd2, 1'b0, 5'd1, 1'b0, "EX-stage rd matches but not a load: no stall");
    check(5'd1, 5'd2, 1'b1, 5'd3, 1'b0, "EX-stage load, no address match: no stall");

    check(5'd3, 5'd2, 1'b1, 5'd3, 1'b1, "load-use hazard on rs1");
    check(5'd1, 5'd3, 1'b1, 5'd3, 1'b1, "load-use hazard on rs2");
    check(5'd3, 5'd3, 1'b1, 5'd3, 1'b1, "load-use hazard on both rs1 and rs2");

    check(5'd3, 5'd2, 1'b1, 5'd0, 1'b0, "load targets x0: no stall");
    check(5'd0, 5'd0, 1'b1, 5'd0, 1'b0, "consumer reads only x0, load targets x0: no stall");

    $display("---- hazard_unit testbench done: %0d passed, %0d failed ----", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else $display("SOME TESTS FAILED");

    $finish;
  end

endmodule : tb_hazard_unit
