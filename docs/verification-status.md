# Stoic-V Verification Status

Living record of **what has been verified, how, and what remains** — the
evidence behind the quality of the core. Pairs with `verification.md` (the
toolchain/how-to) and `implementation-backlog.md` (the task list). Conformance
results assume the §10.3 carve-out (see `README.md` / `local-resume.md`).

Toolchain (local, WSL Ubuntu-24.04): Verilator 5.020, Spike 1.1.1-dev,
RISCOF 1.25.3, riscv-arch-test `old-framework-3.x`, riscv-tests, riscv64
GCC 13.2. All gates below are run with `make -C sim <target>` in WSL.

**Full regression — all green:** `lint` ✓ · `test` 21/21 · `determinism`
8×286 · `archtest` 75/75 · `riscv-tests` 48/48 · `cosim` 48/48 · **`cosim-fw` 12/12**
(compiled C vs Spike on the free-running slave) · **`scoreboard` 128/128** (arch
invariance under randomized compliant slave timing) · **`sva`** (LMB-protocol
assertions, 84 runs clean) · **`formal`** (LMB handshake PROVEN — BMC + k-induction) ·
**`crv` 200/200** (constrained-random hazard-biased programs vs Spike, **incl. CSR RMW**) ·
`lmb-contract` verified (level/edge-detect/**free-running**/back-pressure; incl.
store→load) · `irq-stress` 99/99 · `dmem-matrix` 1410/1410 (`dmem_stall` ×
{IRQ/branch/muldiv}) · `wcet` (latency constants + mul/div data-independence) ·
`coverage` 89.8% core · `xsim` 21/21
(second-simulator gate, Vivado xsim — §11). The determinism golden cycle is
**286 cycles** (data-independent).

**LMB data-bus handshake (2026-06).** The data bus is a single-outstanding handshake
that drives **one rising-edge address strobe per access** and honours `DReady`,
fixing an in-context bug where back-to-back ISR loads read stale data (the
host slave registers the read word on the strobe's rising edge; the old core held
the strobe, so only the first access edged). See §4. Golden re-baselined 285→286;
perf below reflects the per-access gap.

**IP-readiness — synchronous reset throughout** (Xilinx-preferred FPGA style;
clears Vivado `Synth 8-7137` + Verilator `SYNCASYNCNET`, and lets the multiply
pack into the DSP48E2 MREG/PREG). Reset style is a placement/packing concern
only, not a functional one: `lint` clean, `determinism` 8×286, `riscv-tests`
48/48, `cosim` 48/48, `archtest` 75/75 all hold under it. Hand-off to the
integrator is documented in [`ip-delivery.md`](ip-delivery.md).

**Muldiv-result forward register** (in-context 250 MHz, dense host placement): the mul/div
result is forwarded from a dedicated `dont_touch` register (`wmd`) off the
combinational EX-forward→ALU loop, +1 cycle only when a mul/div feeds the
immediately-next dependent (`P_MDUSE`). Re-verified behaviour-neutral and correct:
`lint` (both configs) ✓, `determinism` 8×286 (the muldiv adjacency is absent from
the determinism stream), `riscv-tests` 48/48, `cosim` 48/48 (lockstep retire-compare
confirms the registered muldiv forward), `archtest` 75/75; CoreMark **1.949** and
Embench **0.851** both **CRC-validated** (the mul-heavy benchmarks exercise the new
path).

## Summary

