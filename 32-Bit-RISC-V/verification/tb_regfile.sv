// tb_regfile.sv
// Directed self-checking testbench for the register file. Run via
// sim/run_regfile.ps1

`timescale 1ns / 1ps

module tb_regfile;
  import riscv_pkg::*;

  logic            clk;
  logic [4:0]      rs1_addr, rs2_addr, rd_addr;
  logic [XLEN-1:0] rd_data;
  logic            we;
  logic [XLEN-1:0] rs1_data, rs2_data;

  int pass_count = 0;
  int fail_count = 0;

  regfile dut (
    .clk      (clk),
    .rs1_addr (rs1_addr),
    .rs2_addr (rs2_addr),
    .rd_addr  (rd_addr),
    .rd_data  (rd_data),
    .we       (we),
    .rs1_data (rs1_data),
    .rs2_data (rs2_data)
  );

  always #5 clk = ~clk;

  task automatic write_reg(input logic [4:0] addr, input logic [XLEN-1:0] data);
    rd_addr = addr;
    rd_data = data;
    we      = 1'b1;
    @(posedge clk);
    #1;
    we = 1'b0;
  endtask

  task automatic check_read(
    input logic [4:0]      a1,
    input logic [4:0]      a2,
    input logic [XLEN-1:0] expected1,
    input logic [XLEN-1:0] expected2,
    input string           test_name
  );
    rs1_addr = a1;
    rs2_addr = a2;
    #1;
    if (rs1_data === expected1 && rs2_data === expected2) begin
      pass_count++;
      $display("PASS: %-28s rs1=0x%h rs2=0x%h", test_name, rs1_data, rs2_data);
    end else begin
      fail_count++;
      $display("FAIL: %-28s expected rs1=0x%h rs2=0x%h got rs1=0x%h rs2=0x%h",
                test_name, expected1, expected2, rs1_data, rs2_data);
    end
  endtask

  initial begin
    $display("---- regfile testbench start ----");

    clk      = 1'b0;
    rs1_addr = '0;
    rs2_addr = '0;
    rd_addr  = '0;
    rd_data  = '0;
    we       = 1'b0;

    // x0 reads zero before any writes.
    check_read(5'd0, 5'd0, 32'd0, 32'd0, "x0 reads zero at reset");

    // Writing to x0 must not stick.
    write_reg(5'd0, 32'hFFFFFFFF);
    check_read(5'd0, 5'd0, 32'd0, 32'd0, "x0 ignores writes");

    // Basic write then read back via rs1.
    write_reg(5'd5, 32'hDEADBEEF);
    check_read(5'd5, 5'd0, 32'hDEADBEEF, 32'd0, "write x5, read via rs1");

    // Write to top register x31, read back via rs2.
    write_reg(5'd31, 32'h12345678);
    check_read(5'd0, 5'd31, 32'd0, 32'h12345678, "write x31, read via rs2");

    // Both read ports independent: different addresses at once.
    check_read(5'd5, 5'd31, 32'hDEADBEEF, 32'h12345678, "dual-port independent read");

    // Both read ports pointed at the same register.
    check_read(5'd5, 5'd5, 32'hDEADBEEF, 32'hDEADBEEF, "dual-port same-address read");

    // Overwrite an already-written register.
    write_reg(5'd5, 32'h00000001);
    check_read(5'd5, 5'd0, 32'h00000001, 32'd0, "overwrite x5");

    // Write-enable gating: signals set but we stays low, no write happens.
    // Seed x7 with a known value first so an unintended write is
    // distinguishable from x7's uninitialized (X) reset state.
    write_reg(5'd7, 32'h11111111);
    rd_addr = 5'd7;
    rd_data = 32'hABCDEF00;
    we      = 1'b0;
    @(posedge clk);
    #1;
    check_read(5'd7, 5'd0, 32'h11111111, 32'd0, "we=0 blocks write");

    // Synchronous write timing: read before the clock edge must still see
    // the old value; only after the edge does it update. Seed x6 first for
    // the same reason as above.
    write_reg(5'd6, 32'h22222222);
    rd_addr  = 5'd6;
    rd_data  = 32'hCAFEBABE;
    we       = 1'b1;
    rs1_addr = 5'd6;
    #1;
    if (rs1_data === 32'h22222222) begin
      pass_count++;
      $display("PASS: %-28s rs1=0x%h", "write not yet visible pre-edge", rs1_data);
    end else begin
      fail_count++;
      $display("FAIL: %-28s expected rs1=0x%h got rs1=0x%h",
                "write not yet visible pre-edge", 32'h22222222, rs1_data);
    end
    @(posedge clk);
    #1;
    we = 1'b0;
    check_read(5'd6, 5'd0, 32'hCAFEBABE, 32'd0, "write visible post-edge");

    $display("---- regfile testbench done: %0d passed, %0d failed ----", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else $display("SOME TESTS FAILED");

    $finish;
  end

endmodule : tb_regfile