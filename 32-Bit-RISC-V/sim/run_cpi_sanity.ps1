# Compiles and runs the CPI sanity check (NOT a throughput benchmark --
# see the file header) with Icarus Verilog.
# Usage: from sim/, run .\run_cpi_sanity.ps1

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
$TB = "../verification/tb_cpi_sanity.sv"

iverilog -g2012 -o cpi_sanity_sim.vvp @RTL $TB
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp cpi_sanity_sim.vvp
