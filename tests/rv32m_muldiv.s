# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# rv32m_muldiv.s — M extension: mul/mulh*/div*/rem* incl. edge cases.
.include "test.h"
.section .text.start
.global _start
_start:
    li   s0, 6
    li   s1, 7
    mul  s2, s0, s1
    CHECK_EQ s2, 42, 1
    li   s0, -1
    li   s1, -1
    mulh s2, s0, s1          # high of 1
    CHECK_EQ s2, 0, 2
    mul  s2, s0, s1          # low of 1
    CHECK_EQ s2, 1, 3
    mulhu s2, s0, s1         # 0xFFFFFFFE
    CHECK_EQ s2, 0xFFFFFFFE, 4
    mulhsu s2, s0, s1        # (-1)*0xFFFFFFFF high = 0xFFFFFFFF
    CHECK_EQ s2, 0xFFFFFFFF, 5
    li   s0, 100
    li   s1, 7
    div  s2, s0, s1          # 14
    CHECK_EQ s2, 14, 6
    rem  s2, s0, s1          # 2
    CHECK_EQ s2, 2, 7
    li   s0, -100
    li   s1, 7
    div  s2, s0, s1          # -14 (toward zero)
    CHECK_EQ s2, -14, 8
    rem  s2, s0, s1          # -2
    CHECK_EQ s2, -2, 9
    li   s0, 123
    li   s1, 0
    div  s2, s0, s1          # -1
    CHECK_EQ s2, -1, 10
    rem  s2, s0, s1          # 123
    CHECK_EQ s2, 123, 11
    li   s0, -1
    li   s1, 2
    divu s2, s0, s1          # 0x7FFFFFFF
    CHECK_EQ s2, 0x7FFFFFFF, 12
    li   s0, 0x80000000
    li   s1, -1
    div  s2, s0, s1          # overflow -> INT_MIN
    CHECK_EQ s2, 0x80000000, 13
    rem  s2, s0, s1          # 0
    CHECK_EQ s2, 0, 14
    # back-to-back mul (dependency through s2)
    li   s0, 3
    mul  s2, s0, s0          # 9
    mul  s2, s2, s0          # 27
    CHECK_EQ s2, 27, 15
    TEST_PASS
