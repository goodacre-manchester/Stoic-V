# Interrupt-injection sweep

`make -C sim irq-stress` fires the machine-external interrupt at **every cycle**
across a window that spans a mul, a divide, a load-use hazard, and a branch loop
([`tests/irq_stress.s`](../../tests/irq_stress.s)), and requires every run to
PASS. Because the ISR is transparent (writes only `s11`) and the test spins
until the ISR has fired before checking the result, a PASS means both:

1. the interrupt was **taken** at that injection point (a missed/dropped
   interrupt would spin → TIMEOUT → FAIL), and
2. the computation result is **unchanged** (`mret` resumed correctly, no pipeline
   corruption on entry/squash).

**Result:** 99/99 injection points pass — covering mid-mul/div deferral, the load
shadow, and branch redirects. This stresses interrupt entry/return far harder
than the single directed `trap_mei` test. See
[`docs/verification-status.md`](../../docs/verification-status.md) §5.

Knobs: `FROM`/`TO` (sweep range), `HOLD` (cycles to hold IRQ high — must exceed
the divide latency so the level-sensitive `mip.MEIP` is guaranteed to latch),
`MAX` (timeout). Prereqs: `riscv64-unknown-elf` binutils + verilator.
