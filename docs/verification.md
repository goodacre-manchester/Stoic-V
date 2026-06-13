# Stoic-V Verification — toolchain, suites, commands, gates

This is the concrete, runnable verification plan an autonomous session
executes. Every milestone gate in
[`implementation-backlog.md`](implementation-backlog.md) maps to a target here.

> **Carve-out (mandatory, do not overclaim).** v1 omits precise synchronous
> exceptions and assumes aligned-only access (README Requirements). Therefore the
> misaligned-access, illegal-instruction, and synchronous-cause trap suites of
> riscv-arch-test / RISCOF are **excluded from signoff**, and Spike lock-step
> **excludes misaligned ops** (Spike completes them → divergence). The I / M /
> Zba/Zbb/Zbs instruction suites are fully in scope and are the signoff target.
> Never report "arch-test passes" without stating this carve-out.

---

## 1. Toolchain (pinned in `sim/Makefile` and documented in CLAUDE.md)

| Tool | Use | Notes |
|---|---|---|
| **Verilator** (≥ 5.x) | primary sim + lint, CI | fast; `--binary` or C++ harness |
| **Vivado xsim** | **second-simulator gate** (`make xsim`) | the simulator the host SoC uses; catches Verilator↔xsim semantic divergences Verilator cannot (§4.1) |
| **riscv-gnu-toolchain** | `riscv32-unknown-elf-gcc` | `-march=rv32im_zba_zbb_zbs -mabi=ilp32` |
| **riscv-tests** | rv32ui / rv32um directed ISA tests | tohost/fromhost convention |
| **riscv-arch-test + RISCOF** | architectural conformance | with the carve-out |
| **Spike** (`riscv-isa-sim`) | golden ISS for lock-step | `--isa=rv32im_zba_zbb_zbs`, M-mode |
| **Python 3** | RISCOF, trace diff, hex gen | |

CLAUDE.md records the exact install commands and any pinned versions so a fresh
container can reproduce the environment.

## 2. The bus model — `tb/models/lmb_bram.sv`

A **1-cycle registered** LMB slave for both I and D buses:
- present address + strobe in cycle *n* → assert `*Ready` and drive data in cycle
  *n+1* (registered). Holds the contract exactly.
