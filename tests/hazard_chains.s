# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# hazard_chains.s — deeper data-hazard chains and muldiv result/operand
# forwarding, complementing fwd_matrix.s (single M+W overlap). Covers:
#   - multi-writer RAW chains (EX->EX forward applied repeatedly),
#   - pointer-chase load->load (a load result used as the next load's base),
#   - mul result forwarded to an immediate consumer and to the next mul operand,
#   - div/rem corner cases (divide-by-zero, signed INT_MIN/-1 overflow) with the
#     deterministic RISC-V results, and a forwarded youngest-writer div operand.
# All latencies are operand-independent (determinism); the values are checked.
# SIM: +max=20000
.include "test.h"
.section .text.start
.global _start
_start:
    # --- 1) 4-deep RAW chain into a consumer (repeated EX->EX forward) ---
    li   a0, 0x100
    addi a0, a0, 1          # 0x101 (each depends on the previous)
    addi a0, a0, 1          # 0x102
    addi a0, a0, 1          # 0x103 (youngest)
    add  s0, a0, x0        # consumer -> 0x103
    CHECK_EQ s0, 0x103, 1

    # --- 2) pointer-chase: a load result is the NEXT load's base (load->load AGEN) ---
    la   a1, ptr_word       # ptr_word holds &target_word
    lw   a2, 0(a1)          # a2 = &target_word  (load result = an address)
    lw   s0, 0(a2)          # base a2 from the load result -> reads target_word
    CHECK_EQ s0, 0x600D600D, 2

    # --- 3) MUL result forwarded to an immediate consumer (md result forward) ---
    li   a3, 6
    li   a4, 7
    mul  a5, a3, a4        # 42
    add  s0, a5, x0        # consume the mul result the next cycle
    CHECK_EQ s0, 42, 3

    # --- 4) MUL result feeds the next MUL's operand ---
    li   a6, 3
    mul  a6, a6, a6        # 9
    mul  s0, a6, a6        # 81 (operand from the previous mul result)
    CHECK_EQ s0, 81, 4

    # --- 5) divide-by-zero (deterministic: div -> -1, rem -> dividend) ---
    li   a0, 12345
    li   a1, 0
    div  s0, a0, a1        # -1
    CHECK_EQ s0, 0xFFFFFFFF, 5
    rem  s1, a0, a1        # dividend
    CHECK_EQ s1, 12345, 6

    # --- 6) signed overflow INT_MIN / -1 (div -> INT_MIN, rem -> 0) ---
    li   a0, 0x80000000
    li   a1, -1
    div  s0, a0, a1        # INT_MIN
    CHECK_EQ s0, 0x80000000, 7
    rem  s1, a0, a1        # 0
    CHECK_EQ s1, 0, 8

    # --- 7) youngest-writer DIV operand (M+W overlap into the divider) ---
    li   a6, 100
    li   a7, 5
    mv   a4, a0            # old dividend (= INT_MIN from above; the wrong value)
    mv   a4, a6            # young dividend = 100
    div  s0, a4, a7        # 100 / 5 = 20
    CHECK_EQ s0, 20, 9

    TEST_PASS

.section .data
.align 4
ptr_word:    .word target_word     # holds the address of target_word
target_word: .word 0x600D600D
