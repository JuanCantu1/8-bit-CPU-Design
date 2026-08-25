# Screenshots

Drop terminal screenshots here using the exact filenames referenced from
the project's top-level `README.md`. Once a file exists at the path an
image tag points to, it renders automatically — no other edits needed.

| Filename | How to capture |
|---|---|
| `pipelined_core_test.png` | `cd sim`, run `.\run_riscv_core_pipelined.ps1`, screenshot the terminal from the first `PASS:` line down through `ALL TESTS PASSED`. |
| `full_program_test.png` | Run `.\run_full_program.ps1`, screenshot from `---- throughput ----` down through `ALL TESTS PASSED` (includes the dual-core cycle counts). |
| `compliance_test.png` | Run `.\run_compliance.ps1`, screenshot from the top (`Group 1`) down through `ALL TESTS PASSED`. |
| `coverage_report.png` | Run `.\run_coverage.ps1`, screenshot the full `==== functional coverage report ====` block down through `FULL FUNCTIONAL COVERAGE`. |
| `random_test.png` | Run `.\run_random.ps1`, screenshot the last ~15 `PASS:` lines through the final `300 passed, 0 failed, 0 inconclusive` / `ALL TESTS PASSED` lines. |

A plain terminal screenshot (PowerShell, default colors, whole window)
is fine — no need to crop tightly, GitHub scales images to fit.
