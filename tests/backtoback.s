# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# backtoback.s — REGRESSION for the integrator-reported "load captured one cycle early
# on a back-to-back access" bug. A load that immediately follows another bus access
# (store or load) must return its OWN addressed word, not the previous transaction's
# value, even when the registered-1-cycle slave still asserts Ready in the load's
# issue cycle (Ready = registered AS, held across back-to-back accesses).
#
# All address registers are set up well ahead so the store;load;load;load sequence
# issues with NO bubble (no load-use / address dependency between them).
# SIM: +max=20000
.include "test.h"
.section .text.start
.global _start
_start:
    la   s0, scratch        # store target (distinct from the loads)
    la   s1, vals           # load base
    li   t3, 0xDEADBEEF
    li   t4, 0xCAFEF00D

    # --- case 1: store immediately followed by back-to-back loads ---
    # store holds Ready into load a0's issue cycle; each load must read its own word.
    sw   t3, 0(s0)          # store -> scratch
    lw   a0, 0(s1)          # vals[0] = 0x11111111  (load right after the store)
    lw   a1, 4(s1)          # vals[1] = 0x22222222  (back-to-back load)
    lw   a2, 8(s1)          # vals[2] = 0x33333333  (back-to-back load)
    CHECK_EQ a0, 0x11111111, 1
    CHECK_EQ a1, 0x22222222, 2
    CHECK_EQ a2, 0x33333333, 3

    # --- case 2: store, then a single load of the OTHER address ---
    # the classic shifted-by-one symptom: a0 must NOT come back as scratch's value.
    sw   t4, 0(s0)          # store -> scratch (0xCAFEF00D)
    lw   a3, 12(s1)         # vals[3] = 0x44444444
    CHECK_EQ a3, 0x44444444, 4

    # --- case 3: pure back-to-back loads (no store ahead) ---
    lw   a4, 0(s1)          # 0x11111111
    lw   a5, 4(s1)          # 0x22222222
    lw   a6, 8(s1)          # 0x33333333
    lw   a7, 12(s1)         # 0x44444444
    CHECK_EQ a4, 0x11111111, 5
    CHECK_EQ a5, 0x22222222, 6
    CHECK_EQ a6, 0x33333333, 7
    CHECK_EQ a7, 0x44444444, 8

    # --- case 4: store to scratch then read scratch back (RAW through memory,
    # back-to-back). The registered slave commits the store at the edge; the load
    # must observe the just-written value (its own transaction), not stale. ---
    li   t5, 0x5A5A5A5A
    sw   t5, 0(s0)
    lw   t6, 0(s0)          # immediately reload scratch
    CHECK_EQ t6, 0x5A5A5A5A, 9

    TEST_PASS

.section .data
.align 4
scratch: .word 0
vals:    .word 0x11111111
         .word 0x22222222
         .word 0x33333333
         .word 0x44444444