- modes: (a) fixed 1-cycle, level-ready (default); (b) **back-pressure** (`+dwait=N`
  — `*Ready` low until data ready; the DReady-handshaked core honours it); (c) **edge-
  detect, held-ready** (`+dedge=1`) — a representative host tile slave:
  starts an access on the strobe's **rising edge** and registers the read word there,
  holding `*Ready` while the strobe stays asserted. A core that *held* the strobe
  across back-to-back accesses would re-read the first word (the 2026-06 bug); the
  single-outstanding one-edge-per-access core reads each correctly; (d) **free-running
  registered read** (`+dfree=1`) — the **canonical Xilinx BRAM Port A** (`q <= mem[addr]`
  every cycle; the read tracks the *current address*, not the strobe — exactly a host
  BRAM tile's registered read). Unlike (a)–(c) it does NOT hold a load's word past the next
  access, so it exposes the 2026-06 **store→load** stale read (a load held in WB
  committing the next access's word); the fixed core latches its own load word and
  passes. **(c)/(d) are the representative host slaves; the hold-type default masked
  the store→load bug — run `make lmb-contract` which sweeps all four;** (e) **combinational
  NEGATIVE test** (`COMB_D`) — delivers data same-cycle as the strobe; the harness
  asserts the DUT **fails**, proving the core depends on the registered contract.
- preload: `$readmemh` from the test's `.hex` (built from ELF).

## 3. Test harnesses

### 3.1 `tb/tb_top.sv` (unit)
Instantiates `rv_core` + two `lmb_bram` instances (I and D) + a single
level-sensitive external interrupt from the host (write-1-clear at the host; no
hardware-acknowledge handshake). Detects end-of-test via the riscv-tests
**tohost** write (store to a known DMEM address) → pass if `tohost==1`, fail
otherwise; timeout → fail.

### 3.2 Optional firmware example (`fw/`)
`fw/` is an **optional generic example**, not a signoff gate: a small M-mode
program that boots, takes the single external interrupt, runs an ISR, and returns
from the handler (`mret`). Built with `riscv32-unknown-elf-gcc` and run on
`tb_top`, it demonstrates the M-mode trap/interrupt contract (boot → ISR →
handler return) end-to-end on the core.

## 4. Suites & how to run (Make targets)

| Target | What | Gate for |
|---|---|---|
| `make lint` | Verilator `--lint-only` over `rtl/core` | M0 |
| `make test` | build + run `tb_top` on a named hex | all |
| `make riscv-tests` | build rv32ui (+rv32um at M2) → run each → assert pass | M1/M2 |
| `make archtest` | RISCOF run, **in-scope suites only** (I/M/Zb*) | M3 |
| `make trap-suite` | directed trap/interrupt tests (§5 below) | M4 |
| `make cosim` | Spike lock-step retire-compare (carve-out applied) | M2–M4 |
| `make cosim-fw` | **system-level**: compiled-C firmware vs Spike on the free-running slave (§4.2) | RTL changes |
| `make scoreboard` | **randomized-slave-timing** scoreboard: arch invariance vs Spike under `+drand` seed sweep (§4.3) | bus RTL |
| `make sva` | **assertion-based**: LMB-protocol SVA bound onto `rv_core`, checked in sim (§4.3) | bus RTL |
| `make formal` | **formal proof** of the LMB handshake (yosys-smtbmc + z3, BMC + k-induction) (§4.3) | bus RTL |
| `make crv` | **constrained-random**: hazard-biased random instruction streams vs Spike (§4.4) | any RTL |
| `make dmem-matrix` | **interaction matrix**: MEI swept while a data access is outstanding (`dmem_stall` × {IRQ/branch/muldiv}) on stalling slaves (§5) | bus/IRQ RTL |
| `make determinism` | cycle-trace regression (§6 below) | M5 |
| `make xsim` | **second-simulator gate**: the directed suite under Vivado xsim (§4.1) | RTL changes |
| `make synth` | `vivado -mode batch -source vivado/build.tcl`; assert WNS > 0 at 250 MHz + budget | M6 |
| `make coremark` | CoreMark/MHz, cycle-exact (perf validation — §9) | perf |
| `make embench` | Embench-IoT, cycle-exact + 24/16 fit check (perf validation — §9) | perf |
| `make ci` | `lint riscv-tests archtest trap-suite cosim determinism` | every push |

### 4.1 Second-simulator gate — `make xsim` (Vivado xsim)

Every other functional gate runs on **Verilator only**. Two integrator-reported
defects (the LMB back-to-back stale read and the continuous-`assign` forwarding-
sensitivity gap) lived in the **semantic delta between Verilator and Vivado xsim**
— the simulator the host SoC actually uses. Verilator builds the full read-
dependency graph through called functions, so it computed the correct
youngest-writer forward **regardless of stimulus**: *no Verilator test vector could
catch the forwarding bug.* Running the SAME directed programs under xsim does.

`make xsim` (driver: [`sim/xsim/run_xsim.ps1`](../sim/xsim/run_xsim.ps1), tb:
[`tb/xsim/tb_xsim.sv`](../tb/xsim/tb_xsim.sv)) is **Windows-native** (Vivado, like
`make synth`). It assembles each `tests/*.s` via the WSL riscv toolchain
(`run_tests.py --build-only`), compiles the RTL + `tb_top` + `tb_xsim` once with
`xvlog`/`xelab`, then `xsim` replays each hex — scoring PASS/FAIL on the exact
stdout markers Verilator's `sim_main.cpp` emits (`tb_xsim.sv` is the SV analogue
of that C++ driver). Cycle counts match Verilator exactly (cycle-equivalent
simulators, re-confirming determinism).

Run it (Windows terminal):
```
pwsh sim/xsim/run_xsim.ps1            # all tests/*.s  (WSL builds hex, then xsim)
pwsh sim/xsim/run_xsim.ps1 -NoBuild   # reuse existing sim/build/*.hex
pwsh sim/xsim/run_xsim.ps1 -Tests fwd_matrix,loadbase_fwd
```

**Teeth (measured) — forwarding-sensitivity class.** With the forwarding fix
reverted to the pre-fix `assign` form, **11 of the 18 directed tests FAIL under
xsim** (`csr_ops`, `fwd_matrix`, `hazard_chains`, `loadbase_fwd`, `rv32i_branch`,
`zb_bitmanip`, the `irq_stress`/`isr_backtoback`/`trap_mei` interrupt tests, and
the two stall-coincident additions `fwd_loaduse`/`fwd_stall`) while **all 18 pass
under Verilator** — i.e. Verilator is blind to this bug class and xsim is not. The
manifestation is **stall-sensitive** (it trips when a forward source updates while
the consumer's `rs` is held steady by a stall — e.g. a load awaiting the bus), so
the load/CSR/branch consumers and the pointer-chase-under-stall cases catch it most
reliably.

**A second divergence class — uninitialized state (`X`).** The gate also caught
the 2026-06 P7.1 escape: `rv_regfile.regs` had no power-up value, so under xsim an
unwritten GPR reads `X` (Verilator and FPGA LUTRAM read 0), and that `X` propagates
into a load base or a `ret`/`jalr` target. `tests/regzero.s` reproduces it (FAILs
under xsim before the fix, passes after `rv_regfile` is given an `initial = 0`,
synthesized as the LUTRAM INIT — timing/area unchanged). `tests/loadgap.s` is the
companion bus-generality regression (`load; ALU; load` on the edge slave), which
ruled out a residual back-to-back capture bug in the same report.

**Run `make xsim` on any change to forwarding, hazard, bus, or register-file RTL**
before pushing — it is the catch-net for the Verilator↔xsim semantic divergences
(stale forwards, `X` from uninitialized state) that Verilator cannot see.

### 4.2 System-level lock-step — `make cosim-fw` (compiled C vs Spike on the realistic slave)

The directed suite is hand-written asm on a benign default BFM. The 2026-06 integrator
escapes (LMB back-to-back, store→load) lived instead in **real compiled-code patterns
on real BRAM** — function epilogues, stack spill/restore, back-to-back memory, pointer
chases. `make cosim-fw` ([`sim/cosim-fw/`](../sim/cosim-fw/)) closes that gap: it
compiles C workloads with `gcc -O0/-O2/-O3` (three codegen shapes per workload — the
same axis the P7.1 *refactor* changed), runs them on the core against the **canonical
free-running registered BRAM** (`+dfree` — Xilinx Port A, `data_rd_q <= mem[addr]`),
and lock-steps **every committed GPR write** against Spike (`--log-commits`, reusing
`cosim_compare.py`). Workloads are pure compute + memory (no MMIO), so Spike is the
golden architectural model.

Current: **12/12 workloads** (`callchain`/`memops`/`ptrchase`/`sortsum` × 3 opt levels)
match Spike on `+dfree` — up to **22 k retires** validated per run. **Teeth:** with the
store→load fix reverted, `callchain` (all opts), `memops`, and others **DIVERGE** —
i.e. this harness catches P7.1 *organically from compiled C*, no hand-written
reproducer needed. Local (WSL: gcc + Spike); part of `make ci-full`.

### 4.3 Adversarial / assertion-based / formal verification of the bus

The bus protocol is the recurring escape site, so it is verified three ways — random,
assertion-based, and formal:

- **`make scoreboard`** ([`sim/scoreboard/`](../sim/scoreboard/)) — the systematic
  catch-all. The data bus is driven by a **randomized COMPLIANT slave** (`+drand=<seed>`
  in `lmb_bram.sv`: per access, randomly free-running-1-cycle (`+dfree`, exposes the
  store→load class) or latched-with-N-waits (`+dwait`)), and the core's architectural
  result must be **invariant** to the timing — lock-stepped vs Spike across a seed
  sweep. The compliance rule the first cut got wrong: a *free-running* read is only
  legal at 1-cycle latency (the core presents the address for one cycle then advances);
  wait-state latency lives on the *latched* variant. **128/128** (workload × opt ×
  seed) invariant on the current core; **teeth:** with the store→load fix reverted,
  **67/80 diverge** — the random timing reproduces the class with no reproducer.

- **`make sva`** ([`sim/sva/`](../sim/sva/), [`tb/sva/rv_lmb_sva.sv`](../tb/sva/rv_lmb_sva.sv))
  — concurrent SVA properties (single-outstanding, one-strobe-per-access, strobe
  sequencing, in-flight-until-ack) **bound onto the actual `rv_core`** and checked in
  simulation (`verilator --assert`) across the suite under default + randomized timing.
  **84 runs, 0 assertion failures.**

- **`make formal`** ([`sim/formal/`](../sim/formal/)) — a **machine-checked proof** of
  the LMB handshake. The handshake FSM is extracted verbatim from `rv_core` into
  [`rv_lmb_formal.sv`](../sim/formal/rv_lmb_formal.sv) and proven with **yosys-smtbmc +
  z3**: BMC (25 steps) **and k-INDUCTION** → the protocol invariants (P1–P7) hold for
  **all reachable states, unbounded**. Teeth: breaking the FSM yields a counterexample.
  **Scope (honest):** this proves the *bus-handshake protocol* — the part that kept
  breaking — not whole-core ISA correctness (that is `riscv-formal` / an RVFI wrapper,
  a separate larger effort). The `sva` bind checks the same properties on the *real*
  core, cross-checking the extraction.

All three are local (WSL; `formal` also needs `yosys`/`z3`); part of `make ci-full`.

### 4.4 Constrained-random verification — `make crv` (random instruction streams vs Spike)

Hand-written tests catch the bugs you think of; **constrained-random** catches the ones
you don't. `make crv` ([`sim/crv/`](../sim/crv/), generator
[`gen_rand.py`](../sim/crv/gen_rand.py)) is a focused **instruction-sequence generator**
— the same methodology as Google's **riscv-dv**, on the open toolchain (riscv-dv's core
generator is SV/UVM and needs a commercial constraint solver; this delivers the
equivalent with Python + Spike). It emits deterministic, self-terminating
RV32IM_zba_zbb_zbs_zicsr programs whose mix is biased **hard toward pipeline hazards**
— back-to-back RAW dependencies (forwarding stress), load-to-use, store-then-load,
mul/div-to-use, branches on freshly-computed operands, **CSR read-modify-write** — and
lock-steps each against Spike (free-running slave). Programs are memory-safe (reserved
base + zeroed scratch + aligned offsets) and branch-bounded, so Spike is the golden
model; a failure is one seed, trivially reproduced.

