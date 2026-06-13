# CLAUDE.md — project guide & autonomous-resume driver

> This file is committed to the repo (not a memory file) so any Claude Code
> session can resume the work autonomously. Read it first, every session.

## What this project is

**Stoic-V** is a custom **RV32 RISC-V core in SystemVerilog** that is a **drop-in
replacement** for the AMD MicroBlaze-V soft core in a host SoC. ISA
`rv32im_zba_zbb_zbs_zicsr`, **Machine-mode only**, no caches / no MMU / no
speculation — built for **static WCET analysability** (hard determinism); the name
is the design rule — the core is *unmoved by its data* (no speculation/prediction,
operand-independent timing). It presents the **MicroBlaze-V-compatible LMB v10**
master interface, so a host SoC that instantiates a MicroBlaze-V can bind this core
in its place **unchanged**. (The synth top module is still `module mbv` — that fixed
signature is the drop-in contract, not a brand name; do not rename it.)

The authoritative external contract is the **Requirements** section of
[`README.md`](README.md). Everything in `docs/` elaborates it and must never
contradict it.

## Documents

| File | Purpose |
|---|---|
| [`README.md`](README.md) | **Authoritative spec** (Requirements) + project intro |
| [`docs/microarchitecture.md`](docs/microarchitecture.md) | **Design spine**: scope/layout, pipeline, hazards, FU latencies, **WCET constants**, decode + CSR maps |
| [`docs/timing-and-resources.md`](docs/timing-and-resources.md) | **250 MHz / UltraScale+** closure target, critical paths, resource budget, XDC |
| [`docs/verification.md`](docs/verification.md) | Toolchain, suites, `make` targets, gates, conformance carve-out |
| [`docs/verification-status.md`](docs/verification-status.md) | **Living evidence record: what's verified, how, and what remains** (conformance 75/75+48/48+48/48, determinism, LMB contract, IRQ, coverage) |
| [`docs/implementation-backlog.md`](docs/implementation-backlog.md) | **Executable checkbox task list — the progress source of truth** |
| [`docs/local-resume.md`](docs/local-resume.md) | **Setup & run guide: fresh clone → install every toolchain (portable/WSL/Vivado) + run every gate, env-var contract, carve-out** |
| [`docs/ip-delivery.md`](docs/ip-delivery.md) | **IP integration guide for any host SoC: file manifest, port contract, LMB contract, §10.3 carve-out, pblock+DSP integration requirements** |
| [`docs/known-limitations.md`](docs/known-limitations.md) | **Known limitations & errata: scope decisions + verification-coverage boundaries** |
| [`CHANGELOG.md`](CHANGELOG.md) | **Release history (`v1.0.0-rcN` → v1.0.0)** |

## Autonomous resume protocol

1. Read this file, then `docs/implementation-backlog.md`.
2. Find the **first unchecked `[ ]` task** (and check the **Current status**
   table below matches).
3. Implement it, matching the surrounding code's style.
4. Run its **gate** (a `make` target — see `docs/verification.md`).
5. **Only if the gate is green:** check the box `[x]`, update the WCET table
   (`docs/microarchitecture.md` §4) and the **Current status** table here if a
   milestone completed, then commit & push — and **watch the CI run to green**
   (Git/workflow below); fix any failure before moving on.
6. If blocked, mark `[!]` with a one-line reason and surface it to the user.

A milestone is **done only when its gate is green**. Never check a box on a red
or unrun gate. Don't claim "arch-test passes" without the carve-out (below).

## Current status

