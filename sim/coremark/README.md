# CoreMark — cycle-exact CoreMark/MHz on the custom core

`make -C sim coremark` (WSL) runs EEMBC CoreMark on the core under Verilator and
reports **CoreMark/MHz**, the standard frequency-independent cross-microarchitecture
metric.

## Why this is cycle-*exact* (not an estimate)

`CoreMark/MHz = iterations × 1e6 / cycles` — frequency-independent, so only the
cycle count matters. And because this core has **no caches, no speculation, no
branch prediction, and deterministic fixed-latency memory** — and the testbench
models the registered single-outstanding LMB exactly as the hardware contract — **the
Verilator cycle count equals the silicon cycle count, bit-for-bit.** There is no
cache/memory-hierarchy modelling gap. So the number below is exact, not approximate.

Correctness is proven by CoreMark's own validation: the standard performance-run
seeds (0,0,0x66) yield **seedcrc 0xe9f5** and the run prints **"Correct operation
validated"** (crclist 0xe714 / crcmatrix 0x1fd7 / crcstate 0x8e3a all match).

## Result

`rv32im_zba_zbb_zbs` (CRC-validated 0xe9f5 every run). The score is **compiler-robust
at ~1.9** — confirming it's the microarchitecture, not the toolchain, that sets it:

| Compiler | `-O2` | `-O3` |
|---|---|---|
| gcc 13.2.0 (apt `riscv64-unknown-elf`) | 1.823 | **1.949** |
| gcc 15.2.0 (xPack `riscv-none-elf`)    | 1.903 | 1.927 |

Best ≈ **1.949 CoreMark/MHz** → ≈ **487 CoreMark** at the 250 MHz FPGA target and
≈ **1559** at the ~800 MHz 22 nm ASIC target (CoreMark/MHz is frequency-independent;
absolute = score × Fmax). The binary genuinely uses the M and Zb* units: a disassembly
shows **29 mul/div** (`mul`/`divu`/`remu`) and **180 Zb\*** (`zext.h`, `sh1/2/3add`,
`sext.h`, `bexti`) instructions — not soft-emulated.

### Performance build option (`CORE_PERF`)

The default config uses a determinism-safe 2-cycle load-use (`P_LOADUSE=2`). The
`CORE_PERF` build define trades it back to 1 cycle for higher IPC; it defaults OFF
(the default µarch is unchanged):

| Config | load-use | CoreMark/MHz (gcc 13.2 `-O3`) | determinism | closes |
|---|---|---|---|---|
| default | 2-cycle | 1.949 | 286 cyc (8/8) | **250 MHz** (OOC, WNS ≈ +0.070 ns) |
| **`CORE_PERF`** | 1-cycle | **2.074** (+6 %) | 286 cyc (8/8) | needs banked aperture or lower clock (see caveat) |

Both stay fully deterministic (fixed latency, just shorter). Build/measure it:
`DEFS=+define+CORE_PERF TAG=cm_perf OPT=-O3 make -C sim coremark`. For synth/tile,
pass the Verilog define `CORE_PERF`. **Closure caveat:** at the 250 MHz target
(4.0 ns), the 1-cycle load-use path for the *instruction-aperture* load (cascaded
BRAM, ~1.8 ns Tco → ~5 ns path) does not close — so `CORE_PERF` requires that load
off the critical path: bank the instruction aperture (shallower read mux) or make it
multicycle. Ordinary DMEM loads (~1.05 ns Tco) fit 250. The default 2-cycle config
meets 250 MHz with no such constraint.

### Toolchain

Default is the apt `riscv64-unknown-elf-gcc 13.2` (the same compiler every
verification gate uses — untouched). A newer compiler is supported via override
without disturbing it:
```
# one-time: install gcc 15.2 (xPack) to ~/opt  (separate from apt)
wget https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v15.2.0-1/xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz
tar xzf xpack-*.tar.gz -C ~/opt
# run CoreMark with it:
CM_PREFIX=riscv-none-elf CM_BIN=$HOME/opt/xpack-riscv-none-elf-gcc-15.2.0-1/bin OPT=-O3 make -C sim coremark
```

## Reading the number (honest context)

CoreMark/MHz measures **average-case throughput (IPC)**, which is *not* this core's
design goal — hard determinism / WCET analysability is. The ~2.0 reflects exactly
those trade-offs:
- **No branch prediction** + decoupled-fetch refetch → ~3-cycle penalty on every
  taken branch (`P_REDIR`). CoreMark's list-traversal/state-machine inner loops are
  branch-dense, so this dominates.
