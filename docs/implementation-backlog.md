# Stoic-V Implementation Backlog — executable task list

This is the **single source of progress truth**. A resuming session:
1. reads [`../CLAUDE.md`](../CLAUDE.md) → this file,
2. picks the **first unchecked `[ ]` task**,
3. implements it,
4. runs the task's **gate** (a `make` target from
   [`verification.md`](verification.md)),
5. checks the box `[x]` **only when the gate is green**, commits, pushes.

Do tasks in order — later milestones assume earlier gates hold. Never check a
box without a green gate. Keep this file and the WCET table
([`microarchitecture.md`](microarchitecture.md) §4) in sync.

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done (gate green) ·
`[!]` blocked (note why inline).

> **Progress (container session):** M0–M5 green via Verilator 5.020 + directed
> self-checking asm tests + the determinism gate. Official riscv-tests/RISCOF/
> Spike and Vivado are **not available in-container** — those items are marked
> `[!]` and must be run in a local session (see `../CLAUDE.md` env notes).
>
> **Progress (local session, WSL):** Spike + RISCOF + riscv-arch-test +
> riscv-tests installed. **Official `make archtest` (RISCOF vs Spike) green
> (75/75)** and **official `make riscv-tests` (Berkeley rv32ui+rv32um) green
> (48/48)**, both with the §10.3 carve-out. See `sim/riscof/`, `sim/riscv-tests/`
> and `docs/local-resume.md`. **`make cosim` (Spike lock-step retire-compare,
> 48/48) is also green** — `sim/cosim/`. All official conformance `[!]` items
> are now closed (with the §10.3 carve-out).

---

## M0 — Repo scaffold  ·  gate: `make lint` clean, everything compiles
- [x] Create dir tree per the repo layout (README / microarchitecture §0) (`rtl/core`, `fw`, `tb`, `tb/models`, `vivado`, `sim`).
- [x] `rtl/core/rv_pkg.sv`: params (`C_BASE_VECTORS`, core id), opcode/funct enums, CSR-addr constants, control-bundle `typedef struct`, WCET localparams (placeholders).
- [x] Port skeletons (empty bodies) for every module in `microarchitecture.md` §8.
- [x] `rtl/core/mbv.sv` — synthesizable top named **`module mbv`** with the **exact port signature** in `microarchitecture.md` §9 (so a host SoC that instantiates a MicroBlaze-V binds it unchanged); wraps `rv_core`, ties debug outputs to 0, ignores debug + `IWAIT/ICE/IUE/DWait/DCE/DUE` inputs.
- [x] `tb/models/lmb_bram.sv`: 1-cycle registered slave (modes: fixed / wait-inject / combinational-NEG), `$readmemh` preload.
- [x] `tb/tb_top.sv`: instantiate core + 2 BRAM models + IRQ driver + tohost end-detect.
- [x] `sim/Makefile`: `lint`, `test` targets; Verilator wired up.
- [x] `vivado/timing.xdc` (4.000 ns) + `vivado/build.tcl` (part `xczu9eg-ffvb1156-2-e`, ZCU102).
- [x] Document toolchain install in CLAUDE.md (versions, commands).

## M1 — RV32I core  ·  gate: `make riscv-tests` (rv32ui) all pass; WCET constants recorded
- [x] `rv_regfile.sv` (2R1W, x0=0, distributed-RAM intent).
- [x] Fetch (PC, redirect mux, I-LMB master, depth-2 FIFO) — integrated in `rv_core.sv` (not a separate file).
- [x] `rv_decode.sv`: full RV32I decode + immediate-gen + control bundle.
- [x] `rv_alu.sv`: add/sub/logic/shift/slt(u).
- [x] `rv_core.sv`: D-LMB master, `Byte_Enable` gen, load lane-select + sign/zero-extend (aligned-only, README (aligned-only access)).
- [x] Hazards/forwarding (registered-copy forward, **load-use 2-bubble** default, redirect ~3) — integrated in `rv_core.sv`.
- [x] `rv_core.sv`: wire the 5-stage datapath; expose LMB v10 + `Interrupt`.
- [x] Bring up via directed tests (`rv32i_basic`, `rv32i_branch`).
- [x] **Official Berkeley `make riscv-tests` (rv32ui) — 40/40 pass** (self-checking via tohost; `ma_data`/`fence_i` skipped per carve-out). Custom M-mode/no-trap env in `sim/riscv-tests/`.
- [x] **Record** `P_LOADUSE`, `P_REDIR`, `CPI_base` in WCET table from sim.
- [x] **`make cosim` — Spike lock-step retire-compare, 48/48 match** (per-committed-GPR-write, rv32ui+rv32um; carve-out excludes ma_data/fence_i). Core emits a retire trace (`w_pc` + WB write via tb_top XMR, `+trace`); `sim/cosim/`.

