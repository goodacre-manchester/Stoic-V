# Spike lock-step retire-compare (cosim)

`make -C sim cosim` (or `bash sim/cosim/run_cosim.sh`) runs each in-scope test on
both our Verilator model and **Spike**, then diffs the architectural
**GPR-write stream** instruction-by-instruction. This is stronger than the
end-of-test signature/`tohost` checks (archtest/riscv-tests): it pinpoints the
exact retire where a wrong value would first commit.

**Result:** 48/48 match — rv32ui (40 in scope) + rv32um (8).

## How it works

- The core carries the retiring PC to WB (`w_pc`); `tb_top` emits one line per
  committed write to x1..x31 — `"<pc> <rd> <val>"` — when given `+trace=<file>`
  (a hierarchical reference to the WB commit signals; simulation-only, pruned in
  synth).
- Spike is run with `-l --log-commits`; [`cosim_compare.py`](cosim_compare.py)
  reduces both streams to `(pc, rd, val)` over x1..x31, drops Spike's boot-ROM
  commits (`pc < 0x8000_0000`, which our core doesn't execute), and diffs.

## Carve-out (README §10.3)

`ma_data` (misaligned) and `fence_i` (Zifencei) are skipped: Spike would diverge
on misaligned ops and our aligned-only core would hang; Zifencei isn't claimed.

## Prereqs (WSL)

Spike at `~/riscv-tools/bin`, `riscv64-unknown-elf-gcc`, verilator, and the
riscv-tests clone at `~/src/riscv-tests` (override with `RVT=`). Reuses the
`0x8000_0000` arch sim (`make arch-sim`). See `../../docs/local-resume.md`.