**Result: 200/200** random hazard-biased programs (400 instr each) match Spike — the
**datapath, forwarding, hazard, and CSR logic are robust across thousands of random
instructions**. **Teeth:** reverting the store→load fix makes random programs diverge.

**CRV found a real bug — the stall-coincident CSR-RMW divergence (2026-06, FIXED).**
The CSR coverage initially surfaced a core-vs-Spike divergence on `mscratch`: a
`csrr* rd, mscratch, rs` whose `rd` read-back was the NEW value instead of the
architectural OLD value (13/200 programs diverged; the simple forward case always
passed — [`tests/csr_hazard.s`](../tests/csr_hazard.s)). Root cause: the CSR write
commits in EX, but when the CSR instruction is **frozen in EX by a `dmem_stall`** (an
older load/store in the single-outstanding gap — the CRV seed-4 `sh; lhu; csrrw` shape),
the ungated `csr_we` stayed asserted across the freeze, so the write committed on the
first stalled cycle and `csr_rdata` (→ `rd` via `m_result`) was already modified by the
time the instruction advanced. **Fix (`rv_core.sv`): gate `csr_we` with `~dmem_stall`**
so the write commits exactly once, on the cycle the instruction advances out of EX (the
same edge `m_result` latches the still-OLD `csr_rdata`). Regression
[`tests/csr_dmem_hazard.s`](../tests/csr_dmem_hazard.s) FAILs pre-fix under **both
Verilator and xsim**, PASSes post-fix; golden 286 unchanged; synth WNS +0.182 ns. CSR
ops are now **in the default random mix** (`CRV_CSR=0` to drop them) and **CRV is
200/200 with CSR included**.

