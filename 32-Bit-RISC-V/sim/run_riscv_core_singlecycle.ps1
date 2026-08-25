# Compiles and runs the single-cycle RV32I datapath testbench with Icarus
# Verilog. Usage: from sim/, run .\run_riscv_core_singlecycle.ps1

$ErrorActionPreference = "Stop"

$RTL = @(
    "../rtl/riscv_pkg.sv",
    "../rtl/alu.sv",
    "../rtl/regfile.sv",
    "../rtl/control_unit.sv",
    "../rtl/decoder.sv",
    "../rtl/pc_reg.sv",
    "../rtl/imem.sv",
    "../rtl/dmem.sv",
    "../rtl/riscv_core_singlecycle.sv"
)
$TB = "../verification/tb_riscv_core_singlecycle.sv"

iverilog -g2012 -o riscv_core_singlecycle_sim.vvp @RTL $TB
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp riscv_core_singlecycle_sim.vvp
