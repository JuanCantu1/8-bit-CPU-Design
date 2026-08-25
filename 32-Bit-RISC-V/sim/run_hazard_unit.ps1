# Compiles and runs the hazard unit testbench with Icarus Verilog.
# Usage: from sim/, run .\run_hazard_unit.ps1

$ErrorActionPreference = "Stop"

$RTL = @("../rtl/hazard_unit.sv")
$TB  = "../verification/tb_hazard_unit.sv"

iverilog -g2012 -o hazard_unit_sim.vvp @RTL $TB
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp hazard_unit_sim.vvp
