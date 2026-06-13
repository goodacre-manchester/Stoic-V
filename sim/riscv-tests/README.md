# Official Berkeley riscv-tests — rv32ui + rv32um

`make -C sim riscv-tests` (or `bash sim/riscv-tests/run_riscv_tests.sh`) builds
and runs the official [riscv-tests](https://github.com/riscv-software-src/riscv-tests)
`rv32ui` (base integer) and `rv32um` (M) suites on our Verilator model. The
tests are **self-checking** via `tohost` (pass = store 1, fail = odd>1), so no
Spike/reference is needed.

**Result:** 48/48 pass — rv32ui (40 in scope) + rv32um (8).

## Custom env (`env/riscv_test.h`)

The stock `p` environment signals completion with `ecall` (handled by a trap
vector) and enters tests via `mret` to U-mode. This v1 core is **M-mode only and
omits precise synchronous exceptions** (README §10.3), so `ecall` does not trap.
The custom env instead runs bare-metal in M-mode and signals pass/fail with a
**direct `tohost` store** — matching the unit TB's completion detection. It links
at `0x8000_0000` to match the arch sim (`make arch-sim`, `RESET_VEC`/`MEM_BASE`).

## Carve-out (skipped, logged at runtime)

- `ma_data` — misaligned data accesses (aligned-only core).
- `fence_i` — Zifencei (not claimed; no I-cache to make coherent).

## Prereqs (WSL)

`riscv64-unknown-elf-gcc` + `verilator`, and the riscv-tests clone at
`~/src/riscv-tests` (override with `RVT=`). See `../../docs/local-resume.md`.
