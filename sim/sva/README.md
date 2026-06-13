# `sim/sva/` — assertion-based verification of the LMB master

`make sva` binds concurrent SVA properties onto the **actual `rv_core`** instance
([`../../tb/sva/rv_lmb_sva.sv`](../../tb/sva/rv_lmb_sva.sv)) and checks them in
simulation (`verilator --assert`) across the whole directed suite under the default
slave **and** the randomized slave (`+drand` seeds). It is the simulation companion to
the formal proof in [`../formal/`](../formal/): the *same* LMB-protocol invariants
(single-outstanding, one-strobe-per-access, strobe sequencing, in-flight-until-ack),
checked on the real core rather than the extracted FSM.

**Result:** 21 tests × 4 timings = **84 runs, 0 assertion failures.**

## Properties (P1–P5)

`o_das` only when `!d_inflight` · read/write strobes exclusive · any strobe ⇒ address
strobe · an unacked strobe is not immediately re-issued (rc4) · in-flight until DReady.

## Run

```
make -C sim sva        # Verilator only (--assert + the SVA bind)
```

In `make ci-full`.
