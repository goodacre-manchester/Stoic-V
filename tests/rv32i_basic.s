# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# rv32i_basic.s — RV32I arithmetic, logic, shifts, branches, loads/stores,
# load-use hazard, jal/jalr. Self-checking (see test.h).
.include "test.h"
.section .text.start
.global _start
_start:
    # ADD / SUB
    li   s0, 10
    li   s1, 20
    add  s2, s0, s1
    CHECK_EQ s2, 30, 1
    sub  s3, s1, s0
    CHECK_EQ s3, 10, 2
    # logic
    li   s0, 0xF0
    li   s1, 0x0F
    or   s2, s0, s1
    CHECK_EQ s2, 0xFF, 3
    and  s2, s0, s1
    CHECK_EQ s2, 0, 4
    xor  s2, s0, s1
    CHECK_EQ s2, 0xFF, 5
    # shifts
    li   s0, 1
    slli s2, s0, 4
    CHECK_EQ s2, 16, 6
    li   s0, 0x80000000
    srli s2, s0, 31
    CHECK_EQ s2, 1, 7
    srai s2, s0, 31
    CHECK_EQ s2, -1, 8
    # set-less-than
    li   s0, -1
    li   s1, 1
    slt  s2, s0, s1
    CHECK_EQ s2, 1, 9
    sltu s2, s0, s1
    CHECK_EQ s2, 0, 10
    # lui
    lui  s2, 0x12345
    CHECK_EQ s2, 0x12345000, 11
    # branches
    li   s0, 5
    li   s1, 5
    bne  s0, s1, 1f
    j    2f
1:  TEST_FAIL 12
2:  beq  s0, s1, 3f
    TEST_FAIL 13
3:
    # loads/stores
    li   s4, 0x4000
    li   s0, 0xDEADBEEF
    sw   s0, 0(s4)
    lw   s2, 0(s4)
    CHECK_EQ s2, 0xDEADBEEF, 14
    li   s0, 0xAB
    sb   s0, 4(s4)
    lbu  s2, 4(s4)
    CHECK_EQ s2, 0xAB, 15
    lb   s2, 4(s4)
    CHECK_EQ s2, 0xFFFFFFAB, 16
    li   s0, 0x1234
    sh   s0, 8(s4)
    lhu  s2, 8(s4)
    CHECK_EQ s2, 0x1234, 17
    # load-use hazard
    sw   s0, 12(s4)
    lw   s5, 12(s4)
    addi s2, s5, 1
    CHECK_EQ s2, 0x1235, 18
    # jal / jalr
    jal  ra, func1
    CHECK_EQ s2, 0x1111, 19
    TEST_PASS

func1:
    li   s2, 0x1111
    jalr x0, 0(ra)
