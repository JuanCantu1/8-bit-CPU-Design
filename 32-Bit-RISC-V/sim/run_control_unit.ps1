# Compiles and runs the control unit testbench with Icarus Verilog.
# Usage: from sim/, run .\run_control_unit.ps1

$ErrorActionPreference = "Stop"

$RTL = @("../rtl/riscv_pkg.sv", "../rtl/control_unit.sv")
$TB  = "../verification/tb_control_unit.sv"

iverilog -g2012 -o control_unit_sim.vvp @RTL $TB
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp control_unit_sim.vvp