| # | Area | Status | Evidence (gate) |
|---|---|---|---|
| 1 | ISA functional correctness (I/M/Zba/Zbb/Zbs) | ✅ strong | `archtest` 75/75, `riscv-tests` 48/48, `cosim` 48/48 |
| 2 | Architectural equivalence to Spike (per-retire) | ✅ strong | `cosim` 48/48 (riscv-tests) + **`cosim-fw` 12/12** (compiled-C firmware `-O0/-O2/-O3` on the free-running BRAM) GPR-write streams identical |
| 3 | Determinism / WCET (prime directive) | ✅ strong | `determinism` 8×286 + **`wcet`** (§13) — per-op latency constants pinned vs §4; mul/div latency **operand-invariant** |
| 4 | LMB bus timing contract | ✅ verified **3 ways** | `lmb-contract` (modes) + `scoreboard` 128/128 (randomized timing, arch-invariant vs Spike) + `sva` (assertions on `rv_core`) + **`formal`** (handshake PROVEN: BMC + k-induction) — §4 |
| 5 | Interrupt / trap path | ✅ strong | `trap-suite` + `irq-stress` 99/99 + **`dmem-matrix` 1410/1410** (`dmem_stall` × {IRQ/branch/muldiv}) |
| 6 | CSR / Zicsr semantics | ✅ directed | `csr_ops.s` (19 checks); no official privilege suite (carved out) |
| 7 | RTL code coverage | ✅ measured | `make coverage` — 89.8% core lines (datapath ~98–100%); gaps explained |
| 8 | Precise synchronous exceptions | ⛔ out of scope (v1 carve-out) | by design — documented limitation |
| 9 | Performance (cycle-exact) | ✅ measured | default CoreMark **1.949** / Embench **0.851** (CRC-validated); `CORE_PERF` 2.074 / 0.874 — both configs in `verification.md` §9 |
| 10 | Synthesis / timing (250 MHz OOC) | ✅ measured | `make synth` — setup **WNS +0.167 ns** and hold **WHS +0.048 ns** @ 250 MHz OOC, within budget (**2855 LUT / 1068 FF** / 4 DSP / 0 BRAM). OOC-preliminary; final closure is the integrator's in-context P&R (`docs/known-limitations.md` §3) |
| 11 | Simulator portability (Verilator **+ Vivado xsim**) | ✅ verified | `make xsim` — directed suite **21/21** under xsim, cycle-identical to Verilator; catches the Verilator↔xsim divergence class (§11) |

Legend: ✅ strong/verified · 🟡 partial/improving · ⛔ out of scope or blocked.

---

## 1–3. ISA correctness, Spike equivalence, determinism

- **`make archtest`** — official RISCOF vs Spike, **75/75** (I=38, M=8,
  Zba/Zbb/Zbs=29). Byte-identical signatures incl. PC-relative auipc/jal/jalr.
- **`make riscv-tests`** — Berkeley rv32ui+rv32um, **48/48** self-checking.
- **`make cosim`** — Spike `--log-commits` lock-step, **48/48**; every committed
  write to x1..x31 matches Spike instruction-by-instruction (~10k retires).
- **`make cosim-fw`** — **system-level** lock-step: real C firmware compiled `-O0/-O2/
  -O3` (epilogue spill/restore, struct copies, pointer chases, in-place sort), run on
  the **canonical free-running BRAM** (`+dfree`) and compared GPR-write-for-GPR-write
  against Spike. **12/12** workloads match (up to ~22 k retires each). Closes the gap
  behind the integrator escapes — real compiled-code patterns on real BRAM, the
  surface hand-written asm + the benign default BFM missed. **Catches the store→load
  class organically:** with that fix reverted, `callchain`/`memops`/… diverge from
  Spike here with no hand-written reproducer. See [`sim/cosim-fw/`](../sim/cosim-fw/).
