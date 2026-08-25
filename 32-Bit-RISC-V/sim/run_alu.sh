#!/usr/bin/env bash
# Compiles and runs the ALU testbench with Icarus Verilog.
# Usage: from sim/, run ./run_alu.sh

set -e

RTL="../rtl/riscv_pkg.sv ../rtl/alu.sv"
TB="../verification/tb_alu.sv"

iverilog -g2012 -o alu_sim.vvp $RTL $TB
vvp alu_sim.vvp