# Compiles and runs the constrained-random instruction testbench
# (riscv_core_singlecycle as reference model vs. riscv_core_pipelined as
# DUT, across many randomly generated instruction streams) with Icarus
# Verilog.
# Usage: from sim/, run .\run_random.ps1

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
    "../rtl/if_id_reg.sv",
    "../rtl/id_ex_reg.sv",
    "../rtl/ex_mem_reg.sv",
    "../rtl/mem_wb_reg.sv",
    "../rtl/hazard_unit.sv",
    "../rtl/forwarding_unit.sv",
    "../rtl/riscv_core_singlecycle.sv",
    "../rtl/riscv_core_pipelined.sv"
)
$TB = "../verification/tb_random.sv"

iverilog -g2012 -o random_sim.vvp @RTL $TB
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp random_sim.vvp