- **`make crv`** — **constrained-random verification**: a hazard-biased instruction-
  sequence generator ([`sim/crv/gen_rand.py`](../sim/crv/gen_rand.py), the riscv-dv
  methodology on the open toolchain) emits random RV32IM_zba_zbb_zbs_zicsr programs (RAW
  chains, load-to-use, store-then-load, mul/div-to-use, branches on fresh operands, **CSR
  RMW**) and lock-steps each vs Spike. **200/200** random programs match — the
  **datapath, forwarding, hazard, and CSR logic are robust across thousands of random
  instructions**. **CRV found a real bug (now fixed):** the CSR coverage surfaced a
  core-vs-Spike divergence on `mscratch` under back-to-back CSR RMW — `rd` captured the
  NEW value, not the OLD — when a CSR instruction was frozen in EX by a `dmem_stall`
  (13/200 diverged; the simple forward case always passed, `tests/csr_hazard.s`). Fixed
  by gating `csr_we` with `~dmem_stall` (`rv_core.sv`); regression
  `tests/csr_dmem_hazard.s` (FAILs pre-fix under Verilator AND xsim). CSR is now **in
  the default mix** (`CRV_CSR=0` to drop it); CRV is 200/200 with CSR included. See
  [`sim/crv/`](../sim/crv/) and §12.
- **`make determinism`** — **8 datasets, all 286 cycles**, data-independent. Exercises
  mul{,h,hsu,hu}, div/divu/rem/remu (incl. div-by-0, INT_MIN/-1), and the count
  ops clz/ctz/cpop on both operands across all-zero/all-ones/alternating-bit
  inputs. Backed by code review: `rv_bitmanip` is fully combinational (count ops
  are fixed 32-iteration unrolled), `rv_muldiv` runs a constant 32-step divide +
  fixed-latency multiply (MUL_LAT=4, DSP48E2 MREG+PREG) for **all** operands —
  latency depends only on the operation, never operand values.

## 4. LMB bus timing contract  ·  `make lmb-contract`

**Contract (verified):** the data bus is a **single-outstanding handshake** that
drives **one rising-edge address strobe per access** (`D_AS`/`Read_Strobe`/
`Write_Strobe` pulse, never held across accesses) and **honours `DReady`** before
completing. It therefore slots in against any FIXED-latency registered slave —
level-ready, **edge-detect** (a representative host tile), or **back-pressure** — and
matches MicroBlaze-V's own LMB. A combinational/zero-wait response (data the same
cycle as the strobe) still corrupts execution. Determinism holds for any fixed
latency (timing is access-pattern + slave-latency dependent, never data-dependent).

**2026-06 bug + fix.** Binding `mbv` in-context, an ISR doing one-shot back-to-back
loads read stale data. The host data slave (an edge-detect tile,
`rd_start = d_re & ~d_re_q`) starts an access — and **registers the read word** — on
the strobe's rising edge, holding `DReady` while the strobe stays asserted. The old
core held `Read_Strobe` high across back-to-back loads (`o_rstrobe = m_valid &
is_load`), so only the first access produced a rising edge and every later load
re-read the first word. This also violated the core's own documented §9 requirement
("`D_AS` must be a 1-cycle pulse per access — do not hold it across the wait"). Fix:
`rv_core.sv` now tracks one outstanding data access (`d_inflight`), strobes only when
idle (`d_issue = mem_req & ~d_inflight`), and freezes the pipeline (`dmem_stall`) +
suppresses fetch issue while an access is unacked — so consecutive accesses get a
1-cycle gap (a fresh rising edge), exactly like MB-V. Behaviour-neutral on the
1-cycle level slave except the consecutive-access gap; golden re-baselined 285→286.

`make lmb-contract` makes this a regression: `tests/backtoback.s` (a `store; load;
load; load` self-check) and `tests/storeload.s` (a `store; lw ra; …; ret` epilogue)
run against every slave mode in `tb/models/lmb_bram.sv`, plus the riscv-tests
baseline and the `COMB_D` negative:

