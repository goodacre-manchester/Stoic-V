/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 John Goodacre */
# start.S — reset + trap vector for the custom RV32 core (M-mode, direct mtvec).
# Build with the riscv GCC: -march=rv32im_zba_zbb_zbs -mabi=ilp32 -mcmodel=medany -nostartfiles
# Reset vector = C_BASE_VECTORS (0x0 app-direct, or 0x7800 boot-ROM build via link.ld).

    .section .text.start, "ax"
    .global _start
_start:
    la      sp, _stack_top
    # zero .bss
    la      t0, _bss_start
    la      t1, _bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    # install trap vector (direct mode)
    la      t0, _trap_entry
    csrw    mtvec, t0
    # enable machine external interrupt (MEIE) + global (MIE)
    li      t0, (1 << 11)        # mie.MEIE
    csrw    mie, t0
    csrsi   mstatus, (1 << 3)    # mstatus.MIE
    call    main
hang:
    wfi
    j       hang

    # ---- trap entry: single common stack (MIE cleared on entry, no nesting) ----
    .align  2
    .global _trap_entry
_trap_entry:
    addi    sp, sp, -16*4
    sw      ra,  0*4(sp)
    sw      t0,  1*4(sp)
    sw      t1,  2*4(sp)
    sw      t2,  3*4(sp)
    sw      a0,  4*4(sp)
    sw      a1,  5*4(sp)
    sw      a2,  6*4(sp)
    sw      a3,  7*4(sp)
    sw      a4,  8*4(sp)
    sw      a5,  9*4(sp)
    sw      a6, 10*4(sp)
    sw      a7, 11*4(sp)
    sw      t3, 12*4(sp)
    sw      t4, 13*4(sp)
    sw      t5, 14*4(sp)
    sw      t6, 15*4(sp)
    call    isr_handler
    lw      ra,  0*4(sp)
    lw      t0,  1*4(sp)
    lw      t1,  2*4(sp)
    lw      t2,  3*4(sp)
    lw      a0,  4*4(sp)
    lw      a1,  5*4(sp)
    lw      a2,  6*4(sp)
    lw      a3,  7*4(sp)
    lw      a4,  8*4(sp)
    lw      a5,  9*4(sp)
    lw      a6, 10*4(sp)
    lw      a7, 11*4(sp)
    lw      t3, 12*4(sp)
    lw      t4, 13*4(sp)
    lw      t5, 14*4(sp)
    lw      t6, 15*4(sp)
    addi    sp, sp, 16*4
    mret                        # restores mstatus.MIE from MPIE
