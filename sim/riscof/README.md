# Official RISC-V architectural test (RISCOF) — local conformance

`make -C sim archtest` (or `bash sim/riscof/run_archtest.sh`) runs the official
[riscv-arch-test](https://github.com/riscv-non-isa/riscv-arch-test) suite under
[RISCOF](https://github.com/riscv-software-src/riscof) with **Spike** as the
golden reference, comparing per-test signatures against our Verilator model.

**Result:** 75/75 pass — I (38), M (8), Zba/Zbb/Zbs (29).

## Scope / carve-out (README Requirements §10.3)

In scope: the **I, M, and Zba/Zbb/Zbs** instruction suites. Excluded, by
construction (the DUT ISA omits them and the suite is restricted to I/M/B):

- **Zbc** `clmul/clmulh/clmulr` — not implemented by this core.
- **misaligned, illegal-instruction, and synchronous-cause trap** suites — v1
  omits precise synchronous exceptions and assumes aligned access.

Do not report "arch-test passes" without stating this carve-out.

## Layout

| Path | Role |
|---|---|
| `dut/riscof_fabricrv.py` | DUT plugin: compile each test, run `Vtb_top`, dump the signature |
| `dut/env/{link.ld,model_test.h}` | DUT build env — **byte-identical layout to the Spike ref** so PC-relative signatures (auipc/jal/jalr) match |
| `dut/env/run_dut.sh` | per-test: objcopy→hex, pull symbol addrs, run the sim |
| `dut/fabricrv_isa.yaml`, `dut/fabricrv_platform.yaml` | riscv-config specs (`RV32IMZicsr_Zba_Zbb_Zbs`) |
| `spike/` | vendored Spike reference plugin (3 small fixes vs the shipped one, see below) |
| `run_archtest.sh` | orchestrator: build sim, restrict suite to I/M/B, generate `config.ini`, run RISCOF |

## How base matching works

Spike runs at its native `0x8000_0000` and its boot ROM forbids low DRAM, so the
core must execute at the **same** base for PC-relative results to match. The
arch sim is built with `-GRESET_VEC=0x8000_0000 -GMEM_BASE=0x8000_0000`
(`make arch-sim`); `run_dut.sh` shifts the flat image down to offset 0 for
`$readmemh`. Defaults are 0x0, so the normal unit TB / determinism / synth flows
are unchanged.

## Vendored Spike plugin fixes (`spike/riscof_spike_simple.py`)

The shipped `spike_simple` predates current tooling; three one-line fixes:
1. `riscv32-` → `riscv64-unknown-elf-gcc` (the installed multilib toolchain).
2. `ispec['PMP']` made defensive (riscv-config ≥3.x normalizes PMP away).
3. ISA pinned to `rv32im_zba_zbb_zbs` (the naive `"V" in ISA` check matched the
   `V` in `RV32`, spuriously enabling vector; `--misaligned` also removed —
   gone in Spike ≥1.1).

## Prereqs (WSL Ubuntu)

See [`../../docs/local-resume.md`](../../docs/local-resume.md). In short: Spike at
`~/riscv-tools/bin`, RISCOF venv at `~/riscof-venv`, arch-test (`old-framework-3.x`)
at `~/src/riscv-arch-test`, plus `verilator` + `riscv64-unknown-elf-gcc`.
Override paths via `ARCHTEST` / `VENV` / `SPIKE_BIN` env vars.