| Slave behaviour | Expectation | Result |
|---|---|---|
| registered 1-cycle, level-ready (baseline) | PASS | ✅ b2b + add/lw pass |
| registered 1-cycle, **edge-detect + held-ready** (`+dedge`, a host tile) | PASS | ✅ b2b + store→load pass (fails pre-handshake-fix) |
| registered 1-cycle, **free-running read** (`+dfree`, canonical BRAM Port A) | PASS | ✅ b2b + **store→load** pass (**fails pre-store→load-fix**) |
| registered multi-cycle, **back-pressure** (`+dwait`) | PASS | ✅ b2b + store→load + lw pass (DReady-handshaked) |
| edge-detect **+** back-pressure | PASS | ✅ b2b passes |
| combinational / zero-wait (`COMB_D`) | corrupt/hang → FAIL | ✅ fails (NEGATIVE) |

**2026-06 store→load fix (P7.1).** The `+dfree` mode is the canonical Xilinx BRAM
Port A read (`data_rd_q <= mem[addr]` every cycle — exactly `tile.sv`'s data path):
the read tracks the **current address**, not the strobe. On it, a load held in WB
across the single-outstanding gap committed the **next** access's word, because the
core read the **live** bus (`rf_wd = extend(i_dread)`) at the delayed commit cycle —
the store→load stale read (a `ret` whose `ra` was restored from the next
stack slot → PC wedge). Fix: the core now **latches the load's own word the cycle
its access acks** (`d_complete & w_is_load`) and commits the latched value
(`rv_core.sv`, `ld_word`). It is a **real functional bug** — `storeload.s` FAILs
pre-fix under **both Verilator and xsim** on `+dfree`; the earlier hold-type slave
models (level/edge/back-pressure) masked it by holding the read word. All slave
modes pass post-fix; the whole 19-test suite also passes under `+dfree`.
Determinism-neutral (golden 286 unchanged). **Synth re-validated** (ZCU102 -2 OOC):
**WNS +0.167 ns (timing gate PASS)**; area **2855 LUT / 1068 FF / 4 DSP48E2 / 0 BRAM**
— the `ld_word` latch + commit mux add **+76 LUT / +29 FF** over the pre-fix
2779/1039 (the load path does not bind; the EX forward→ALU loop still does).

**Integration requirement:** the host's LMB slave must present a registered response
(data no earlier than the cycle after the strobe). Level, **edge-detect**,
**free-running** (canonical BRAM), and fixed **back-pressure** are all supported; a
combinational (zero-latency) slave is not.

**Bus verified three ways (2026-06).** After the recurring bus escapes, the protocol
is now verified randomly, by assertion, and formally (`verification.md` §4.3):
- **`make scoreboard`** — a **randomized COMPLIANT slave** (`+drand`: per access,
  free-running-1-cycle or latched-with-N-waits) with the architectural result checked
  **invariant** vs Spike across a seed sweep. **128/128** invariant on the current
  core; **67/80 diverge** with the store→load fix reverted (catches the class without a
  reproducer).
- **`make sva`** — LMB-protocol concurrent assertions **bound onto `rv_core`**, checked
  in simulation across the suite (**84 runs, 0 failures**).
- **`make formal`** — the handshake FSM (extracted verbatim from `rv_core`) **PROVEN**
  with yosys-smtbmc + z3: BMC **+ k-induction** (unbounded) for P1–P7 (single-
  outstanding, one-strobe-per-access, in-flight-until-ack, …). Teeth: a broken FSM
  yields a counterexample. Scope: the **bus-handshake protocol**, not whole-core ISA
  (that is `riscv-formal`).

## 5. Interrupt / trap path  ·  `make irq-stress` + `make dmem-matrix`

- **Directed** (`make trap-suite` / in `make test`): `trap_mei` (enable → MEI
  trap → `mcause`=0x8000000B → `mret` → level deassert) and `trap_wfi`.
- **`make irq-stress`** — fires the MEI at **every cycle 12..110** (99 points)
  around a computation containing mul, div, a load-use hazard, and a branch
  loop. A transparent ISR (writes only `s11`) wraps it; each run must PASS,
  which requires both that the interrupt is actually **taken** (the test's
  wait-spin turns a missed interrupt into a TIMEOUT) and that the result is
  **unchanged** (CHECK_EQ). **99/99 pass** → interrupt entry is correct at all
  pipeline positions (incl. deferral while a mul/div is in flight) and `mret`
  resumes correctly. Verifies `mip.MEIP` is level-sensitive (no edge-latch:
  a too-short pulse mid-divide is legitimately not latched — the test holds the
  line high past the divide latency to guarantee capture).
- **`make dmem-matrix`** — the **`dmem_stall` × {IRQ / branch / muldiv}** interaction
  gate (`sim/dmem-matrix/`). irq-stress sweeps the MEI on the *non-stalling* slave; this
  crosses the same sweep with an **outstanding data access** (the one combination not
  previously built). The kernel keeps a load/store in the single-outstanding gap while a
  taken branch / an independent counting mul/div is in flight, and the MEI is injected at
  every cycle on `default / +dwait=1/2/3 / +dfree / +dedge`. The result (s1=638) and the
  transparent ISR must be invariant to both the injection cycle and the slave timing.
  **1410/1410** (6 timings × 235 points). Confirms entry/redirect/`mret` defer correctly
  until the access retires in order (`take_irq & ~dmem_stall`; the redirect block defers
  control-flow during `dmem_stall`; the multiplier freezes on `.hold(dmem_stall)`).
  **Teeth:** removing the `dmem_stall` IRQ guards FAILs it on `+dwait` (CHECK_EQ
  corruption + TIMEOUTs) — a regression irq-stress (non-stalling) does not catch.
- **Entry-latency determinism** (`LAT_IRQ_WORST`): bounded by construction —
  entry is deferred only for an in-flight mul/div (both fixed-latency), so the
  worst case is fixed, not operand-dependent (microarchitecture.md §4). A
  cycle-exact latency-vs-injection measurement is a possible future addition.

## 6. CSR / Zicsr semantics  ·  `tests/csr_ops.s` (in `make test`)

19 directed checks against the implemented CSR file (`rv_csr.sv`): CSRRW returns
old / writes new; CSRRS/CSRRC OR/AND-NOT; the immediate forms CSRRWI/SI/CI; a
CSRRS with an `x0` source does not write; WARL masking — `mstatus` MIE/MPIE
writable with MPP read-only `11`, `mtvec` low-2-bits forced 0 (direct mode),
`mepc` bit0 forced 0, `mie` only MEIE writable; read-only `misa`
(0x40001100 = MXL1+I+M), `mhartid`, `mip`; and `minstret`/`mcycle` monotonic.
No official Zicsr/privilege arch-test suite is run (it lives in the carved-out
privilege group). Trap-side CSR behaviour (mepc/mcause/mstatus on entry, `mret`
restore) is covered by `trap_mei` + `irq-stress`.

## 7. RTL code coverage  ·  `make coverage`

`verilator --coverage` over the full corpus (directed suite on the unit build;
riscv-tests rv32ui+rv32um **and** arch-test I/M/B on the arch build — 131 runs),
merged with `verilator_coverage`. **Core line coverage: 627/698 = 89.8%.**

| file | line cov | note |
|---|---|---|
| rv_alu.sv | 100% | |
| rv_regfile.sv | 100% | |
| rv_muldiv.sv | 98.8% | |
| rv_bitmanip.sv | 98.3% | |
| rv_core.sv | 93.2% | a few rare stall/forward edge branches |
| rv_csr.sv | 88.3% | some counter-high writes / unreached read-mux defaults |
| rv_decode.sv | 86.8% | remainder = `default: c.legal=0` **illegal-instruction** branches — unreachable by valid code (the §10.3 carve-out) |
| mbv.sv | 47.4% | debug-port tie-offs + `_unused` aggregation — structural, no logic |

The datapath (ALU, regfile, mul/div, bitmanip) is ~98–100%. The headline gaps
are *explained, not blind spots*: the decode shortfall is the illegal-instruction
defaults that a conformant, valid-only corpus cannot reach (closing them needs
illegal-instruction trapping — out of scope for v1), and `mbv`'s low number is
the functionally-omitted debug ports. Annotated sources land in
`sim/coverage/work/annotated/` (`%000000` marks an uncovered point).

## 8. Precise synchronous exceptions — out of scope (v1)

By the §10.3 carve-out, v1 omits precise synchronous exceptions: ecall/ebreak/
illegal-instruction/misaligned do **not** trap; an unrecognised instruction
decodes to a defined NOP (`rv_decode.sv` ~L264). Consequence: a stray illegal
instruction is silently ignored rather than trapping — acceptable for the
controlled firmware target, but means the misaligned/illegal/sync-cause arch-test
and rv32mi suites are out of signoff. Closing this is a localised
`rv_csr`/`rv_core` change that does not touch the bus contract.

## 11. Simulator portability — Verilator + Vivado xsim  ·  `make xsim`

**Why this gate exists.** Every other functional gate runs on **Verilator only**.
Both 2026-06 integrator-reported defects escaped local signoff because they lived
in the **semantic delta between Verilator and Vivado xsim** (the simulator the
host SoC uses), not in any missing stimulus:

- the **LMB back-to-back** stale read needed an edge-detect slave model *and* a
  back-to-back access pattern we hadn't driven (a stimulus + model gap — closed by
  `+dedge` and `backtoback.s`/`bus_patterns.s`); and