## M2 — M extension  ·  gate: `make riscv-tests` (rv32um) pass; cosim green
- [x] `rv_muldiv.sv`: fixed-latency multiply (DSP intent, registered I/O).
- [x] `rv_muldiv.sv`: **non-early-terminating** radix-2 divider (div/divu/rem/remu), div-by-0 + INT_MIN/-1 per ISA, constant `DIV_LAT`.
- [x] EX stall/handshake for mul/div; integrate into hazard unit.
- [x] Decode M opcodes.
- [x] **Record** `MUL_LAT`, `DIV_LAT` in WCET table.
- [x] **Official Berkeley `make riscv-tests` (rv32um) — 8/8 pass** (div/divu/mul/mulh/mulhsu/mulhu/rem/remu).

## M3 — Zba/Zbb/Zbs  ·  gate: `make archtest` (Zb* in-scope) pass
- [x] `rv_bitmanip.sv`: Zba (sh1/2/3add), Zbb (andn/orn/xnor, clz/ctz/cpop, min/max(u), sext.b/h, zext.h, rol/ror/rori, orc.b, rev8), Zbs (bclr/bext/binv/bset + imm).
- [x] Extend decode for all Zb* encodings (cross-check vs ISA manual).
- [x] Route bit-manip result into EX mux + forwarding.
- [x] Directed Zb* tests pass (`zb_bitmanip`).
- [x] **Official RISCOF `make archtest` vs Spike — 75/75 pass** (I=38, M=8, Zba/Zbb/Zbs=29), carve-out applied (Zbc `clmul*`, misaligned/illegal/sync-trap suites excluded; see `sim/riscof/`). Toolchain: Spike 1.1.1-dev, RISCOF 1.25.3, riscv-arch-test `old-framework-3.x`, run in WSL.

## M4 — Zicsr + traps  ·  gate: `make trap-suite` + MEI/level/`mret`/`wfi` tests pass
- [x] `rv_csr.sv`: CSR file per `microarchitecture.md` §6 (mstatus/mie/mip/mtvec/mepc/mcause + optional mscratch/mtval/misa/mhartid/counters).
- [x] CSRRW/S/C(+I) semantics; CSR serialisation bubble (`P_CSR`).
- [x] Trap entry (MEI): `mepc/mcause/MPIE/MIE/MPP`, redirect to `mtvec.BASE`.
- [x] `mret`: MIE/MPIE/MPP restore, PC←mepc.
- [x] `mip.MEIP` mirrors synchronised pin (no edge-latch); enable chain.
- [x] `wfi` decode as legal NOP/sleep (idle until IRQ).
- [x] Run all 7 directed trap tests (`verification.md` §5).
- [x] **Record** `P_CSR`, `LAT_IRQ_ENTRY`, derive `LAT_IRQ_WORST`.

## M5 — Determinism  ·  gate: `make determinism` byte-identical across N data sets
- [x] Cycle-trace regression harness (`verification.md` §6); golden cycle count = **286 cyc × 8 datasets** (MUL_LAT=4 DSP48E2 MREG+PREG, P_LOADUSE=2).
- [x] Confirm div/mul **and clz/ctz/cpop** are operand-independent — by construction (combinational / fixed-iteration) and empirically (broadened `determinism` gate).
- [x] **LMB timing-contract NEGATIVE tests** (`make lmb-contract`): a combinational/zero-wait slave makes the tests fail; level/edge-detect/back-pressure registered slaves all pass — proving the single-outstanding, one-rising-edge-strobe-per-access, DReady-handshaked contract (see `docs/verification-status.md` §4) is required on both buses. (Supersedes the earlier mislabelled "wait-injection lockstep-stall / mode b/c" items.)