## 5. Trap / interrupt directed tests (M4)

Each is a small asm program run on `tb_top` with the IRQ driver:
1. **MEI entry**: raise `Interrupt` with `MIE&MEIE` set → assert vector to
   `mtvec.BASE`, `mcause==0x8000_000B`, `mepc==interrupted PC`.
2. **`mret` restore**: ISR clears source (W1C model), `mret` → assert `MIE`
   restored from `MPIE`, execution resumes at `mepc`.
3. **Level re-trap**: keep `Interrupt` high through `mret` → assert it re-traps.
4. **No spurious re-fire**: clear source mid-handler → assert no re-trap after
   `mret`.
5. **Masked**: `MIE=0` or `MEIE=0` with line high → assert *no* trap; pending
   visible in `mip.MEIP`; trap fires when unmasked.
6. **`wfi`**: execute `wfi` with line low → core idles (no trap, no progress);
   raise line → wakes and traps. Proves `wfi` is legal (README, trap model).
7. **MIE/MPIE/MPP stack**: assert entry sets `MPIE←MIE,MIE←0,MPP←M`.

## 6. Determinism regression (M5 — the determinism acceptance gate)

The single most important test. For a fixed instruction stream (a mix incl.
loads/stores, taken/untaken branches, `mul`, `div` with diverse operands):
- run it **N times with different data** (different register/memory inputs,
  including div edge cases: 0, INT_MIN/-1, large/small);
- capture, per run: **total cycle count** and the **per-cycle I-bus and D-bus
  trace** (`{addr, I_AS/D_AS, strobes}`);
- **assert byte-identical** cycle count and bus traces across all N runs.

Any divergence = data-dependent timing = **fail** (most likely an early-
terminating divider or a data-dependent stall). Golden cycle count is recorded
alongside the WCET constants in `microarchitecture.md` §4.

## 7. Lock-step co-simulation (M2–M4)