| Milestone | State |
|---|---|
| Planning / spec / docs | ✅ complete |
| M0 Repo scaffold | ✅ lint clean (Verilator 5.020) |
| M1 RV32I core | ✅ official riscv-tests rv32ui 40/40 + arch-test I 38/38 + cosim |
| M2 M extension | ✅ riscv-tests rv32um 8/8 + arch-test M 8/8 + cosim |
| M3 Zba/Zbb/Zbs | ✅ arch-test B 29/29 + cosim |
| M4 Zicsr + traps | ✅ `csr_ops` (19 checks) + `trap_mei`/`trap_wfi` + `irq-stress` 99/99 |
| M5 Determinism | ✅ 286 cyc × 8 datasets (incl. clz/ctz/cpop, all mul/div variants) |
| **Conformance + verification** | ✅ **archtest 75/75, riscv-tests 48/48, cosim 48/48, cosim-fw 12/12, scoreboard 128/128 (randomized timing), sva (LMB assertions, 84 runs), formal (handshake PROVEN: BMC+induction), crv 200/200 (constrained-random vs Spike, **incl. CSR RMW** — clean), lmb-contract (level/edge-detect/free-running/back-pressure, incl. store→load), irq-stress 99/99, dmem-matrix 1410/1410 (dmem_stall×{IRQ/branch/muldiv}), wcet (latency constants + mul/div data-independence), coverage 89.8% core, `make xsim` 21/21** — see `docs/verification-status.md` |
| M6 Synth/timing (250 MHz US+) | ✅ default 2-cycle config meets **250 MHz OOC** (WNS ≈ **+0.167 ns** at 4.000 ns; **2855 LUT / 1068 FF / 4 DSP48E2 / 0 BRAM**) within the resource budget. Binding path is the EX `forward→ALU→m_result` loop (logic ≈ 1.23 ns). **Re-validated post CSR-RMW fix** (Vivado 2025.2.1): still **PASS**, this run WNS **+0.182 ns** / 2800 LUT / 1071 FF — within OOC run-to-run noise (the `~dmem_stall` gate on `csr_we` is a single AND-term off the binding loop). |