## Optional — host-side byte-enable behaviour  ·  verified
- [x] **Sub-word stores honour `Byte_Enable`** — directed test drives the data LMB with word + sub-word byte + sub-word half stores; read-back confirms only the addressed lanes change (resolves the the byte-enable decision (§9) risk). **TEST PASSED.** The core drives correct `Byte_Enable`; the host's data slave must honour it.

## Optional — firmware example  ·  boot→ISR→handler-return on `tb_top`  ·  verified
> Optional reference firmware that exercises the M-mode trap/interrupt contract on
> the core in isolation (not a host bring-up). Demonstrates the must-have set the
> integrator's firmware depends on.
- [x] `fw/start.S` + `fw/firmware.c` + `fw/link.ld` build with `riscv64-unknown-elf-gcc -march=rv32im_zba_zbb_zbs_zicsr -mabi=ilp32 -mcmodel=medany -nostartfiles`. Builds the ELF + imem hex.
- [x] **Runs boot→ISR→handler-return** on `tb_top` (the core + BRAM models + a single level-sensitive external interrupt): the firmware boots, idles on `wfi`, takes the injected MEI, the ISR services it and returns via `mret`, then the host-side source is write-1-cleared (IRQ deasserts). **TEST PASSED.** Demonstrates the M-mode trap/interrupt contract (`wfi`/`mret`/level-sensitive `mip.MEIP`/`mtvec`) end-to-end.

## M6 — Synthesis / timing  ·  gate: **WNS > 0 at 250 MHz** + within resource budget  ·  **UNBLOCKED (Vivado present)**
- [x] `vivado/build.tcl` is complete (synth→opt→place→phys_opt→route→reports + WNS gate); default part **`xczu9eg-ffvb1156-2-e` (ZCU102)**. `make synth` target added.
- [x] **Synthesis proven clean** (Vivado 2025.2.1, part licensed): `synth_design` finished **0 errors, 0 critical warnings**; correct primitive inference (DSP48 for the multiplier, LUTRAM for the regfile). Post-route util: **2779 LUT / 1039 FF / 4 DSP48E2 / 0 BRAM** — within §3 budget (multiply PREG packs into the DSP).
- [x] **OOC standalone WNS characterised** (ZCU102 -2; runs 1–5, `timing-and-resources.md §6`): the default 2-cycle config **meets 250 MHz OOC** (WNS ≈ **+0.070 ns** at the 4.000 ns period; re-validated post-handshake); worst-path **logic = 1.23 ns** — the core *logic* closes 250 MHz with large margin. `timing.xdc` models the cascaded-BRAM read Tco so the standalone build is a **logic-sanity check** (core reg→reg), per §1's host-level-I/O methodology.
- [x] **Utilization within budget** (`timing-and-resources.md §3`): 2779 LUT / 1039 FF / **4 DSP48E2** / **0 BRAM** — all under budget.
- [x] **Multiply mitigation** (§2): single pipelined signed 33×33 → 4 DSP, MUL_LAT = 4 (DSP48E2 MREG+PREG; determinism-safe; golden cycle 286). Re-verified green.
- [x] **IP-readiness tidy:** whole core → **synchronous reset** (clears `Synth 8-7137` + `SYNCASYNCNET`, packs the multiply into DSP48E2 MREG/PREG). Re-verified behaviour-neutral (lint / det 8×286 / riscv-tests 48/48 / cosim 48/48 / archtest 75/75).
- [x] **IP hand-off documented:** `docs/ip-delivery.md` (manifest, port + LMB contract, carve-out, pblock+DSP integration must-checks).
- [x] **Re-ran `make synth` after the 2026-06 LMB data-bus handshake** (Vivado 2025.2.1, xczu9eg-2): **TIMING GATE PASS, WNS +0.070 ns** @ 250 MHz OOC. Binding path unchanged (EX `forward→ALU→m_result`, logic 1.23 ns); the handshake logic (`dmem_stall`/`d_inflight`) is in register clock-enables, not the data path. The +0.209→+0.070 drop is OOC **route** (the +18 LUT / +2 FF perturbed the floorplan-less placement), not logic depth.

