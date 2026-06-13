# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# loadbase_fwd.s — REGRESSION for the in-context forwarding defect (rc4): two back-to-back
# writes to the same register feeding a LOAD BASE (AGEN), with NO instruction between
# the younger writer and the load. The load's base must forward the YOUNGER writer.
# Firmware shape: `or a5,a4,s4 ; add a5,a5,s3 ; lw _,0(a5)` (0x164/0x168/0x16c).
# Pre-fix the load uses the OLDER x15, reading the wrong location.
# SIM: +max=20000
.include "test.h"
.section .text.start
.global _start
_start:
    la   s0, wrongloc       # &wrongloc (older base, holds the WRONG value)
    li   s1, 0x10           # delta from wrongloc -> sentinel

    # --- minimal: op x; op x(dep); lw 0(x) ---
    or   a0, s0, x0         # write1 (older): a0 = &wrongloc
    add  a0, a0, s1         # write2 (younger, dep): a0 = &wrongloc+0x10 = &sentinel
    lw   a1, 0(a0)          # load base a0 -> must read sentinel (youngest writer)
    CHECK_EQ a1, 0x600D600D, 1

    # --- addi form from the suggested regression: addi x;addi x;lw 0(x) ---
    addi t1, s0, 0          # t1 = &wrongloc (older)
    addi t1, t1, 0x10       # t1 = &sentinel  (younger)
    lw   t2, 0(t1)          # must read sentinel
    CHECK_EQ t2, 0x600D600D, 2

    # --- exact firmware chain: load-use feeds `or a5,a4,s4; add a5,a5,s3; lw 0(a5)` ---
    la   s2, basew          # s2 -> word holding 0
    li   s4, 0x4000         # s4 = &wrongloc (the offset, like c<<12)
    li   s3, 0x10           # s3 = delta to sentinel (the base add)
    lw   a4, 0(s2)          # a4 = 0  (load)
    addi t3, sp, 0          # filler
    slli a4, a4, 5          # a4 = 0  (load-use)
    or   a5, a4, s4         # a5 = 0x4000 = &wrongloc   (older write)
    add  a5, a5, s3         # a5 = 0x4010 = &sentinel   (younger)
    lw   a6, 0(a5)          # must read sentinel
    CHECK_EQ a6, 0x600D600D, 3

    TEST_PASS

.section .data
.align 4
wrongloc: .word 0x0BAD0BAD   # @ 0x4000 (DELTA-0x10 before sentinel)
          .word 0x0BAD0BAD   # @ 0x4004
          .word 0x0BAD0BAD   # @ 0x4008
          .word 0x0BAD0BAD   # @ 0x400c
sentinel: .word 0x600D600D   # @ 0x4010
basew:    .word 0            # @ 0x4014
