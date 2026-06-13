# `sim/cosim-fw/` — system-level lock-step (compiled C vs Spike, free-running slave)

`make cosim-fw` compiles real **C firmware** with `gcc -O0/-O2/-O3`, runs it on the
core against the **canonical free-running registered BRAM** (`+dfree`), and compares
**every committed GPR write** against Spike instruction-by-instruction. A divergence
is a real architectural bug.

## Why it exists

The 2026-06 integrator escapes (LMB back-to-back, store→load) lived in **real
compiled-code patterns on real BRAM** — function epilogues, stack spill/restore,
back-to-back memory, pointer chases — none of which hand-written asm on the benign
default BFM exercised. This harness closes that gap:

- **Compiled C, not asm** — `-O0/-O2/-O3` give three different codegen shapes per
  workload (the same axis the P7.1 firmware *refactor* changed). `-O0` especially
  spills every local to the stack → dense store-then-restore-load traffic.
- **Free-running slave** (`+dfree`) — the canonical Xilinx BRAM Port A
  (`data_rd_q <= mem[addr]` every cycle), the slave that exposes the store→load
  class. Override with `SLAVE=+dedge=1` etc.
- **Spike is the golden model** — the workloads are pure compute + memory (no MMIO),
  so Spike's architectural GPR stream is the reference. MMIO aperture timing is the
  integrator's concern, not the core's.

**Proven teeth:** with the rc7 store→load fix reverted, `callchain` (all opts),
`memops`, and others **DIVERGE** from Spike here — i.e. this harness catches P7.1
*organically from compiled C*, no hand-written reproducer required.

## Run

```
make -C sim cosim-fw                 # all workloads × -O0/-O2/-O3 on +dfree
SLAVE=+dedge=1 make -C sim cosim-fw  # against the edge-detect slave instead
OPTS="-O2" make -C sim cosim-fw      # one opt level
```

Requires WSL: `riscv64-unknown-elf-gcc` (C), Spike (`SPIKE_BIN`), the arch sim.

## Files

| File | Role |
|---|---|
| [`run_cosim_fw.sh`](run_cosim_fw.sh) | build each workload × opt → run core (`+dfree`, retire trace) → Spike `--log-commits` → diff (`../cosim/cosim_compare.py`) |
| [`crt0.S`](crt0.S) | bare-metal C runtime (sp, zero .bss, call main, HTIF `tohost` exit) |
| [`link.ld`](link.ld) | base 0x8000_0000 (matches Spike + arch sim), 16 KiB stack |
| [`workloads/`](workloads/) | `callchain` (epilogue spill/restore), `memops` (struct copy / sub-word), `ptrchase` (load→load), `sortsum` (in-place sort + recursion) |

## Adding a workload

Drop a `workloads/<name>.c` with an `int main(void)` that is **deterministic** and
**pure compute + memory** (no libc, no MMIO, no FP). The lock-step against Spike is
the check — no in-program assertions needed.
