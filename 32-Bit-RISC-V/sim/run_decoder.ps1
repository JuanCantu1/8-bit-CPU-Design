# Compiles and runs the decoder testbench with Icarus Verilog.
# Usage: from sim/, run .\run_decoder.ps1

$ErrorActionPreference = "Stop"

$RTL = @("../rtl/riscv_pkg.sv", "../rtl/decoder.sv")
$TB  = "../verification/tb_decoder.sv"

iverilog -g2012 -o decoder_sim.vvp @RTL $TB
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp decoder_sim.vvp
