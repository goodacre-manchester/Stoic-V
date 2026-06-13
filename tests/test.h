# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# test.h — assembly test framework macros (GAS, .include'd by each test).
# Completion protocol: store to TOHOST (0x7000): value 1 = PASS, (n<<1)|1 = FAIL test #n.
# Scratch used by macros: t0,t1,t2. Put checked values in s-registers.
# Macros use unique \@ labels so test code may freely use numeric local labels (1f/2f/...).

.equ TOHOST, 0x00007000

.macro TEST_PASS
    li   t0, TOHOST
    li   t1, 1
    sw   t1, 0(t0)
.Lhang\@:
    j    .Lhang\@
.endm

.macro TEST_FAIL n
    li   t0, TOHOST
    li   t1, ((\n<<1)|1)
    sw   t1, 0(t0)
.Lhang\@:
    j    .Lhang\@
.endm

# CHECK_EQ reg, expected_imm, testnum  — fail with testnum if reg != expected
.macro CHECK_EQ reg, expect, num
    li   t2, \expect
    beq  \reg, t2, .Lok\@
    TEST_FAIL \num
.Lok\@:
.endm
