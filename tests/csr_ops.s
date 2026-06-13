# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# csr_ops.s — Zicsr semantics: CSRRW/S/C(+I), read-old/write-new, x0-source
# no-write, WARL masking (mstatus/mtvec/mepc/mie), read-only CSRs, counters.
# Self-checking via test.h (no interrupts needed).
.include "test.h"
.section .text.start
.global _start
_start:
    # --- mscratch: plain RW read-back ---
    li   t0, 0x12345678
    csrw mscratch, t0
    csrr s0, mscratch
    CHECK_EQ s0, 0x12345678, 1

    # --- CSRRW returns OLD value to rd, writes new ---
    li   t1, 0x0BCD0000
    csrrw s1, mscratch, t1          # s1 = old, mscratch = new
    CHECK_EQ s1, 0x12345678, 2
    csrr s2, mscratch
    CHECK_EQ s2, 0x0BCD0000, 3

    # --- CSRRS sets bits (OR) ---
    li   t0, 0x000000FF
    csrs mscratch, t0
    csrr s3, mscratch
    CHECK_EQ s3, 0x0BCD00FF, 4

    # --- CSRRC clears bits (AND ~) ---
    li   t0, 0x0000000F
    csrc mscratch, t0
    csrr s4, mscratch
    CHECK_EQ s4, 0x0BCD00F0, 5

    # --- CSRRS with x0 source must NOT write ---
    csrrs s5, mscratch, x0
    CHECK_EQ s5, 0x0BCD00F0, 6
    csrr s6, mscratch
    CHECK_EQ s6, 0x0BCD00F0, 7

    # --- immediate forms (5-bit zero-extended) ---
    csrwi mscratch, 0x15            # = 0x15
    csrr s7, mscratch
    CHECK_EQ s7, 0x15, 8
    csrsi mscratch, 0x02            # |= 0x2 -> 0x17
    csrr s8, mscratch
    CHECK_EQ s8, 0x17, 9
    csrci mscratch, 0x04            # &= ~0x4 -> 0x13
    csrr s9, mscratch
    CHECK_EQ s9, 0x13, 10

    # --- mstatus: MIE writable, MPP reads 11 ---
    csrsi mstatus, 0x8              # set MIE (bit3)
    csrr t1, mstatus
    CHECK_EQ t1, 0x00001808, 11     # MPP=11 (12:11), MIE=1 (3)

    # --- misa read-only (MXL=1, I+M) ---
    csrr s10, misa
    CHECK_EQ s10, 0x40001100, 12
    li   t0, 0xFFFFFFFF
    csrw misa, t0                   # ignored
    csrr s11, misa
    CHECK_EQ s11, 0x40001100, 13

    # --- mtvec WARL: low 2 bits forced 0 (direct mode) ---
    li   t0, 0x00001007
    csrw mtvec, t0
    csrr t1, mtvec
    CHECK_EQ t1, 0x00001004, 14

    # --- mepc WARL: bit0 forced 0 ---
    li   t0, 0x00002003
    csrw mepc, t0
    csrr t1, mepc
    CHECK_EQ t1, 0x00002002, 15

    # --- mhartid read-only 0 ---
    csrr t1, mhartid
    CHECK_EQ t1, 0x0, 16

    # --- mie: only MEIE (bit11) writable ---
    li   t0, 0xFFFFFFFF
    csrw mie, t0
    csrr t1, mie
    CHECK_EQ t1, 0x00000800, 17

    # --- minstret monotonically increases ---
    csrr s0, minstret
    nop
    nop
    nop
    csrr s1, minstret
    bltu s0, s1, 1f
    TEST_FAIL 18
1:
    # --- mcycle monotonically increases ---
    csrr s0, mcycle
    nop
    nop
    csrr s1, mcycle
    bltu s0, s1, 2f
    TEST_FAIL 19
2:
    TEST_PASS
