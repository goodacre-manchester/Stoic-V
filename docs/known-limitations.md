# Stoic-V — Known Limitations & Errata (v1.0.0)

The honest scope statement for the v1.0.0 core: deliberate design exclusions, and the
boundaries of what verification does and does not establish. Nothing here is a known
*defect* — there are no open functional bugs — these are **scope decisions** and
**verification-coverage boundaries**. Read alongside the authoritative
[Requirements](../README.md#requirements--specification) and
[`verification-status.md`](verification-status.md).

## 1. Functional scope (by design)

- **No precise synchronous exceptions (the §10.3 carve-out).** v1 assumes **aligned-only**
  access and omits misaligned-access traps (`mcause` 4/6), illegal-instruction (2), and
  ecall/ebreak/bus-error (5/7); `mtval`/`mscratch` are vestigial. Consequence: the
  misaligned / illegal-instruction / synchronous-cause arch-test suites are **carved out
  of signoff**, and Spike lock-step **excludes misaligned accesses**. The integer / M /
  Zba/Zbb/Zbs suites — the ones this core targets — are unaffected. Adding precise traps
  later is a localized `rv_csr`/`rv_core` change that does **not** touch the bus contract.
- **No PMP / memory protection** — deferred to v2.
- **No S/U privilege, no MMU, no A/C/F/D, no Zbc.** Machine-mode only, by design (smallest
  deterministic core).
- **`wfi`** is a legal NOP/sleep; **interrupt** is a single level-sensitive MEI (no
  edge-latch, no ack handshake).

## 2. Verification-coverage boundaries (what is / isn't established)

- **ISA correctness is established empirically, not by whole-core formal.** Conformance is
  via RISCOF/Spike arch-test (75/75), Berkeley riscv-tests (48/48), Spike lock-step cosim
  (48/48), and constrained-random vs Spike (`make crv`, 200/200 incl. CSR). **Formal proof
  is limited to the LMB bus handshake** (`make formal`, BMC + k-induction). Whole-core
  **riscv-formal (RVFI)** is *not* done and is future work; note upstream riscv-formal also
  lacks insn models for the Zba/Zbb/Zbs extensions, so even then the bit-manip ISA would
  remain on the empirical path.
- **Coverage is line + toggle (≈89.8% core), not functional.** There are no SystemVerilog
  covergroups asserting which scenarios were exercised.
- **No gate-level (post-synthesis netlist) simulation.** Equivalence between RTL and the
  synthesized netlist is not separately checked with a gate-level/SDF sim; we rely on RTL
  sim under two simulators (Verilator + Vivado xsim) plus OOC synthesis.
- **X-propagation is covered reactively, not by a systematic audit.** The known
  uninitialized-state issues (regfile, store→load) are fixed and regression-tested, but
  there is no deliberate X-injection sweep.

## 3. Timing / physical (OOC scope)

- **Timing is out-of-context (OOC), single corner (-2 speed grade).** `make synth` asserts
  **WNS ≥ 0** (setup, +0.167–0.182 ns @ 250 MHz across runs) **and WHS ≥ 0** (hold,
  preliminary — OOC has no clock tree, skew = 0). **Final timing closure — hold included —
  multi-corner sign-off, in-context P&R, power, and DRC are the integrator's**, done in the
  host floorplan/pblock (the OOC result is a logic-sanity bound, not a placed-and-routed
  guarantee). A representative single-instance in-context P&R has closed at ~+0.30 ns.
- **No power estimate** is published (a soft-core figure depends on the host fabric/clock).

## 4. Licensing note

- The core IP (`rtl/core/*`) and harnesses are **Apache-2.0**, **except `sim/embench/*`**
  (the Embench-IoT board port), which is **GPL-3.0-or-later** — an optional
  performance-measurement harness, not part of the deliverable. See [`NOTICE`](../NOTICE).

## 5. Not defects — verified-robust areas

For contrast (so this list isn't read as doubt about the core): determinism, the LMB bus
contract (verified four ways — modes, randomized scoreboard, SVA, formal), forwarding /
hazard / CSR robustness (CRV), the interrupt path incl. the `dmem_stall` coincidence
matrix, and Verilator↔xsim equivalence are all **strongly** verified — see the
[`verification-status.md`](verification-status.md) Summary table.
