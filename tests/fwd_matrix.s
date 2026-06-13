# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# fwd_matrix.s — systematic operand-forwarding / youngest-writer coverage.
#
# Every block uses the M+W overlap shape that exposed the 2026-06 in-context
# forwarding bug: TWO single-instruction writers of the same register with NO
# bubble between them, then a consumer that reads it. When the consumer is in EX,
# the YOUNGER writer is in MEM (m_result) and the OLDER is in WB (w_pre); the
# consumer MUST forward the younger one. The pre-fix continuous-`assign fwd(...)`
# returned the OLDER (WB) value under Vivado xsim's sensitivity rules (Verilator
# always computed it correctly), so this file is a TRUE second-simulator
# regression — it passes Verilator pre- and post-fix, but FAILS under xsim with
# the buggy RTL and PASSES with the always_comb fix. Run it under BOTH:
#   make test                 (Verilator)
#   sim/xsim/run_xsim.ps1      (Vivado xsim)
#
# Writers inside each window are single instructions: `li` of a large immediate
# is lui+addi (2 instrs) and would break the exact overlap, so the OLD/YOUNG
# sentinels live in s8/s9 and the window uses single-instruction `mv` writers.
# Scratch t0/t1/t2 are reserved by the macros; window temps use t3-t6/a*/s0.
# SIM: +max=20000
.include "test.h"
.section .text.start
.global _start
_start:
    li   s8, 0x0BAD0BAD          # OLD sentinel (older writer / WB-stage value)
    li   s9, 0x600D600D          # YOUNG sentinel (younger writer / MEM-stage value)

    # --- 1) ALU consumer via rs1 (ex_a_fwd) ---
    mv   a0, s8                  # old:   a0 = OLD
    mv   a0, s9                  # young: a0 = YOUNG
    add  s0, a0, x0             # consumer reads a0 -> must be YOUNG
    CHECK_EQ s0, 0x600D600D, 1

    # --- 2) ALU consumer via rs2 (ex_b_fwd) ---
    mv   a1, s8
    mv   a1, s9
    add  s0, x0, a1            # rs2 path
    CHECK_EQ s0, 0x600D600D, 2

    # --- 3) LOAD BASE / AGEN (the original bug site: ex_a_fwd into the address) ---
    la   a2, good_word          # &good_word (holds YOUNG)  -> the correct base
    la   a3, bad_word           # &bad_word  (holds OLD)    -> the wrong base
    mv   a4, a3                 # old base
    mv   a4, a2                 # young base
    lw   s0, 0(a4)             # load base a4 -> must read good_word
    CHECK_EQ s0, 0x600D600D, 3

    # --- 4) STORE DATA (ex_b_fwd -> m_storedata) ---
    la   a5, scratch0
    mv   a6, s8
    mv   a6, s9                 # young store data
    sw   a6, 0(a5)             # store ex_b_fwd(a6) -> must write YOUNG
    lw   s0, 0(a5)
    CHECK_EQ s0, 0x600D600D, 4

    # --- 5) STORE BASE (ex_a_fwd -> agen) ---
    la   a2, slotA              # target slot (pre-zeroed); read back below
    la   a3, slotB
    sw   x0, 0(a2)             # zero slotA so a bug (store to slotB) leaves it 0
    mv   a7, a3                # old base -> slotB
    mv   a7, a2                # young base -> slotA
    sw   s9, 0(a7)            # store YOUNG via base a7 -> must hit slotA
    lw   s0, 0(a2)
    CHECK_EQ s0, 0x600D600D, 5

    # --- 6) BRANCH operands (ex_a_fwd / ex_b_fwd into the comparator) ---
    mv   t3, s8
    mv   t3, s9                # young: t3 = YOUNG
    bne  t3, s9, .Lbrfail      # forwarded YOUNG -> equal -> not taken
    j    .Lbrok
.Lbrfail:
    TEST_FAIL 6
.Lbrok:

    # --- 7) SHIFT AMOUNT (ex_b_fwd[4:0]) ---
    li   a0, 1
    li   t4, 0
    li   t5, 4
    mv   a1, t4                # old amount = 0
    mv   a1, t5                # young amount = 4
    sll  s0, a0, a1           # 1 << 4 = 16  (1 if bug forwards 0)
    CHECK_EQ s0, 16, 7

    # --- 8) MUL operand (ex_a_fwd into the multiplier) ---
    li   a2, 7
    li   t5, 3
    li   t6, 5
    mv   a3, t5                # old operand = 3
    mv   a3, t6                # young operand = 5
    mul  s0, a3, a2          # 5 * 7 = 35  (21 if bug forwards 3)
    CHECK_EQ s0, 35, 8

    # --- 9) CSR source (csrrw rs1 -> csr_wsrc = ex_a_fwd) ---
    mv   a4, s8
    mv   a4, s9                # young: a4 = YOUNG
    csrw mscratch, a4         # mscratch <- ex_a_fwd(a4) -> must be YOUNG
    csrr s0, mscratch
    CHECK_EQ s0, 0x600D600D, 9

    # --- 10) x0 GUARD: an in-flight "write" to x0 must NOT forward a value ---
    add  x0, s9, x0           # discards into x0 (hardwired 0)
    add  s0, x0, x0           # consumer reads x0 -> must be 0, never forwarded
    CHECK_EQ s0, 0, 10

    # --- 11) LOAD-RESULT forward (wl path) + load-use interlock ---
    la   a5, good_word
    lw   a6, 0(a5)           # a6 = YOUNG (load)
    add  s0, a6, x0          # load-use: forward the load result
    CHECK_EQ s0, 0x600D600D, 11

    TEST_PASS

.section .data
.align 4
good_word: .word 0x600D600D
bad_word:  .word 0x0BAD0BAD
scratch0:  .word 0
slotA:     .word 0
slotB:     .word 0
