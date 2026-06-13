# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# zb_bitmanip.s — Zba/Zbb/Zbs operations.
.include "test.h"
.section .text.start
.global _start
_start:
    # Zba
    li   s0, 5
    li   s1, 100
    sh1add s2, s0, s1        # 110
    CHECK_EQ s2, 110, 1
    sh2add s2, s0, s1        # 120
    CHECK_EQ s2, 120, 2
    sh3add s2, s0, s1        # 140
    CHECK_EQ s2, 140, 3
    # Zbb logic
    li   s0, 0xFF00
    li   s1, 0x0F0F
    andn s2, s0, s1          # 0xF000
    CHECK_EQ s2, 0xF000, 4
    orn  s2, s0, s1          # 0xFFFFFFF0
    CHECK_EQ s2, 0xFFFFFFF0, 5
    xnor s2, s0, s1          # 0xFFFF0FF0
    CHECK_EQ s2, 0xFFFF0FF0, 6
    # counts
    li   s0, 0x00010000
    clz  s2, s0              # 15
    CHECK_EQ s2, 15, 7
    ctz  s2, s0              # 16
    CHECK_EQ s2, 16, 8
    li   s0, 0xF0F0F0F0
    cpop s2, s0              # 16
    CHECK_EQ s2, 16, 9
    # min/max
    li   s0, -5
    li   s1, 3
    min  s2, s0, s1          # -5
    CHECK_EQ s2, -5, 10
    max  s2, s0, s1          # 3
    CHECK_EQ s2, 3, 11
    minu s2, s0, s1          # 3
    CHECK_EQ s2, 3, 12
    maxu s2, s0, s1          # 0xFFFFFFFB
    CHECK_EQ s2, 0xFFFFFFFB, 13
    # sext/zext
    li   s0, 0x80
    sext.b s2, s0            # 0xFFFFFF80
    CHECK_EQ s2, 0xFFFFFF80, 14
    li   s0, 0x8000
    sext.h s2, s0            # 0xFFFF8000
    CHECK_EQ s2, 0xFFFF8000, 15
    li   s0, 0xFFFF1234
    zext.h s2, s0            # 0x1234
    CHECK_EQ s2, 0x1234, 16
    # rotate
    li   s0, 0x80000001
    rori s2, s0, 1           # 0xC0000000
    CHECK_EQ s2, 0xC0000000, 17
    li   s1, 4
    rol  s2, s0, s1          # rotate left 4: 0x80000001 -> 0x00000018
    CHECK_EQ s2, 0x00000018, 18
    # orc.b / rev8
    li   s0, 0x00120034
    orc.b s2, s0             # 0x00FF00FF
    CHECK_EQ s2, 0x00FF00FF, 19
    li   s0, 0x11223344
    rev8 s2, s0              # 0x44332211
    CHECK_EQ s2, 0x44332211, 20
    # Zbs
    li   s0, 0
    bseti s2, s0, 5          # 0x20
    CHECK_EQ s2, 0x20, 21
    li   s0, 0xFF
    bclri s2, s0, 0          # 0xFE
    CHECK_EQ s2, 0xFE, 22
    binvi s2, s0, 8          # 0x1FF
    CHECK_EQ s2, 0x1FF, 23
    bexti s2, s0, 7          # 1
    CHECK_EQ s2, 1, 24
    li   s0, 0
    li   s1, 4
    bset s2, s0, s1          # 0x10
    CHECK_EQ s2, 0x10, 25
    TEST_PASS
