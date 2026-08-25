# Compiles and runs the ALU testbench with Icarus Verilog.
# Usage: from sim/, run .\run_alu.ps1

$ErrorActionPreference = "Stop"

$RTL = @("../rtl/riscv_pkg.sv", "../rtl/alu.sv")
$TB  = "../verification/tb_alu.sv"

iverilog -g2012 -o alu_sim.vvp @RTL $TB
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp alu_sim.vvp