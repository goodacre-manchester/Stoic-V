# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# bus_patterns.s — LMB data-bus access-pattern coverage, run against the
# EDGE-DETECT slave (+dedge) that models a representative host tile (one access
# per rising strobe edge, Ready held while the request stays asserted). This is
# the slave on which the 2026-06 back-to-back stale-read bug manifested, so these
# patterns are a regression for the single-outstanding / one-edge-per-access
# handshake. backtoback.s covers store->load and pure back-to-back loads; this
# adds SUB-WORD byte-enable correctness across back-to-back stores, interleaved
# RAW chains to one address, and store/store/load WAW ordering.
#
# Defaulting +dedge here means `make test` (and the portable CI) exercise the
# edge slave too — not just the WSL-only `make lmb-contract` sweep. Determinism
# of the 1-cycle consecutive-access gap is unchanged (the values, not timing,
# are checked here).
# SIM: +dedge=1 +max=20000
.include "test.h"
.section .text.start
.global _start
_start:
    # --- 1) back-to-back SUB-WORD stores (byte enables) then a word load ---
    la   s0, w0
    li   t3, 0xAA
    li   t4, 0xBB
    sb   t3, 0(s0)          # byte 0
    sb   t4, 1(s0)          # byte 1 (back-to-back sub-word store, edge slave)
    lw   a0, 0(s0)          # assembled little-endian word
    CHECK_EQ a0, 0x0000BBAA, 1

    # --- 2) back-to-back HALFWORD stores then a word load ---
    la   s1, w1
    li   t5, 0x1234
    li   t6, 0x5678
    sh   t5, 0(s1)          # halfword 0
    sh   t6, 2(s1)          # halfword 1 (back-to-back)
    lw   a1, 0(s1)
    CHECK_EQ a1, 0x56781234, 2

    # --- 3) interleaved RAW chain to ONE address (st;ld;st;ld, all back-to-back) ---
    # each load must observe the immediately preceding store to the same word.
    la   s2, w2
    li   t3, 0x11112222
    li   t4, 0x33334444
    sw   t3, 0(s2)
    lw   a2, 0(s2)          # -> 0x11112222
    sw   t4, 0(s2)
    lw   a3, 0(s2)          # -> 0x33334444
    CHECK_EQ a2, 0x11112222, 3
    CHECK_EQ a3, 0x33334444, 4

    # --- 4) store/store/load/load: WAW to two words then read both back-to-back ---
    la   s3, w3              # two consecutive words (w3, w3+4)
    li   t5, 0x0A0A0A0A
    li   t6, 0x0B0B0B0B
    sw   t5, 0(s3)
    sw   t6, 4(s3)          # back-to-back store
    lw   a4, 0(s3)          # back-to-back load
    lw   a5, 4(s3)
    CHECK_EQ a4, 0x0A0A0A0A, 5
    CHECK_EQ a5, 0x0B0B0B0B, 6

    # --- 5) sub-word store then OVERLAPPING word read after a full word store ---
    # store a full word, then overwrite one byte, then read: byte-enable must
    # leave the other 3 bytes intact across the back-to-back accesses.
    la   s4, w4
    li   t3, 0xF0F0F0F0
    sw   t3, 0(s4)          # full word
    li   t4, 0x99
    sb   t4, 2(s4)          # overwrite byte 2 only (back-to-back)
    lw   a6, 0(s4)
    CHECK_EQ a6, 0xF099F0F0, 7

    TEST_PASS

.section .data
.align 4
w0: .word 0
w1: .word 0
w2: .word 0
w3: .word 0
    .word 0
w4: .word 0
