# `sim/scoreboard/` — randomized-slave-timing scoreboard

`make scoreboard` is the systematic catch-all for the bus-capture / ordering class
(rc4 back-to-back, rc7 store→load). Instead of a few hand-picked slave modes, it
drives the data bus with a **randomized COMPLIANT registered slave** (`+drand=<seed>`)
and asserts the core's **architectural result is INVARIANT to the timing** — i.e.
identical to Spike — across a **seed sweep**. A divergence on any seed is a real bug:
a load/store that commits the wrong value for some legal slave timing.

## How it works

- **`+drand=<seed>`** ([`tb/models/lmb_bram.sv`](../../tb/models/lmb_bram.sv)): per
  access it randomly picks a contract-legal behaviour — **free-running 1-cycle**
  (`== +dfree`, the read tracks the address; the slave style that exposes the
  store→load class) **or latched with 1..6 wait states** (`== +dwait`, the canonical
  multi-cycle slave that latches the strobe-cycle address). The compliance rule that
  matters: a *free-running* read is only legal at **1-cycle** latency (the core
  presents the address for one cycle then advances), so wait-state latency lives on
  the *latched* variant.
- **Spike is the timing-agnostic golden** — computed once per workload; the core is
  re-run under each seed; `cosim_compare.py` diffs the GPR-write streams.
- Reuses the [`../cosim-fw/`](../cosim-fw/) C workloads (epilogue spill/restore,
  struct copy, pointer chase, in-place sort).

## Validated

- **128/128** (4 workloads × {-O0,-O2} × 16 seeds) invariant to random compliant
  timing on the current core.
- **Teeth:** with the store→load fix reverted, **67/80 diverge** — the random timing
  reproduces the class without a hand-written reproducer.

## Run

```
make -C sim scoreboard
SEEDS="1 2 3 ... " OPTS="-O0 -O2" make -C sim scoreboard   # customise the sweep
```

Requires WSL: `riscv64-unknown-elf-gcc` (C), Spike (`SPIKE_BIN`). In `make ci-full`.
