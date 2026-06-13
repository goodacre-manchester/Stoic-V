# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# loadgap.s — the EXACT shape the P7.1 integrator refactor reported as failing:
# `load(header) ; <ALU decode> ; load(payload)` — a load, an ALU op, then a second
# load from a DIFFERENT address. Run against the edge-detect slave (+dedge, the
# real host tile). Asserts the second load returns its OWN word (header read does
# not bleed into payload, and payload is not stale/0). Also covers load;op;op;load
# and a longer header-then-payload chain, to exercise any held-Ready capture path.
# SIM: +dedge=1 +max=20000
.include "test.h"
.section .text.start
.global _start
_start:
    la   s0, hdr               # header word
    la   s1, pay0              # payload[0]
    la   s2, pay1              # payload[1]

    # --- 1) load ; ALU ; load (the reported shape) ---
    lw   a0, 0(s0)            # header = 0x000A0011  (decoded: dest/len)
    addi t3, a0, 0            # <ALU decode> on the header (1 op between the loads)
    lw   a1, 0(s1)            # payload[0] must be 0x7711_0001, NOT stale/0
    CHECK_EQ a0, 0x000A0011, 1
    CHECK_EQ a1, 0x77110001, 2

    # --- 2) load ; ALU ; ALU ; load (2 ops between) ---
    lw   a2, 0(s0)
    srli t4, a2, 4
    andi t5, a2, 0xff
    lw   a3, 0(s2)            # payload[1] must be 0x7711_0002
    CHECK_EQ a3, 0x77110002, 3

    # --- 3) header decode then back-to-back payload reads (the forward loop) ---
    lw   a4, 0(s0)           # header
    addi t6, a4, 0           # decode
    lw   a5, 0(s1)           # payload[0]
    lw   a6, 0(s2)           # payload[1] (back-to-back after payload[0])
    CHECK_EQ a5, 0x77110001, 4
    CHECK_EQ a6, 0x77110002, 5

    TEST_PASS

.section .data
.align 4
hdr:  .word 0x000A0011
pay0: .word 0x77110001
pay1: .word 0x77110002
