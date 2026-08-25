# Live showcase: builds and runs the Fibonacci demo once (fast, via
# Icarus), then replays its narration at a human-watchable pace, looping
# forever until you press Ctrl+C. For live demos -- see run_fibonacci.ps1
# for the actual pass/fail verification run.
# Usage: from sim/, run .\run_fibonacci_demo.ps1

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
    "../rtl/riscv_core_pipelined.sv"
)
$TB = "../verification/tb_fibonacci_demo.sv"

iverilog -g2012 -o fibonacci_demo_sim.vvp @RTL $TB
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# The actual RTL simulation is effectively instantaneous -- capture its
# full output once, filter out Icarus's benign "sorry: constant selects"
# elaboration notices, then replay the clean narration at a pace a human
# can actually watch, on a loop, until interrupted.
$lines = @(& vvp fibonacci_demo_sim.vvp | Where-Object { $_ -notmatch "sorry:|\$finish called" })

Write-Host ""
Write-Host "Press Ctrl+C to stop." -ForegroundColor Yellow
Write-Host ""
Start-Sleep -Seconds 1

while ($true) {
    foreach ($line in $lines) {
        Write-Output $line
        Start-Sleep -Milliseconds 400
    }
    Start-Sleep -Seconds 2
}
