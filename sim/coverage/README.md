# RTL coverage

`make -C sim coverage` measures Verilator line+toggle coverage of the core over
the whole test corpus and reports per-file line coverage.

**Core line coverage: 89.8%** (datapath units ~98–100%). See
[`docs/verification-status.md`](../../docs/verification-status.md) §7 for the
per-file table and gap analysis.

## How it works

Two coverage-instrumented builds are exercised and their `coverage.dat` merged:

- **unit build** (`cov-sim-unit`, base 0x0) ← the directed suite
  (`tests/*.s`: I/M/Zb + `trap_*` + `irq_stress` + `csr_ops`) — control paths the
  arithmetic suites don't reach.
- **arch build** (`cov-sim-arch`, base 0x8000_0000) ← riscv-tests rv32ui+rv32um
  **and** arch-test I/M/B (covers every Zba/Zbb/Zbs encoding).

`sim_main.cpp` writes per-run coverage to `+covfile=<f>` (guarded by
`VM_COVERAGE`); `verilator_coverage` merges to `cov.info` (lcov) and annotates
sources under `work/annotated/`.

The remaining uncovered core lines are explained, not blind spots: decode's
illegal-instruction `default` branches are unreachable by a valid-only corpus
(closing them needs illegal-instruction trapping — out of v1 scope), and
`mbv.sv`'s low number is the functionally-omitted debug-port tie-offs.

Prereqs (WSL): verilator (+ `verilator_coverage`), `riscv64-unknown-elf` GCC,
riscv-tests at `~/src/riscv-tests`, arch-test at `~/src/riscv-arch-test`.