- **2-cycle load-use** (`P_LOADUSE = 2`) — CoreMark chases pointers, so this is
  visible. The `CORE_PERF` 1-cycle load-use scores higher (see above).
- **Single-outstanding data bus**, one rising-edge strobe per access (the LMB /
  MicroBlaze-V contract, `microarchitecture.md` §9): *consecutive* loads/stores take
  a fixed 1-cycle gap. No caches, but 1-cycle BRAM → no miss penalty.

## Comparison points (published)

**Caveat first:** cores explicitly designed for hard determinism / WCET — Patmos
(T-CREST), FlexPRET, JOP, MERASA — almost never publish CoreMark/MHz. That
community benchmarks *worst-case* execution time (Mälardalen WCET, TACLeBench)
and reports bound-tightness, not average-case throughput. Patmos's paper only
states qualitatively that its pipeline is "in the same range as comparable
processors that are not optimized for time predictability" — no number to cite.
So a clean apples-to-apples against a peer WCET core **does not exist in the
literature**; the right axis for a true peer comparison is WCET tightness on
TACLeBench, which favours this design.

The meaningful set that *does* publish CoreMark/MHz is the cacheless in-order
RISC-V cores (deterministic in practice). Our 1.949 / 2.074 reads against them as:

| Core | CoreMark/MHz | Determinism-relevant notes |
|---|---:|---|
| PicoRV32 | ~0.3–0.5 | CPI ≈ 4, multicycle; truly deterministic |
| Piccolo / Flute | ~1.0 | in-order, no prediction |
| VexRiscv (small) | ~1.2 | full config w/ caches+pred ≈ 1.5 |
| Orca | ~1.4 | in-order |
| **this core (default)** | **1.949** | 5-stage, **no branch prediction**, 2-cycle load-use, one-strobe-per-access LMB, no C |
| **this core (`CORE_PERF`)** | **2.074** | 1-cycle load-use |
| Ibex "small" | 2.36 | 2-stage, **no branch prediction**, RV32IM**C** |
| Taiga | 2.53 | in-order, but speculative/scoreboarded |
| Ibex "maxperf" | 3.13 | adds branch-target ALU + 1-cyc mult — breaks strict determinism |

Commercial reference (ARM/EEMBC): Cortex-M0+ 2.46, Cortex-M3 3.34, Cortex-M4 3.42
(M3/M4 use branch speculation + prefetch, so not WCET-clean); SiFive E31 ≈ 2.73.

**How to read it:** among the genuinely-comparable set (no branch prediction, no
speculation, fixed latency) — PicoRV32, Piccolo/Flute, Ibex-small — we beat every
simple core and sit just under Ibex-small (1.949 vs 2.36; the gap is its shallow
2-stage pipe + C extension). Every core that out-scores us (Ibex-maxperf, Taiga,
Cortex-M4) uses branch prediction or speculation — exactly what the prime
directive forbids. `CORE_PERF` (2.074) recovers part of the load-use gap on a
relaxed clock. **Report the toolchain + flags with any comparison** — CoreMark/MHz
is strongly compiler-sensitive (treat ±0.2 as noise).

Sources: [Heinz et al., *A Catalog and In-Hardware Evaluation of Open-Source
RISC-V Cores*, ReConFig 2019](https://www.esa.informatik.tu-darmstadt.de/assets/publications/materials/2019/heinz_reconfig19.pdf);
[Ibex benchmarks README (lowRISC)](https://github.com/lowRISC/ibex/blob/master/examples/sw/benchmarks/README.md);
[Schoeberl et al., *Patmos: a time-predictable microprocessor*, Real-Time Systems
2018](https://link.springer.com/article/10.1007/s11241-018-9300-4);
[EEMBC CoreMark scores](https://www.eembc.org/coremark/scores.php).

## How it works (no new RTL/SV)

Reuses `tb_top` + `sim_main` + the RISCOF signature-dump. Files here: `core_portme.c`
(`mcycle` timing + `ee_printf`→buffer), `ee_printf_min.c` (integer-only printf, no
soft-float), `start.S`, `link.ld` (flat 256 KiB), `libc.c` (memcpy/memset/…), and
`run_coremark.sh` (builds a 256 KiB-memory sim via `-GIAW=18 -GDAW=18`, compiles
CoreMark, runs, decodes the output buffer). CoreMark source is cloned to
`~/src/coremark` (override with `CM=`). Knobs: `OPT=-O3 ITER=10 make -C sim coremark`.
