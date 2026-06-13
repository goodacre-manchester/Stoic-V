# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# fwd_loaduse.s — load-result (wl-path) forwarding into EVERY consumer type, under
# the load-use interlock STALL. The escaped 2026-06 forwarding bug was
# stall-sensitive (it bit when a forward source updated while the consumer's rs was
# held steady by a stall — e.g. a load awaiting the bus), so the load-use regime is
# exactly where a forward-sensitisation defect shows. fwd_matrix.s covers the
# un-stalled M+W overlap; this covers the load->consumer matrix:
#   load -> ALU, branch, store-data, store-base (pointer-chase store), MUL, CSR.
# SIM: +max=20000
.include "test.h"
.section .text.start
.global _start
_start:
    la   s0, vword              # holds 0x600D600D
    la   s1, slot               # writable scratch
    li   s3, 0x600D600D         # comparison constant (also store data)

    # --- 1) load -> ALU ---
    lw   a0, 0(s0)
    add  s2, a0, x0            # consume the load result (load-use stall)
    CHECK_EQ s2, 0x600D600D, 1

    # --- 2) load -> branch operand ---
    lw   a0, 0(s0)
    bne  a0, s3, .Llu2_fail     # forwarded load value must equal s3
    j    .Llu2_ok
.Llu2_fail:
    TEST_FAIL 2
.Llu2_ok:

    # --- 3) load -> store data ---
    lw   a0, 0(s0)
    sw   a0, 0(s1)            # store the just-loaded value
    lw   s2, 0(s1)
    CHECK_EQ s2, 0x600D600D, 3

    # --- 4) load -> store BASE (pointer-chase store) ---
    la   s4, slotptr           # slotptr holds &slot2
    lw   a1, 0(s4)            # a1 = &slot2 (load result used as a base)
    sw   s3, 0(a1)            # store via the loaded base
    la   s5, slot2
    lw   s2, 0(s5)
    CHECK_EQ s2, 0x600D600D, 4

    # --- 5) load -> MUL operand ---
    la   s6, vsmall            # holds 7
    lw   a0, 0(s6)
    li   a3, 6
    mul  s2, a0, a3           # 7 * 6 = 42
    CHECK_EQ s2, 42, 5

    # --- 6) load -> CSR source ---
    lw   a0, 0(s0)
    csrw mscratch, a0         # mscratch <- forwarded load value
    csrr s2, mscratch
    CHECK_EQ s2, 0x600D600D, 6

    TEST_PASS

.section .data
.align 4
vword:   .word 0x600D600D
vsmall:  .word 7
slot:    .word 0
slot2:   .word 0
slotptr: .word slot2          # holds the address of slot2
