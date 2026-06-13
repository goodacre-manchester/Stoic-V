# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# irq_stress.s — MEI taken at many pipeline positions; verify transparency + resume.
# A transparent ISR (writes only s11) wraps a known computation (mul/div, load-use,
# branch loop). For ANY injection cycle the result must be unchanged and the program
# must complete: the wait-spin blocks until the ISR has fired (else TIMEOUT), and
# CHECK_EQ enforces the result. Swept across injection points by
# sim/irq-stress/run_irq_stress.sh; `make test` runs the single case below.
# SIM: +irq_at=30 +irq_clr=80 +max=10000
.include "test.h"
.section .text.start
.global _start
_start:
    la   t0, isr
    csrw mtvec, t0
    li   s11, 0              # ISR fired-count (the ONLY register the ISR writes)
    csrsi mstatus, 0x8       # mstatus.MIE = 1
    li   t0, 0x800
    csrs mie, t0             # mie.MEIE = 1 (bit 11)
    # --- known computation: result in s1 ---
    li   s2, 5
    mul  s3, s2, s2          # 25  (IRQ here must defer until mul completes)
    div  s4, s3, s2          # 5   (and here, until div completes)
    add  s1, s3, s4          # 30
    li   t0, 0x4000
    li   t1, 0x100
    sw   t1, 0(t0)
    lw   t2, 0(t0)           # load-use hazard
    add  s1, s1, t2          # 30 + 256 = 286
    li   t3, 0               # branch loop to widen the injection window
    li   t4, 40
1:  addi t3, t3, 1
    blt  t3, t4, 1b
    # --- require the interrupt to have been taken, then check transparency ---
2:  beq  s11, x0, 2b         # spin until ISR fires (missed IRQ -> TIMEOUT -> FAIL)
    CHECK_EQ s1, 286, 1      # result must be unchanged by the interrupt(s)
    TEST_PASS

    .align 2
isr:
    addi s11, s11, 1         # transparent handler: touches only s11, then return
    mret