- the **forwarding** continuous-`assign` sensitivity gap was *purely* a simulator-
  semantics gap. Verilator builds the full read-dependency graph through `fwd()`,
  so it computed the correct youngest-writer forward **regardless of stimulus** —
  no Verilator vector could ever catch it. Only re-running the same programs under
  xsim exposes it.

**The gate.** `make xsim` ([`sim/xsim/run_xsim.ps1`](../sim/xsim/run_xsim.ps1) +
[`tb/xsim/tb_xsim.sv`](../tb/xsim/tb_xsim.sv)) runs the directed `tests/*.s` suite
under Vivado xsim (Windows-native, like `make synth`). `tb_xsim.sv` is the SV
analogue of the Verilator C++ driver (`sim_main.cpp`): same clk/reset/irq/timeout
and the same tohost PASS(1)/FAIL stdout markers, so xsim runs are scored
identically. Result: **18/18 PASS under xsim, with cycle counts identical to
Verilator** (the two simulators are cycle-equivalent — independently re-confirming
the determinism premise).

**Teeth (measured).** Reverting the forwarding fix to the pre-fix `assign` form:

| Simulator | Directed suite (18 tests) on the **buggy** RTL |
|---|---|
| Verilator | **18/18 pass** — structurally blind to the bug |
| Vivado xsim | **7/18 pass, 11 FAIL** — `csr_ops`, `fwd_matrix`, `hazard_chains`, `loadbase_fwd`, `rv32i_branch`, `zb_bitmanip`, `irq_stress`, `isr_backtoback`, `trap_mei`, `fwd_loaduse`, `fwd_stall` |

