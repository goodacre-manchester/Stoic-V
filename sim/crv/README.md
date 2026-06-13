# `sim/crv/` — constrained-random verification (ISG + Spike lock-step)

`make crv` generates **pseudo-random, hazard-biased** RV32IM_zba_zbb_zbs_zicsr programs
and **lock-steps each against Spike**. Hand-written tests catch the bugs you think of;
this catches the ones you don't — the forwarding / hazard-unit / pipeline-congestion
corner cases that only trigger under a specific instruction mix.

## What it is

A focused **instruction-sequence generator** ([`gen_rand.py`](gen_rand.py)) — the same
CRV methodology as Google's **riscv-dv**, but on the open toolchain. (riscv-dv's core
generator is SystemVerilog/UVM and needs a commercial constraint solver — VCS / Questa
/ Xcelium; this delivers the equivalent with Python + Spike.) The instruction
distribution is biased **hard toward pipeline hazards**:

- back-to-back **RAW dependencies** (a source is the previous instruction's dest →
  ALU-forwarding stress),
- **load-to-use** (a load's result used by the very next instruction),
- **store-then-load** (the rc7 class),
- **mul/div-to-use** (a multiplier/divider result used immediately),
- **branches on freshly-computed operands**.

Every program is deterministic per seed, self-terminating, and **safe** so Spike == the
core: loads/stores go through a reserved base register (`x3`) into a zeroed scratch
region with masked-aligned offsets (aligned-only per the v1 carve-out); branches are
forward-only and bounded; `x0`/`x3` are never written; no `jal`/`jalr`/`ecall`/`fence`/
trap-state CSRs (the random *datapath*, not control-flow escapes). The free-running
slave (`+dfree`) is used so the bus is stressed too.

**A failure is one seed** → trivially reproduced: `python3 sim/crv/gen_rand.py <seed>`.

## Run

```
make -C sim crv                          # default: 200 programs × 400 instr on +dfree (incl. CSR RMW)
NPROG=1000 NINSTR=600 make -C sim crv     # deeper sweep
SLAVE=+drand=1 make -C sim crv            # random slave timing too
CRV_CSR=0 make -C sim crv                 # drop CSR ops from the mix
```

Requires WSL: `riscv64-unknown-elf-gcc`, Spike. In `make ci-full`.

## Scope

Pure compute + memory + CSR (no MMIO, no async interrupts), so Spike is the golden
model. Random *asynchronous-interrupt* injection (bit-exact vs Spike) is a follow-up;
the `irq-stress` gate already sweeps MEI across pipeline positions.

## CRV found a real bug — the stall-coincident CSR-RMW divergence (fixed)

When CSR ops first went into the mix, **13/200** programs diverged from Spike: a
`csrr* rd, mscratch, rs` whose `rd` read-back was the **NEW** value instead of the
architectural **OLD** value. The simple back-to-back forward case always passed
([`../../tests/csr_hazard.s`](../../tests/csr_hazard.s)) — it was **stall-coincident**.
Root cause: the CSR write commits in EX, but an ungated `csr_we` stayed asserted while
the CSR instruction was **frozen in EX by a `dmem_stall`** (an older load/store in the
single-outstanding gap — the seed-4 `sh; lhu; csrrw` shape), so the write committed
early and the read-back captured the modified value. **Fixed** in `rv_core.sv` by gating
`csr_we` with `~dmem_stall` (regression
[`../../tests/csr_dmem_hazard.s`](../../tests/csr_dmem_hazard.s), FAILs pre-fix under
Verilator AND xsim). CSR ops are therefore now **in the default mix** and **CRV is
200/200 with CSR included**. Full write-up: `docs/verification-status.md` §12.
