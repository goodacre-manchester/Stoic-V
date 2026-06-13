# Changelog — Stoic-V

All notable changes to the Stoic-V core and its verification suite. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/); the core targets a single
`v1.0.0` release, reached through the `v1.0.0-rcN` candidates below. Scope and known
limitations: [`docs/known-limitations.md`](docs/known-limitations.md).

## [v1.0.0] — 2026-06-13

First stable release of the Stoic-V core: a deterministic RV32IM_zba_zbb_zbs_zicsr
(M-mode) RISC-V soft core, drop-in for the AMD MicroBlaze-V via LMB v10, closing 250 MHz
OOC on UltraScale+. Verification scope and the §10.3 carve-out: `docs/known-limitations.md`.

### Added
- **`make dmem-matrix`** — the `dmem_stall` × {IRQ / branch / muldiv} interaction gate:
  the MEI is swept at every cycle while a data access is outstanding, across all
  compliant slave timings (default / `+dwait=1/2/3` / `+dfree` / `+dedge`). **1410/1410**;
  teeth: removing the `dmem_stall` IRQ guards FAILs it on `+dwait`. Closes the last
  verification cross-matrix.
- **`make wcet`** — WCET latency-constant validation + functional-unit data-independence:
  measures the exact per-op latency (div **37**, mul **6**, load-use **4**, taken-branch
  **4** cycles — all fixed) and proves mul/div latency is operand-INVARIANT across
  adversarial sets. Reconciles to microarchitecture.md §4 (DIV_LAT=34, MUL_LAT=4, P_REDIR=3).
- **Hold-timing (WHS) check** in `vivado/build.tcl` — the synth gate now reports and
  asserts worst-hold-slack alongside WNS (synth PASS: WNS +0.182 / WHS +0.048 ns;
  OOC-preliminary, final hold closure is the integrator's in-context P&R).
- `CHANGELOG.md` and `docs/known-limitations.md` (consolidated errata / scope).

### Changed
- **Renamed the core/project to Stoic-V** (was the working name "Fabric-RISC-V"). The
  synth top stays `module mbv` — the MicroBlaze-V LMB v10 drop-in contract is unchanged.
- Removed integrator/host-"fabric" references from the documentation and comments
  (genericized to "the integrator" / "a host SoC"); the deliverable stands on its own.
- Trimmed `CLAUDE.md` from the per-fix narrative log to rules + status + pointers
  (history now lives only in `docs/verification-status.md` and git tags).
- All cycle latencies stated as **exact** integers (purged "~"/"≈"): a WCET-analysable
  core has fixed, not approximate, cycle counts.

### Fixed
- `NOTICE` license scope corrected: `sim/embench/*` is **GPL-3.0-or-later** (the
  Embench-IoT board port), not Apache-2.0; documented the carve-out and the externally
  fetched CoreMark/Embench benchmarks.

## [v1.0.0-rc8]
- **CSR-RMW stall-coincident fix** (surfaced by `make crv` once CSR ops were in the
  random mix): a `csrr* rd, mscratch, rs` returned the NEW value instead of the
  architectural OLD value when the CSR instruction was frozen in EX by a `dmem_stall`.
  Fix: gate `csr_we` with `~dmem_stall` (`rv_core.sv`); regression `tests/csr_dmem_hazard.s`.
- **Constrained-random verification** (`make crv`) added — hazard-biased random
  RV32IM_zba_zbb_zbs_zicsr streams vs Spike, **200/200** (incl. CSR RMW).

## [v1.0.0-rc7]
- **Store→load capture fix**: a load held in WB across the single-outstanding gap
  committed the next access's word on a canonical free-running BRAM slave. Fix: latch
  the load's own word at its ack (`ld_word`); regression `tests/storeload.s` on `+dfree`.
- **Regfile power-up fix**: `rv_regfile.regs` given `initial = 0` (LUTRAM INIT) so a
  4-state simulator does not read `X` for an unwritten GPR; regression `tests/regzero.s`.
- **System-level lock-step** (`make cosim-fw`, compiled-C firmware vs Spike on the
  free-running slave) and the **bus verified three ways** (`scoreboard` / `sva` / `formal`).

## [v1.0.0-rc5 / rc6]
- **Forwarding-sensitivity fix**: compute the operand forwards in `always_comb` rather
  than a continuous `assign fwd(...)` (which some simulators under-sensitise → a stale
  youngest-writer forward). Behaviour-identical in Verilator; closes the Verilator↔xsim gap.
- **`make xsim`** second-simulator gate added (the directed suite under Vivado xsim,
  cycle-compared to Verilator) + directed forwarding/hazard/bus stimulus expansion.

## [v1.0.0-rc1 … rc4] — initial release candidates
- RV32IM_zba_zbb_zbs_zicsr M-mode core (`rtl/core/`, synth top `mbv.sv`); 5-stage
  in-order pipeline, synchronous reset, no caches/speculation (deterministic by design).
- Official conformance: RISCOF/Spike arch-test **75/75** and Berkeley riscv-tests
  **48/48** (with the §10.3 carve-out), Spike lock-step cosim **48/48**, determinism
  (8 datasets × 286 cycles).
- **LMB v10 single-outstanding handshake**: one rising-edge address strobe per access,
  DReady-handshaked (fixed the in-context back-to-back stale-read); `make lmb-contract`.
- M6 synthesis/timing: meets **250 MHz OOC** on UltraScale+ within the resource budget.
