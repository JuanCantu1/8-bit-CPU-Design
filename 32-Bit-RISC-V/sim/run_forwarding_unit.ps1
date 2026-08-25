# Compiles and runs the forwarding unit testbench with Icarus Verilog.
# Usage: from sim/, run .\run_forwarding_unit.ps1

$ErrorActionPreference = "Stop"

$RTL = @("../rtl/riscv_pkg.sv", "../rtl/forwarding_unit.sv")
$TB  = "../verification/tb_forwarding_unit.sv"

iverilog -g2012 -o forwarding_unit_sim.vvp @RTL $TB
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp forwarding_unit_sim.vvp
