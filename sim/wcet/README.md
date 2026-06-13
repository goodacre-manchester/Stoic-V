# `sim/wcet/` — WCET latency-constant validation + FU data-independence

`make wcet` validates the published per-instruction latency constants
([`microarchitecture.md`](../../docs/microarchitecture.md) §4) against the RTL, and —
the load-bearing part — that the **operand-dependent-risk functional units (mul/div) are
data-independent** in latency. This is the determinism prime directive, measured
directly rather than inferred.

## Method

[`wcet_probe.s`](wcet_probe.s) is one dependent-op chain, assembled by the harness with
`--defsym OP/K/A/B`. For each op the harness runs the chain at **K and 2K** ops and takes
the slope `(cyc2K − cycK)/K` — the per-op latency, with the fixed prologue / pipeline
fill / drain cancelled. For div and mul it also runs a fixed K across **adversarial
operand sets** and asserts the cycle count is **identical**.

## Result

Every latency below is an **exact, fixed integer — identical for all operands**. There
are no approximate or data-dependent cycle counts: that is the determinism guarantee
(the divider is non-early-terminating, the multiply is fixed-latency). The numbers are
the *exact* measured per-op latencies; the decomposition columns are exact too.

| Op | Per-op latency (dependent chain) | Decomposition (all exact) |
|---|---|---|
| `div` | **37** | DIV_LAT **34** (1 accept + **32 fixed** restoring steps + 1 finalize) + **3** dependent-issue |
| `mul` | **6** | MUL_LAT **4** (fixed 4-stage DSP MREG/PREG) + **2** dependent-issue/forward |
| load-use | **4** | registered load + **2**-cycle load-use penalty (`P_LOADUSE=2`) |
| taken branch | **4** | **1** (branch) + **3** fixed redirect/refetch (`P_REDIR`) |

**Data-independence: div and mul latency is INVARIANT** across `{normal, INT_MIN÷−1
overflow, ÷0, 0÷x}` and `{normal, INT_MIN², −1×−1, 0×0}` — identical cycle counts. A
divide or multiply whose timing depended on its operands (e.g. an early-terminating
divider) would fail this immediately; that is the gate's teeth.

The per-op numbers are pinned baselines: a latency change fails the gate, and must be
landed together with an update to `microarchitecture.md` §4 (like the determinism golden
286). WSL: riscv assembler only; in `make ci-full`.

```
make -C sim wcet
K=128 make -C sim wcet     # deeper slope
```