> **State:** M0–M5 + the conformance/verification milestone are complete and
> GREEN (RISCOF/Spike + Berkeley riscv-tests + the extended suite; full evidence:
> `docs/verification-status.md`). The core uses **synchronous reset** throughout
> (so the multiply packs into the DSP48E2 MREG/PREG). Sole open *functional* item:
> precise synchronous exceptions (the §10.3 carve-out).
>
> **Recent fixes & evidence.** The 2026-06 bus / forwarding / regfile / store→load /
> CSR-RMW fixes are written up in `docs/verification-status.md` §4/§11/§12; their
> durable lessons are the **Golden rules** below; the timeline is git tags
> `v1.0.0-rc1…rc8`. (History lives in the evidence record, not in this always-loaded file.)
>
> **Timing (M6):** the default config meets **250 MHz OOC** (WNS ≈ +0.167 ns @
> 4.0 ns; core logic ≈ 1.23 ns; 2855 LUT / 1068 FF / 4 DSP48E2 / 0 BRAM) within the
> resource budget; the residual is OOC routing of a floorplan-less design, not logic
> depth (binding path is the EX forward→ALU loop).
> **The core IP is functionally complete and validated — `v1.0.0` released (2026-06-13).**
> Run conformance gates in WSL (`wsl make -C sim <target>`; Spike doesn't build on
> Windows).
>
> **Single sources of truth** (don't duplicate — link): milestone progress →
> [`docs/implementation-backlog.md`](docs/implementation-backlog.md); verification
> evidence → [`docs/verification-status.md`](docs/verification-status.md); timing/
> resources → [`docs/timing-and-resources.md`](docs/timing-and-resources.md);
> integration → [`docs/ip-delivery.md`](docs/ip-delivery.md); `CORE_PERF`
> 1-cycle build is OFF by default (perf table in `docs/verification.md` §9).

### Environment / toolchain notes (important for resume)
- **This container had:** Verilator **5.020** (`apt-get install verilator`),
  `binutils-riscv64-unknown-elf` (assembler/linker), Python 3, gcc. No Vivado,
  no Spike, no riscv **gcc** (C), no official riscv-tests/RISCOF.
- **Verification done here:** Verilator lint + **directed self-checking asm
  tests** (real assembler) + the determinism cycle regression. This substitutes
  for `make riscv-tests`/`archtest`/`cosim` which need the official suites +
  Spike — **run those locally** to complete formal conformance (with the §10.3
  carve-out). Do not claim official arch-test/Spike pass until run locally.
- **Local session (WSL Ubuntu-24.04), DONE:** built Spike 1.1.1-dev
  (`~/riscv-tools`), `pip install riscof` (`~/riscof-venv`), cloned
  riscv-arch-test `old-framework-3.x`. **`make archtest` is GREEN — official
  RISCOF vs Spike, 75/75** (I/M/Zba/Zbb/Zbs) with the §10.3 carve-out (Zbc
  `clmul*` + misaligned/illegal/sync-trap suites out of scope). The flow lives
  in `sim/riscof/` (DUT plugin + base-matched env; the arch build boots the sim
  at 0x8000_0000 via the new `RESET_VEC`/`MEM_BASE` params — default 0x0, so
  synth/firmware/determinism are unchanged). Run conformance **in WSL**, not
  native Windows (Spike won't build there and its boot ROM forbids base 0x0).
  **Official `make riscv-tests` (Berkeley rv32ui+rv32um) is also GREEN — 48/48**
  (custom M-mode/no-trap env in `sim/riscv-tests/`, self-checking via tohost;
  `ma_data`/`fence_i` skipped per carve-out). **`make cosim` is GREEN too —
  Spike lock-step retire-compare, 48/48** (per-committed-GPR-write vs Spike
  `--log-commits`; core emits a retire trace via `w_pc` + a tb_top XMR gated by
  `+trace`; `sim/cosim/`). **All official conformance `[!]` items are now
  closed** (archtest, riscv-tests, cosim) with the §10.3 carve-out.
- **Local must-haves:** a RISC-V GCC toolchain for the optional `fw/` example;
  Vivado UltraScale+ for `make synth` (M6).
- **WSL resume cheat-sheet** (distro `Ubuntu-24.04`; everything below already
  installed): Spike `~/riscv-tools/bin`, RISCOF venv `~/riscof-venv`, arch-test
  `~/src/riscv-arch-test` (branch `old-framework-3.x`), riscv-tests
  `~/src/riscv-tests`, plus apt `verilator`/`gcc-riscv64-unknown-elf`/`dtc`.
  Re-run any gate with `wsl -d Ubuntu-24.04 -- bash -lc "make -C <repo>/sim <target>"`
  — targets: `lint test determinism archtest riscv-tests cosim cosim-fw scoreboard sva
  formal crv lmb-contract irq-stress dmem-matrix wcet coverage` (`formal` also needs apt `yosys`/`z3`).
  **`make xsim`** (second-simulator gate) and `make synth` are
  run **natively on Windows** (Vivado, not WSL): `pwsh sim/xsim/run_xsim.ps1` — it
  shells into WSL only to assemble the test hex. The RISC-V GCC toolchain targets
  rv32 via `-march=rv32im_zba_zbb_zbs -mabi=ilp32`.

## Golden rules (non-negotiable)

- **Determinism is the prime directive.** No caches, no speculation, no branch
  prediction, no out-of-order, no early-terminating mul/div. Any operand-
  dependent timing is a bug even if functionally correct.
- **The core conforms to the LMB v10 host boundary, not the reverse** — that
  drop-in premise is load-bearing. A host SoC instantiates the core as
  **`module mbv`** with the fixed MicroBlaze-V port list, so our synth top must
  **be `module mbv`** with that exact signature (see `docs/microarchitecture.md`
  §9).
- **LMB data bus is single-outstanding, one rising-edge strobe per access,
  DReady-handshaked.** The core drives a 1-cycle address-strobe *pulse* per access
  (a clean rising edge — the host slave and MB-V both start an access on that edge)
  and waits for `DReady` before completing it; it never holds the strobe across
  back-to-back accesses (that re-reads the first word — the 2026-06 in-context bug).
  This works with any FIXED-latency registered slave (level / edge-detect /
  **free-running** / back-pressure); a combinational/zero-wait response still corrupts
  execution (negative test). Consecutive accesses cost a 1-cycle gap (deterministic;
  matches MB-V).
- **The load result is LATCHED, not read live off the bus.** `rv_core.sv` captures the
  load's own word the cycle its access acks (`ld_word`, `d_complete & w_is_load`) and
  commits the latched value — because on the CANONICAL free-running registered slave
  (Xilinx BRAM Port A, `q <= mem[addr]` every cycle, e.g. a host tile's `data_rd_q`)
  the read tracks the *address*, which advances to the next access while `dmem_stall`
  holds this load in WB. Reading live `i_dread` at the delayed commit cycle gets the
  NEXT access's word (the 2026-06 P7.1 store→load stale read; a `ret`'s `ra` restored
  from the wrong slot → PC wedge). This is a REAL bug (Verilator + xsim); the hold-type
  slave models masked it. Test the bus on `+dfree`, not only the hold-type slaves.
- **Forwarding lives in `always_comb`, never a continuous `assign fwd(...)`.** `fwd()`
  reads module signals (`m_*`/`w_*`/`wmd_*`/`wl_*`) outside its arg list; a continuous
  `assign` of it is under-sensitised by some simulators (Vivado xsim) → STALE forward
  → a load-base reads the older of two same-`rd` writers (the 2026-06 rc5 bug).
  `always_comb` sensitises to reads inside called functions — keep it that way. This
  bug class is **invisible to Verilator** (it tracks the full dependency), so the
  guard is **`make xsim`** — the directed suite under Vivado xsim (the host's
  simulator). Run it on any forwarding/hazard/bus RTL change before pushing; with
  the bug reintroduced it FAILs 11/18 directed tests under xsim while all 18 still
  pass Verilator (`docs/verification.md` §4.1, `verification-status.md` §11).
- **`csr_we` is gated by `~dmem_stall`** — a CSR read-modify-write commits its write in
  EX, and `rd` gets the OLD value via the combinational `csr_rdata`. If a `dmem_stall`
  (an older load/store in the single-outstanding gap) freezes the CSR in EX, an ungated
  `csr_we` commits the write early, so the read-back captures the NEW value (the 2026-06
  CRV-surfaced stall-coincident CSR-RMW bug; a `csrr* rd, mscratch, rs` returned the new
  value, e.g. after a `sh; lhu;` pair). Gating with `~dmem_stall` makes the write land
  exactly once, on the cycle the instruction advances out of EX — the same edge
  `m_result` latches `csr_rdata` (still OLD). `dmem_stall` is the only thing that holds a
  CSR in EX. Guard: `tests/csr_dmem_hazard.s` (FAILs pre-fix under Verilator AND xsim);
  CSR ops are in the default `make crv` mix.
- **Synchronous reset throughout** — every `always_ff` is `@(posedge clk)` with
  `if (!rst_n)` *inside* (NO `negedge rst_n` in any sensitivity list). An async
  reset blocks DSP48E2 register packing (the multiply MREG/PREG) and trips Vivado
  `Synth 8-7137` + Verilator `SYNCASYNCNET`. This matches the documented reset
  spec (README "Clock & reset", README "Clock & reset", µarch §3). Do **not** reintroduce
  async reset. (Reset is held ≥1 clock everywhere, so it's behaviour-identical.)
- **Defined power-up state: `rv_regfile.regs` has an `initial = 0`.** The regfile is
  LUTRAM (no reset port — adding one breaks LUTRAM inference), but on FPGA it
  configures to 0 at programming, so an `initial` models that and is synthesized as
  the LUTRAM INIT (timing/area unchanged — re-confirmed WNS +0.070 ns). Without it,
  4-state sim (xsim) reads `X` for an unwritten GPR; that `X` propagates into a load
  base (→ wrong/0 address) or a `ret`/`jalr` target (→ PC 0) when firmware touches an
  untouched register (the 2026-06 P7.1 wedge). Verilator (2-state) reads 0 and hides
  it. Keep the `initial`. Note: an `X` from uninitialized *memory* (the host BRAM/
  aperture model or unzeroed `.bss`) is the **integrator's** to define (real FPGA
  BRAM is 0) — the core cannot and must not special-case `X` in `jalr`. Guard:
  `tests/regzero.s` under `make xsim`.
- **Conformance carve-out:** v1 omits precise synchronous exceptions and assumes
  aligned-only access; the misaligned / illegal-instruction / sync-cause
  arch-test suites are out of signoff and Spike lock-step excludes misaligned
  ops. State this whenever reporting conformance.
- **Required must-haves** (firmware depends on them): `wfi` legal NOP/sleep;
  `mret` MIE/MPIE restore; level-sensitive `mip.MEIP` (no edge-latch);
  MEI trap → `mtvec`; the `mstatus`/`mie`/`mtvec`/`mepc`/`mcause` set.
  See the conformance checklist in `README.md` and the repo layout (README / microarchitecture §0)5.

## Build & verify (commands)

Real targets live in `sim/Makefile`; the repo-root `Makefile` forwards to it, so
`make <target>` works from either the project root or `sim/`. See
`docs/verification.md` for details.

```
make lint          # Verilator lint (M0)
make test      # run tb_top on a hex
make riscv-tests   # rv32ui (+rv32um at M2)
make archtest      # RISCOF, in-scope I/M/Zb* only (carve-out)
make trap-suite    # directed trap/interrupt tests (M4)
make cosim         # Spike lock-step retire-compare (riscv-tests)
make cosim-fw      # system-level: compiled-C firmware (-O0/-O2/-O3) vs Spike on the free-running slave (+dfree)
make scoreboard    # randomized-slave-timing scoreboard: arch invariance vs Spike under +drand seed sweep
make sva           # assertion-based: LMB-protocol SVA bound onto rv_core, --assert over the suite (Verilator)
make formal        # FORMAL proof of the LMB handshake (yosys-smtbmc + z3: BMC + k-induction). needs yosys/z3
make crv           # constrained-random: hazard-biased random instruction streams vs Spike (NPROG/NINSTR to tune)
make determinism   # cycle-trace regression (M5 acceptance gate)
make lmb-contract  # LMB contract: back-to-back loads/stores on level / edge-detect / back-pressure slaves PASS; combinational FAILs
make irq-stress    # MEI injection swept across all pipeline positions (99 points)
make dmem-matrix   # dmem_stall × {IRQ/branch/muldiv} coincidence: MEI sweep on stalling slaves (1410/1410)
make wcet          # WCET latency constants (µarch §4) + mul/div data-independence (operand-invariant latency)
make coverage      # verilator --coverage over the corpus (per-file line coverage)
make xsim          # second-simulator gate: directed suite under Vivado xsim (Windows-native; catches Verilator<->xsim divergences). pwsh sim/xsim/run_xsim.ps1
make synth         # Vivado: assert WNS>0 @ 250 MHz + budget (M6)
make ci            # portable: lint+test+determinism (verilator only, runs anywhere)
make ci-full       # full local regression (WSL): +archtest+riscv-tests+cosim+cosim-fw+scoreboard+sva+formal+crv+lmb-contract+irq-stress+dmem-matrix+wcet
```

Toolchain: Verilator ≥5, riscv-gnu-toolchain (`riscv32-unknown-elf-gcc`,
`-march=rv32im_zba_zbb_zbs -mabi=ilp32`), Spike (`--isa=rv32im_zba_zbb_zbs`),
RISCOF/Python, Vivado (UltraScale+, default part **`xczu9eg-ffvb1156-2-e`** = ZCU102 / XCZU9EG-2).
Record exact versions/install steps here as M0 pins them.

## Git / workflow

- Work on **`main`** (the single working branch — the earlier `claude/*` feature
  branch was consolidated). Commit with clear messages; **push only when the user
  authorises** (per-commit). Do **not** open a PR unless asked.
- Keep `docs/implementation-backlog.md` checkboxes and the **Current status**
  table above updated in the same commit as the work they describe.
- **Docs discipline — status reflects the CURRENT state, not history.** `README.md` and
  any "Status" section state what is true *now* (green gates + standing conditions like
  the §10.3 carve-out). Bug-found-and-fixed write-ups and "was X, now Y" deltas belong in
  `docs/verification-status.md`, `CHANGELOG.md`, and the commit/tag history — not in the
  top-level status. (Likewise, never claim an approximate cycle count: latencies are
  exact integers — DIV_LAT=34, MUL_LAT=4, P_REDIR=3 — see `make wcet`.)
- **CI ownership — after every push to `origin/main` that triggers a run, watch the
  GitHub Actions run to completion and fix any failure in the SAME session.** Don't
  leave a red run for the user to discover by email — a bare failure email is not a
  substitute for catching it. How: `gh run list --workflow ci.yml --commit <sha>` for
  the run id, then `gh run watch <id> --exit-status` (exit 0 = green). **Docs-only
  pushes skip CI by design** (`paths-ignore: '**.md'`) — no run is created, so finding
  none to watch is expected, not a miss. (Manual override for any push:
  `[skip ci]` in the commit message.) The cloud CI (`.github/workflows/ci.yml`) runs
  only the **portable subset** — `make -C sim ci` (lint + directed tests +
  determinism; verilator + binutils, no Vivado/Spike) — and travels with every clone.
  The heavy gates (archtest/cosim/riscv-tests/lmb-contract/irq-stress/synth) are
  **local only** (WSL/Vivado); run them before pushing anything that touches RTL or
  the WCET/golden numbers.
