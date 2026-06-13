# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# trap_mei.s — machine external interrupt: enable, take trap, mret, level deassert.
# SIM: +irq_at=200 +irq_clr=600 +max=20000
.include "test.h"
.section .text.start
.global _start
_start:
    la   t0, handler
    csrw mtvec, t0
    li   s6, 0               # set by handler
    csrsi mstatus, 0x8       # mstatus.MIE = 1
    li   t0, 0x800
    csrs mie, t0             # mie.MEIE = 1 (bit 11)
    # spin until handler runs
1:  beq  s6, x0, 1b
    CHECK_EQ s6, 1, 1
    # mcause should read the MEI cause
    csrr s7, mcause
    li   t3, 0x8000000B
    CHECK_EQ s7, 0x8000000B, 2  # (t3 unused; CHECK uses imm)
    TEST_PASS

    .align 2
handler:
    li   s6, 1
    mret
