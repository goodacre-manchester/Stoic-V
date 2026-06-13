# `sim/formal/` — formal proof of the LMB handshake protocol

`make formal` **machine-proves** the LMB single-outstanding data-bus handshake — the
recurring bug site (rc4 held-strobe, rc7 store→load) — with **yosys-smtbmc + z3**:
bounded model checking AND **k-induction for an unbounded proof** (the properties hold
for *all reachable states, all time*, not just the traces a simulation happens to hit).

## What is proven

[`rv_lmb_formal.sv`](rv_lmb_formal.sv) contains the handshake FSM (`d_inflight` /
`d_issue` / `d_complete` / strobes) **extracted verbatim from `rv_core.sv`**, driven by
free inputs. The proven invariants:

| | Property |
|---|---|
| P1 | single-outstanding — a strobe issues only when no access is in flight |
| P2 | read/write strobes are mutually exclusive |
| P3 | any read/write strobe implies the address strobe (one strobe per access) |
| P4 | an unacked strobe is **not** immediately followed by another (rc4 violated this) |
| P5 | an access in flight stays in flight until DReady (no silent drop) |
| P7 | the DReady ack clears exactly one outstanding access |

**Result:** BMC (25 steps) PASS **+ k-induction PASS (unbounded)**. **Teeth:** breaking
the FSM (dropping `~d_inflight` from `d_issue`) makes both FAIL with a counterexample.

## Scope (honest)

This proves the **bus-handshake protocol** — the part that kept breaking. It is **not**
a whole-core ISA proof; that is `riscv-formal` (an RVFI-wrapper + bounded instruction
checks), a separate larger effort. The FSM here is a faithful extraction of the core's
handshake; the SVA bind in [`../sva/`](../sva/) checks the *same* properties on the
*actual* `rv_core` instance in simulation, so the extraction and the real core are
cross-checked.

## Run

```
make -C sim formal        # needs: yosys, yosys-smtbmc, z3  (apt-get install yosys z3)
```

Artifacts (SMT2, VCD, logs) land in `work/` (git-ignored). In `make ci-full`.