> **M6 complete:** the core meets 250 MHz OOC within budget. (`timing.xdc` models the
> cascaded-BRAM read Tco, so the OOC reg→reg result is the core's timing evidence.)

## Verification hardening — second-simulator gate + directed-suite expansion (2026-06)
> Closes the methodology gap behind both 2026-06 integrator escapes: every
> functional gate ran on **Verilator only**, but the bugs lived in the
> Verilator↔**xsim** semantic delta (the host's simulator). See
> `docs/verification.md` §4.1 and `docs/verification-status.md` §11.
- [x] **`make xsim` second-simulator gate** — `sim/xsim/run_xsim.ps1` + `tb/xsim/tb_xsim.sv` (the SV analogue of `sim_main.cpp`). Assembles the directed suite via WSL, then `xvlog`/`xelab`/`xsim` replays each hex (Windows-native, like `synth`). **18/18 PASS under Vivado xsim, cycle-identical to Verilator.**
- [x] **Teeth proven** — reverting the forwarding fix to the pre-fix `assign` form makes **11/18 directed tests FAIL under xsim** while **all 18 still pass Verilator** (the bug is stall-sensitive). Verilator is structurally blind to this class; xsim is the catch-net.
- [x] **Directed stimulus expanded** (also run in `make test`/CI on Verilator): `tests/fwd_matrix.s` (youngest-writer forwarding into ALU/load-base/store-data/store-base/branch/shift/MUL/CSR + x0-guard + load-use), `tests/hazard_chains.s` (multi-writer chains, pointer-chase load→load, MUL/div forwarding + div edge cases), `tests/bus_patterns.s` (sub-word + interleaved back-to-back on the `+dedge` edge slave), plus the stall-coincident pair `tests/fwd_loaduse.s` (load-result forward into every consumer under the load-use stall) and `tests/fwd_stall.s` (forwarding under `+dwait` bus back-pressure). Suite 11→16, all green; golden 286 unchanged.
- [x] **Regfile power-up fix (P7.1 / rc7-candidate).** An integrator reported a firmware refactor re-opening an xsim co-sim failure. `rv_regfile.regs` was uninitialised → `X` in xsim (0 on FPGA LUTRAM); fixed with an `initial = 0` carried as the LUTRAM INIT (area-neutral). Regression `tests/regzero.s` (fails xsim pre-fix). (This was a real fidelity gap but NOT what unblocked the integrator — see the store→load fix below.)
- [x] **Store→load capture fix (P7.1 round 2) — the actual unblocking fix.** The integrator's 4-state dump was clean (no `X`): a valid-but-stale load on the **store→load** edge. My earlier "bus is fine" was WRONG — ALL my `lmb_bram` models were **capture-and-hold** (non-canonical) and masked it; the host tile uses the **canonical free-running BRAM Port A** (`data_rd_q <= mem[addr]` every cycle, the read tracks the address). Modelled as `+dfree`, reproduced: a load held in WB across the single-outstanding gap committed the NEXT access's word because the core read **live `i_dread`** at the delayed commit (a `ret`'s `ra` from the wrong slot → PC wedge). **REAL bug** — `tests/storeload.s` FAILs pre-fix under **both Verilator and xsim** on `+dfree`. Fix (`rv_core.sv`): latch the load's own word at its ack (`ld_word`, `d_complete & w_is_load`), commit the latched value. Added `+dfree` mode + store→load to `make lmb-contract` (all slave modes pass). Validated: `make ci` 19/19, `make xsim` 19/19, whole suite under `+dfree` 19/19, determinism 8×286; **synth WNS +0.167 ns PASS, area 2855 LUT / 1068 FF** (+76/+29 for the latch). Suite 18→19. **CONFIRMED CLOSED** by the integrator's co-sim (PLATFORM_SIM 16/16; their Verilator 18/18) against `c7c9f4e` → tagged **`v1.0.0-rc7`**.
- [x] **System-level cosim (`make cosim-fw`).** Closes the gap behind the escapes: real **compiled C** (`-O0/-O2/-O3`) firmware — epilogue spill/restore, struct copy, pointer chase, in-place sort — run on the core against the **free-running slave** (`+dfree`) and lock-stepped GPR-write-for-GPR-write vs Spike. **12/12 match** (~22 k retires each); reverting the store→load fix makes them **diverge** (catches P7.1 organically, no reproducer). `sim/cosim-fw/`; in `ci-full`.
- [x] **Bus verified 3 ways — scoreboard + SVA + formal.** (1) `make scoreboard` (`sim/scoreboard/`, `+drand`): a **randomized COMPLIANT slave** (per access: free-running-1-cycle or latched-N-waits) with the architectural result checked **invariant** vs Spike across a seed sweep — **128/128**, **67/80 diverge** with the store→load fix reverted. (2) `make sva` (`sim/sva/` + `tb/sva/rv_lmb_sva.sv`): LMB-protocol concurrent assertions **bound onto `rv_core`**, `--assert` over the suite — **84 runs, 0 failures**. (3) `make formal` (`sim/formal/`): the handshake FSM extracted verbatim from `rv_core`, **PROVEN** with yosys-smtbmc + z3 — BMC + **k-induction (unbounded)**, P1–P7; teeth: a broken FSM → counterexample. All in `ci-full`. **Honest scope:** formal covers the *bus-handshake protocol*, not whole-core ISA (= `riscv-formal`/RVFI).
- [x] **Constrained-random verification (`make crv`).** A hazard-biased instruction-sequence generator (`sim/crv/gen_rand.py`, the riscv-dv methodology on the open toolchain — riscv-dv's UVM flow needs a commercial solver) emits random RV32IM_zba_zbb_zbs_zicsr programs (RAW chains, load-to-use, store-then-load, mul/div-to-use, branches on fresh operands, CSR RMW) lock-stepped vs Spike. **200/200 match — the datapath/forwarding/hazard/CSR logic is robust across thousands of random instructions.** Teeth: reverting the store→load fix makes random programs diverge.
- [x] **CSR-RMW stall-coincident fix (CRV found it).** CRV's CSR coverage surfaced a real core-vs-Spike divergence on `mscratch`: a `csrr* rd, mscratch, rs` whose `rd` read-back was the NEW value, not the OLD (13/200 diverged; the simple forward case always passed — `tests/csr_hazard.s`). Root cause: the CSR write commits in EX, but an ungated `csr_we` stayed asserted while the CSR was **frozen in EX by a `dmem_stall`** (older load/store in the single-outstanding gap — the seed-4 `sh; lhu; csrrw` shape), so the write committed early and `csr_rdata`→`rd` was already modified at advance. **Fix (`rv_core.sv`): gate `csr_we` with `~dmem_stall`** (commit exactly once, on the advance cycle — the same edge `m_result` latches the still-OLD `csr_rdata`). Regression `tests/csr_dmem_hazard.s` (FAILs pre-fix under Verilator AND xsim). CSR now in the default `make crv` mix → **200/200 with CSR included**; suite 20→21; golden 286 unchanged; `make xsim` 21/21; synth **WNS +0.182 ns** (2800 LUT / 1071 FF / 4 DSP / 0 BRAM). See `docs/verification-status.md` §12.
- [x] **`dmem_stall` × {IRQ / branch / muldiv} interaction gate (`make dmem-matrix`).** Closes the last verification cross-matrix: the MEI is swept across `sim/dmem-matrix/dmem_matrix.s` (whose back-to-back accesses keep a memory op outstanding while a taken branch / an independent counting mul/div is in flight) on every compliant slave timing (`default / +dwait=1/2/3 / +dfree / +dedge`). The architectural result (s1=638) and a transparent ISR must be invariant to both the injection cycle and the slave timing, and the MEI must be taken (a miss → TIMEOUT). **1410/1410** (6 timings × 235 injection points). Teeth: removing the `dmem_stall` IRQ guards (`take_irq`'s `~dmem_stall` + the redirect deferral) FAILs it on `+dwait` (CHECK_EQ corruption + TIMEOUTs) — a regression `irq-stress` (non-stalling slave) does not catch. In `ci-full`.

---

## Cross-cutting invariants (check on every task)
- [ ] **Preserve the `module mbv` port signature** — the MicroBlaze-V-compatible LMB v10 boundary the host binds to is fixed.
- [ ] No caches / speculation / branch prediction / OoO / early-terminating ops.
- [ ] LMB stays registered, in-order, single-outstanding (one rising-edge strobe per access, DReady-handshaked).
- [ ] Don't claim full arch-test/Spike conformance (state the carve-out).
- [ ] Keep WCET table (`microarchitecture.md` §4) and golden cycle count current.
