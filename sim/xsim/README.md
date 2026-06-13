# `sim/xsim/` — second-simulator gate (Vivado xsim)

`make xsim` runs the directed unit suite (`tests/*.s`) under **Vivado xsim** — the
simulator the host SoC integrates with — instead of Verilator. It exists because
two integrator-reported defects (the LMB back-to-back stale read and the
continuous-`assign` forwarding-sensitivity gap) lived in the **semantic delta
between Verilator and xsim**, and Verilator computed the correct answer regardless
of stimulus, so no Verilator vector could catch them. See
[`docs/verification.md` §4.1](../../docs/verification.md).

## Files

| File | Role |
|---|---|
| [`run_xsim.ps1`](run_xsim.ps1) | runner (PowerShell, Windows-native): WSL builds hex → `xvlog`/`xelab` once → `xsim` replays each hex → score PASS/FAIL |
| [`../../tb/xsim/tb_xsim.sv`](../../tb/xsim/tb_xsim.sv) | SV testbench driver: the analogue of `tb/cpp/sim_main.cpp` (clk/reset/irq/timeout/tohost-detect over `tb_top`) |

## Run

```
pwsh sim/xsim/run_xsim.ps1                 # all tests/*.s  (WSL assembles hex, then xsim)
pwsh sim/xsim/run_xsim.ps1 -NoBuild        # reuse existing sim/build/*.hex
pwsh sim/xsim/run_xsim.ps1 -Tests fwd_matrix,loadbase_fwd,bus_patterns
pwsh sim/xsim/run_xsim.ps1 -VivadoBin 'D:\Xilinx\2025.2.1\Vivado\bin'
```

Exit 0 = all PASS; nonzero = any FAIL/TIMEOUT. Generated artifacts go to
`work/` (git-ignored).

## Requirements

- **Vivado** (xvlog/xelab/xsim) on Windows — auto-detected, or `-VivadoBin`/`$XILINX_VIVADO`.
- **WSL** distro with the riscv toolchain (default `Ubuntu-24.04`, `-WslDistro` to
  override) to assemble the tests; or pre-build hex in WSL (`make -C sim test`) and
  pass `-NoBuild`.

## Implementation notes (xsim quirks the runner works around)

- The `xsim.bat` wrapper splits a `name=value` arg on `=` and chokes on a
  drive-letter colon, so plusargs are passed through a per-run `.bat` with the
  value quoted (`--testplusarg "hex=foo.hex"`) and the hex is referenced by a
  bare relative name from the `work/` cwd.
- `--runall` must be a CLI flag (it has no effect from a `-f` command file).
- The runtime flags are double-dash (`--runall`, `--testplusarg`, `--onfinish`).