The bug is **stall-sensitive** — it manifests when a forward source updates while
the consumer's `rs` is held steady by a stall (e.g. a load awaiting the bus), so
the load/CSR/branch consumers catch it most reliably; un-stalled M+W overlaps
often re-evaluate at the right moment and pass. This is why a *broad* consumer
surface matters.

**New directed stimulus** (also raises Verilator coverage; run in `make test`):

| Test | Covers |
|---|---|
| [`tests/fwd_matrix.s`](../tests/fwd_matrix.s) | youngest-writer forwarding into ALU(rs1/rs2), load base/AGEN, store data, store base, branch operands, shift amount, MUL operand, CSR source, the x0-no-forward guard, and load-result (load-use) forward |
| [`tests/hazard_chains.s`](../tests/hazard_chains.s) | multi-writer RAW chains, pointer-chase load→load (load result as next load's base), MUL result→consumer and →next MUL operand, div-by-zero / signed INT_MIN÷−1 overflow (deterministic results), forwarded youngest div operand |
| [`tests/bus_patterns.s`](../tests/bus_patterns.s) | back-to-back **sub-word** stores (byte/halfword enables), interleaved RAW chains to one address, store/store/load WAW ordering, byte-overwrite-then-read — all against the `+dedge` edge-detect slave (so the portable `make test`/CI exercise the edge slave too) |
| [`tests/fwd_loaduse.s`](../tests/fwd_loaduse.s) | **load-result (wl-path) forward under the load-use stall** into every consumer: ALU, branch, store-data, store-base (pointer-chase store), MUL operand, CSR source |
| [`tests/fwd_stall.s`](../tests/fwd_stall.s) | the M+W forwarding scenarios run under **bus back-pressure** (`+dwait=2`) — load base, store base, store data, pointer-chase load→load while accesses are held unacked (closest reproduction of the in-context stall) |
| [`tests/loadgap.s`](../tests/loadgap.s) | `load(header) ; <ALU> ; load(payload)` and back-to-back-payload variants on the `+dedge` edge slave — the bus-generality regression that **ruled out** a residual back-to-back capture bug in the P7.1 report |
| [`tests/regzero.s`](../tests/regzero.s) | never-written GPRs read **0** (FPGA-LUTRAM fidelity) and an unwritten reg used as a load base addresses 0, not `X` — the regfile power-up regression |

The two stall-coincident additions (`fwd_loaduse`/`fwd_stall`) both catch the
forwarding-fix-reverted bug under xsim at the **pointer-chase** (a loaded value used
as a base while a stall holds it), a scenario the un-stalled cases miss — confirming
the value of exercising the stall regime explicitly.

**Second divergence class caught — uninitialized state (`X`), the 2026-06 P7.1
escape.** `rv_regfile.regs` had no power-up value, so under xsim an unwritten GPR
reads `X` while Verilator (2-state) and real FPGA LUTRAM read **0**; that `X`
propagates into a load base (→ wrong/0 address) or a `ret`/`jalr` target (→ PC 0)
the moment a library-refactored firmware touches an untouched register. `regzero.s`
**FAILs under xsim before the fix** and passes after `rv_regfile` is given an
`initial = 0` (synthesized as the LUTRAM INIT — no reset port; `make synth`
re-confirmed **WNS +0.070 ns and area 2779 LUT / 1039 FF / 4 DSP / 0 BRAM, identical
to before**). The companion `loadgap.s` proved the bus side of the same report is
*not* a core bug — the `load; ALU; load` shape returns each load's own word on the
edge slave. (Note: this fix defines the **core's** power-up state; an `X` that
originates in *uninitialized memory* — the host's BRAM/aperture model or unzeroed
`.bss` — is the integrator's to define, since real FPGA BRAM configures to 0.)

**When to run.** `make xsim` is a local Windows/Vivado gate (not in cloud CI, which
is the portable Verilator subset). Run it on any change to forwarding, hazard, bus,
or register-file RTL before pushing — it is the catch-net for the simulator-semantic
divergences (stale forwards, `X` from uninitialized state) that Verilator cannot see.

## 12. Stall-coincident CSR-RMW divergence — CRV found it, fixed  ·  `tests/csr_dmem_hazard.s`

**Found by `make crv`.** Once CSR ops were in the random mix, 13/200 hazard-biased
programs diverged from Spike — always a `csrr* rd, mscratch, rs` whose `rd` read-back
was the **NEW** value instead of the architectural **OLD** value (e.g. CRV seed 4,
`...; sh t0,304(gp); lhu a0,1218(gp); csrrw a1,mscratch,s3` — DUT `a1`=new, Spike
`a1`=old). The simple back-to-back CSR forward case always passed
([`tests/csr_hazard.s`](../tests/csr_hazard.s)), which is why hand-written tests and
every other gate missed it — it is **stall-coincident**.

**Root cause.** The CSR read/commit live in EX: `csr_rdata` is combinational from the
current CSR state, `rd` is written from `csr_rdata` (the OLD value), and `csr_we`
commits the new value at the EX clock edge. But when an **older load/store is awaiting
its DReady in the single-outstanding gap, `dmem_stall` freezes the CSR instruction in
EX** while `csr_we` stayed asserted (ungated). The write then committed on the *first*
stalled cycle, so on the cycle the instruction finally advanced, `csr_rdata` (→ `rd`
via `ex_wb_value`/`m_result`) was already the modified value. A `ret` whose `ra` came
from such a CSR-restored value, or any RMW idiom, then diverges. Real bug: reproduces
under **both Verilator and xsim** on the free-running slave.

**Fix.** Gate `csr_we` with `~dmem_stall` (`rv_core.sv`): the write commits **exactly
once**, on the cycle the instruction advances out of EX — the same edge the EX/MEM
register latches `csr_rdata` (still OLD that cycle). `rd` gets OLD, the CSR gets the new
value, atomically. `dmem_stall` is the only thing that holds a CSR in EX (`stall_e`
holds only mul/div; `stall_d` holds ID), so the single gate is sufficient. On a 1-cycle
slave `dmem_stall ≡ 0`, so behaviour and timing are unchanged.

**Evidence.** [`tests/csr_dmem_hazard.s`](../tests/csr_dmem_hazard.s) (store;store;csrrw
/ store;load;csrrw / load;load;csrrs / store;store;csrrc, each on `+dfree`) **FAILs
pre-fix** (test #1) under Verilator AND xsim, **PASSes post-fix**. CSR ops are now in
the default `make crv` mix → **CRV 200/200 with CSR included** (was 13/200 diverged).
Full regression re-run green: directed 21/21, `xsim` 21/21 (csr_dmem_hazard cycle-
identical), determinism 8×286, `cosim` 48/48, `sva` 84 runs, `synth` **WNS +0.182 ns**
(2800 LUT / 1071 FF / 4 DSP / 0 BRAM).

## 13. WCET latency constants + FU data-independence  ·  `make wcet`

The core's value proposition is **static WCET analysability**, so the published
per-instruction latency constants (`microarchitecture.md` §4) must (a) match the RTL and
(b) be **operand-independent** for the variable-latency-risk functional units. `make wcet`
([`sim/wcet/`](../sim/wcet/)) measures this directly: one dependent-op chain
([`wcet_probe.s`](../sim/wcet/wcet_probe.s)) assembled at **K and 2K** ops, with the slope
`(cyc2K − cycK)/K` giving the per-op latency (fixed prologue/fill/drain cancels).

| Op | Measured per-op (dependent) | Reconciles to §4 |
|---|---|---|
| `div` | **37** cycles | DIV_LAT 34 (non-early-terminating, 32 fixed steps) + 3 dependent-issue |
| `mul` | **6** cycles | MUL_LAT 4 (fixed 4-stage DSP MREG/PREG) + 2 dependent-issue/forward |
| load-use | **4** cycles | registered load + 2-cycle load-use (`P_LOADUSE=2`) |
| taken branch | **4** cycles | redirect/refetch penalty (`P_REDIR`) |

**Data-independence (the load-bearing assertion):** the div and mul cycle counts are
**identical** across adversarial operand sets — div `{normal, INT_MIN÷−1, ÷0, 0÷x}`,
mul `{normal, INT_MIN², −1×−1, 0×0}`. An early-terminating or operand-dependent
multiplier/divider would fail immediately — that is the gate's teeth. The per-op numbers
are **pinned baselines**: a latency change fails the gate and must be landed with a
matching `microarchitecture.md` §4 update (like the determinism golden 286). In `ci-full`.
