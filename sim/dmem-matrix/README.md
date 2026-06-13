# `sim/dmem-matrix/` — `dmem_stall` × {IRQ / branch / muldiv} interaction gate

`make dmem-matrix` crosses an active **`dmem_stall`** (an outstanding load/store in the
single-outstanding gap) with the three pipeline events that interact with it, sweeping
the **machine-external interrupt injection cycle** across the kernel on every compliant
slave timing.

## Why this gate exists

Each axis was already covered *individually* — `irq-stress` sweeps the MEI across all
pipeline positions, `lmb-contract`/`scoreboard` cover the data stall, `fwd_stall` covers
forwarding under back-pressure — but nothing crossed all three. The kernel
([`dmem_matrix.s`](dmem_matrix.s)) forces the coincidences:

1. **`dmem_stall` × IRQ** — a memory access is outstanding when the MEI fires; entry must
   defer until the access retires in order (`take_irq & ~dmem_stall`, and the redirect
   block defers control-flow while `dmem_stall`).
2. **`dmem_stall` × branch** — a taken branch sits in EX while the preceding load stalls
   in MEM; the redirect must be held until DReady.
3. **`dmem_stall` × muldiv** — an **independent** mul/div enters EX and counts while the
   preceding load stalls; the multiplier counter must freeze on `.hold(dmem_stall)`.

The kernel's architectural result (`s1 = 638`) and a transparent ISR (writes only `s11`)
mean the result must be **invariant** to both the injection cycle and the slave timing,
and the interrupt must be **taken** (the wait-spin turns a missed MEI into a TIMEOUT).

## Run

```
make -C sim dmem-matrix                  # sweep on {default, +dwait=1/2/3, +dfree, +dedge}
FROM=6 TO=240 HOLD=70 make -C sim dmem-matrix
```

**Result: 1410/1410** (6 slave timings × 235 injection points). Pure self-check (no
Spike); needs only the riscv assembler. WSL; in `make ci-full`.

## Teeth

Removing the `dmem_stall` IRQ guards (`take_irq`'s `~dmem_stall` **and** the redirect
deferral) makes the matrix **FAIL** — `CHECK_EQ` corruption *and* TIMEOUTs, exclusively
on the **stalling slaves** (`+dwait`) at the injection cycles where the MEI coincides
with an outstanding access. The non-stalling `irq-stress` gate passes that same broken
core, which is exactly the gap this gate closes.
