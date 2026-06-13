# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# dmem_matrix.s — kernel for the dmem_stall × {IRQ / branch / muldiv} interaction gate.
#
# Each individual axis is already covered (irq-stress sweeps MEI across all pipeline
# positions; lmb-contract/scoreboard cover the data-stall; fwd_stall covers forwarding
# under back-pressure). This kernel forces the THREE coincidences with an active
# `dmem_stall` (an outstanding load/store in the single-outstanding gap) and is swept by
# run_dmem_matrix.sh under stalling/free-running slaves with the MEI injected at every
# cycle:
#   1. dmem_stall × IRQ entry   — a memory access is outstanding when the MEI fires
#      (take_irq must defer until the access retires in order: take_irq & ~dmem_stall).
#   2. dmem_stall × branch      — a taken branch sits in EX while the preceding load
#      stalls in MEM (the redirect must be deferred until DReady).
#   3. dmem_stall × muldiv      — an INDEPENDENT mul/div enters EX and counts while the
#      preceding load stalls (the multiplier counter must freeze on `.hold(dmem_stall)`).
#
# The transparent ISR writes only s11; the architectural result (s1) must be 638 (0x27E)
# for EVERY injection cycle on EVERY compliant slave timing, and the interrupt must be
# taken (the wait-spin turns a missed IRQ into a TIMEOUT). SIM: +irq_at=24 +irq_clr=94 +max=30000
.include "test.h"
.section .text.start
.global _start
_start:
    la   a0, isr
    csrw mtvec, a0
    li   s11, 0                # ISR fired-count (the ONLY register the ISR writes)
    csrsi mstatus, 0x8         # mstatus.MIE = 1
    li   a1, 0x800
    csrs mie, a1               # mie.MEIE = 1 (bit 11)

    li   t0, 0x4000            # scratch data base
    li   s1, 0                 # architectural checksum

    # --- block 1: back-to-back stores then loads (store→load + dmem_stall window) ---
    li   t1, 0x100
    li   t2, 0x055
    sw   t1, 0(t0)
    sw   t2, 4(t0)             # b2b stores
    lw   t3, 0(t0)             # b2b loads (the read must track its own address)
    lw   t4, 4(t0)
    add  s1, s1, t3            # += 0x100
    add  s1, s1, t4            # += 0x055  -> s1 = 0x155 (341)

    # --- coincidence 2 (branch × dmem_stall): a taken branch right behind a stalling load
    lw   t5, 0(t0)             # this load stalls in MEM under a slow/free-running slave...
    bge  s1, x0, 1f            # ...while THIS taken branch is in EX (redirect deferred)
    addi s1, s1, 0x400         # poison — skipped (s1 >= 0 always); detectable if mis-taken
1:
    # --- coincidence 3 (div × dmem_stall): INDEPENDENT div counts while a load stalls ---
    li   a3, 256
    li   a4, 6
    lw   t6, 4(t0)             # independent load -> stalls in MEM...
    div  s5, a3, a4            # ...while this div (operands ready, no load-use) counts in EX
    add  s1, s1, s5            # 256/6 = 42 -> s1 = 383

    # --- coincidence 4 (mul × dmem_stall): INDEPENDENT mul while a load stalls ---
    li   a5, 85
    li   a6, 3
    lw   t6, 0(t0)             # independent load -> stalls...
    mul  s6, a5, a6            # ...while this mul counts in EX. 85*3 = 255
    add  s1, s1, s6            # -> s1 = 638 (0x27E)

    # --- loop with a load body to widen the injection window (more dmem_stall windows) ---
    li   a6, 0
    li   a7, 8
2:  lw   t6, 0(t0)
    addi a6, a6, 1
    blt  a6, a7, 2b

    # --- require the interrupt to have been taken, then check transparency ---
3:  beq  s11, x0, 3b           # spin until the ISR fires (missed IRQ -> TIMEOUT -> FAIL)
    CHECK_EQ s1, 638, 1        # result must be invariant to slave timing AND interrupts
    TEST_PASS

    .align 2
isr:
    addi s11, s11, 1           # transparent handler: touches only s11, then return
    mret
