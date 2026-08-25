# Compiles and runs the register file testbench with Icarus Verilog.
# Usage: from sim/, run .\run_regfile.ps1

$ErrorActionPreference = "Stop"

$RTL = @("../rtl/riscv_pkg.sv", "../rtl/regfile.sv")
$TB  = "../verification/tb_regfile.sv"

iverilog -g2012 -o regfile_sim.vvp @RTL $TB
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp regfile_sim.vvp