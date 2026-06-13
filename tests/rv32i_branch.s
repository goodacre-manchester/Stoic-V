# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# rv32i_branch.s — all branch conditions (taken/not), backward loop, jal/jalr/auipc.
.include "test.h"
.section .text.start
.global _start
_start:
    li   s0, 7
    li   s1, 7
    beq  s0, s1, 1f
    TEST_FAIL 1
1:  li   s1, 8
    beq  s0, s1, 2f
    j    3f
2:  TEST_FAIL 2
3:  bne  s0, s1, 4f
    TEST_FAIL 3
4:  li   s0, -1
    li   s1, 1
    blt  s0, s1, 5f
    TEST_FAIL 4
5:  bge  s1, s0, 6f
    TEST_FAIL 5
6:  li   s0, 1
    li   s1, -1
    bltu s0, s1, 7f
    TEST_FAIL 6
7:  bgeu s1, s0, 8f
    TEST_FAIL 7
8:  # backward loop
    li   s2, 0
    li   s3, 5
9:  addi s2, s2, 1
    blt  s2, s3, 9b
    CHECK_EQ s2, 5, 8
    # jal / jalr
    jal  ra, sub1
    CHECK_EQ s4, 0xABC, 9
    # auipc executes
    auipc s5, 0
    TEST_PASS
sub1:
    li   s4, 0xABC
    ret
