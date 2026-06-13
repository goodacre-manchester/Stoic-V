# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# storeload.s — REGRESSION for the P7.1 store->load stale read.
# A STORE immediately followed by a back-to-back stack-restore LOAD sequence (a
# function epilogue: `sw ...; lw ra,off(sp); lw s0,...; ...`), on the edge-detect
# slave (+dedge) that HOLDS DReady from the store into the first load's address
# cycle. The first load (ra) must capture its OWN word, not the prior store's held
# bus nor the following load's value. loadgap.s (load->load) does NOT exercise this;
# backtoback.s only runs store->load on the LEVEL slave. Each restore slot holds a
# distinct sentinel so an off-by-one capture (ra <- the next slot, the reported
# 0x5fc -> 0x4 wedge) is caught. Also feeds the first restored value into a JALR to
# mirror the failing `ret`.
# Runs against +dfree — the canonical free-running registered BRAM read (tile.sv
# data_rd_q), the slave timing that exposes the P7.1 store->load stale read.
# SIM: +dfree=1 +max=20000
.include "test.h"
.section .text.start
.global _start
_start:
    la   sp, stk + 128       # stack pointer (restore slots are at positive offsets)
    la   s6, faraway         # STORE target, a DIFFERENT region from the stack
    li   s0, 0xDEADBEEF      # store data

    # pre-fill the restore slots with distinct sentinels (well ahead of the epilogue)
    li   t0, 0x000005FC
    sw   t0, 60(sp)          # slot for ra  (their 0x5fc)
    li   t0, 0x00000004
    sw   t0, 56(sp)          # next slot    (their wrong value 0x4)
    li   t0, 0xAAAA0003
    sw   t0, 52(sp)
    li   t0, 0xBBBB0002
    sw   t0, 48(sp)

    # --- the failing epilogue: STORE then back-to-back restore LOADS, no bubble ---
    sw   s0, 0(s6)           # STORE (far) — holds DReady into the next load's cycle
    lw   a0, 60(sp)          # restore #1 (ra) -> MUST be 0x000005FC, not 0x4
    lw   a1, 56(sp)          # restore #2      -> 0x00000004
    lw   a2, 52(sp)          # restore #3      -> 0xAAAA0003
    lw   a3, 48(sp)          # restore #4      -> 0xBBBB0002
    CHECK_EQ a0, 0x000005FC, 1
    CHECK_EQ a1, 0x00000004, 2
    CHECK_EQ a2, 0xAAAA0003, 3
    CHECK_EQ a3, 0xBBBB0002, 4

    # --- mirror the real wedge: a STORE then `lw ra` then `ret` (jalr ra) ---
    la   t1, .Lreturn_ok     # the correct return target
    sw   t1, 64(sp)          # save it on the stack
    sw   s0, 0(s6)           # STORE immediately before the ra restore
    lw   ra, 64(sp)          # restore ra (must be &.Lreturn_ok)
    jr   ra                  # ret — must land at .Lreturn_ok, not elsewhere
    TEST_FAIL 5              # fell through / wrong target
.Lreturn_ok:

    TEST_PASS

.section .data
.align 4
faraway: .word 0
.align 6
stk:     .zero 256
