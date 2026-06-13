# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# isr_backtoback.s — the in-context symptom shape: an interrupt handler doing one-shot
# back-to-back loads must read each addressed word, not the previous transaction's.
# Run on the 1-cycle slave this confirms the ISR path itself is sound (isolating the
# bug to >1-cycle data latency vs an interrupt-specific fault).
# SIM: +irq_at=200 +irq_clr=400 +max=20000
.include "test.h"
.section .text.start
.global _start
_start:
    la   t0, handler
    csrw mtvec, t0
    li   s6, 0
    csrsi mstatus, 0x8       # MIE = 1
    li   t0, 0x800
    csrs mie, t0             # MEIE = 1
1:  beq  s6, x0, 1b          # spin until handler ran
    CHECK_EQ s6, 1, 20
    TEST_PASS

    .align 2
handler:
    la   s0, ivals
    li   s1, 0xFEEDFACE
    # store immediately followed by back-to-back loads, inside the ISR
    sw   s1, 0(s0)           # store -> ivals[0] slot (scratch)
    lw   a0, 4(s0)           # ivals[1] = 0x0A0A0A0A
    lw   a1, 8(s0)           # ivals[2] = 0x0B0B0B0B
    lw   a2, 12(s0)          # ivals[3] = 0x0C0C0C0C
    CHECK_EQ a0, 0x0A0A0A0A, 10
    CHECK_EQ a1, 0x0B0B0B0B, 11
    CHECK_EQ a2, 0x0C0C0C0C, 12
    li   s6, 1
    mret

.section .data
.align 4
ivals: .word 0
       .word 0x0A0A0A0A
       .word 0x0B0B0B0B
       .word 0x0C0C0C0C
