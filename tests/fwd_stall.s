# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# fwd_stall.s — youngest-writer forwarding run under BUS BACK-PRESSURE (+dwait=2),
# the closest reproduction of the real 2026-06 in-context stall: a memory access held
# unacked (inflight) while its forwarded base/data advances. The data slave inserts
# 2 wait states per access, so each load/store holds the consumer's rs steady across
# several cycles during which the forward source (m_result) transitions — exactly
# the condition that exposed the continuous-assign forward-sensitisation gap.
# Same M+W overlap shape as fwd_matrix.s, but every consumer is a stalled bus access.
# SIM: +dwait=2 +max=20000
.include "test.h"
.section .text.start
.global _start
_start:
    li   s8, 0x0BAD0BAD         # OLD (wrong)
    li   s9, 0x600D600D         # YOUNG (correct)

    # --- 1) LOAD BASE forwarded youngest, under back-pressure ---
    la   a2, good               # &good (YOUNG)
    la   a3, bad                # &bad  (OLD)
    mv   a4, a3                 # old base
    mv   a4, a2                 # young base
    lw   s0, 0(a4)            # slow load (+dwait): base must stay YOUNG
    CHECK_EQ s0, 0x600D600D, 1

    # --- 2) STORE BASE forwarded youngest, under back-pressure ---
    la   a2, slotA
    la   a3, slotB
    sw   x0, 0(a2)            # zero slotA (a wrong base writes slotB, leaving slotA 0)
    mv   a7, a3
    mv   a7, a2                 # young base -> slotA
    sw   s9, 0(a7)
    lw   s0, 0(a2)
    CHECK_EQ s0, 0x600D600D, 2

    # --- 3) STORE DATA forwarded youngest, under back-pressure ---
    la   a5, scratch0
    mv   a6, s8
    mv   a6, s9                 # young store data
    sw   a6, 0(a5)
    lw   s0, 0(a5)
    CHECK_EQ s0, 0x600D600D, 3

    # --- 4) pointer-chase load->load BASE, under back-pressure ---
    la   a1, ptrw               # ptrw holds &target
    lw   a2, 0(a1)            # a2 = &target (slow load result as next base)
    lw   s0, 0(a2)            # slow load via the loaded base
    CHECK_EQ s0, 0x600D600D, 4

    TEST_PASS

.section .data
.align 4
good:     .word 0x600D600D
bad:      .word 0x0BAD0BAD
slotA:    .word 0
slotB:    .word 0
scratch0: .word 0
ptrw:     .word target          # holds the address of target
target:   .word 0x600D600D