Run Spike (`--isa=rv32im_zba_zbb_zbs`, M-mode, same reset vector) with commit
logging; run the DUT producing a retire trace `{pc, rd, wdata, csr writes}`.
Compare per-retire. **Exclude** misaligned accesses and synchronous-exception
behaviour (carve-out). Divergence pinpoints the failing instruction.

## 8. CI

`make ci` is the per-push gate (lint + riscv-tests + in-scope arch-test + trap
suite + cosim + determinism). Its **determinism cycle-count check is also the
per-push performance-regression gate** (§9). `make synth` (M6) and the perf
suites (§9) are heavier and run on demand / nightly. If a SessionStart hook is
configured for web sessions, it should ensure the toolchain is present and
`make lint` + `make test` run (see the `session-start-hook` skill). All gates
return non-zero on failure so an autonomous session can detect pass/fail
programmatically.

## 9. Performance benchmarking & CI perf regression

Performance is validated **cycle-exact**, not estimated. The core has no caches,
no speculation, and deterministic registered-1-cycle memory, and the testbench
models that LMB contract exactly — so **the Verilator cycle count equals the
silicon cycle count, bit-for-bit.** There is no memory-hierarchy modelling gap;
the scores are exact for the RTL.

### Suites (perf validation)

`make coremark` (EEMBC CoreMark) and `make embench` (Embench-IoT, 17 kernels) are
cycle-exact; CoreMark/MHz and the Embench geomean (ref Arm Cortex-M4 = 1.0) are
**frequency-independent** (pure IPC). Results for **all three build configs**:

| Config | load-use | CoreMark/MHz | Embench (geomean) | determinism |
|---|---|---:|---:|---|
| **default** (`P_LOADUSE=2`) | 2-cycle | **1.949** | **0.851** | 286 cyc × 8 |
| `CORE_PERF` (1-cycle load-use) | 1-cycle | 2.074 (+6 %) | 0.874 (+3 %) | 286 cyc × 8 |

These are the figures for the real LMB contract (§9): a single-outstanding data bus
that drives one rising-edge strobe per access, so **consecutive** loads/stores take a
1-cycle gap (the rising edge) — exactly like MicroBlaze-V. The gap costs a few percent
(CoreMark 2.02 → 1.949, −3.6 %; Embench 0.91 → 0.851, −6.5 %) — the price of correct
edge-detect-slave compatibility. Toolchain: CoreMark gcc 13.2 `-O3`; Embench
gcc 15.2 `-O2` (**cite the toolchain + flags with any comparison** — both are
compiler-sensitive). Absolute CoreMark ≈ 487 @ 250 MHz, ≈ 1559 @ ~800 MHz (22 nm).
All 17 Embench kernels fit the 24/16 KiB budget. Build a non-default config:
`DEFS=+define+CORE_PERF make -C sim coremark`.
Per-harness detail + the published deterministic-core
comparison band: [`../sim/coremark/README.md`](../sim/coremark/README.md) and
[`../sim/embench/README.md`](../sim/embench/README.md).

Both are self-checking: CoreMark validates its seedcrc (`0xe9f5`, "Correct
operation validated"); Embench runs `verify_benchmark` per kernel. CoreMark/MHz
and the Embench score are **frequency-independent** (pure IPC), so they hold for
both the 250 MHz FPGA and the ~800 MHz 22 nm ASIC realisation — absolute
throughput = score × Fmax. Per-kernel tables, the toolchain (the kernels need the
xPack newlib gcc, separate from the gate toolchain), and the cross-microarchitecture
comparison band are in [`../sim/coremark/README.md`](../sim/coremark/README.md)
and [`../sim/embench/README.md`](../sim/embench/README.md).

### CI perf regression

The **per-push perf-regression gate is `make determinism`** (inside `make ci`).
It asserts a **byte-identical golden cycle count (286 cycles × 8 datasets)** for a
fixed instruction stream. Any change that alters IPC — a forwarding/stall/latency
edit, a pipeline change, an accidental early-out — changes that cycle count and
**fails the gate deterministically**, with no benchmark run required. This is a
tighter perf guard than a CoreMark threshold: it catches a *single-cycle* change
anywhere in the corpus, not just aggregate score drift. When a perf change is
intentional, the golden count is updated in `microarchitecture.md` §4 in the same
commit (e.g. a `P_LOADUSE` or `MUL_LAT` change), so the gate stays exact.

`make coremark` / `make embench` are the **absolute** perf validation. They are
heavier (WSL + the benchmark toolchain) and run **on-demand / nightly**, not
per-push; cite the toolchain + flags with any score (both metrics are
compiler-sensitive). A regression there points back to a cycle-count change the
determinism gate will already have localised.
