# crt0.S — Embench-IoT startup + cycle/instret triggers + signature dump for the
# custom RV32 core. Flat image at 0x0 (TB loads it into both I- and D-BRAM).
# start_trigger/stop_trigger snapshot mcycle+minstret; on exit the four counters
# plus a pass/fail code are written to begin_signature, which the TB dumps via
# +sig (RISCOF hex words). Modelled on embench examples/riscv32/rv32wallyverilog.
# SPDX-License-Identifier: GPL-3.0-or-later
    .section .text.start, "ax"
    .global _start
_start:
.option push
.option norelax
    la      gp, __global_pointer$
.option pop
    la      sp, _stack_top
    # zero .bss (covers each benchmark's static heap + buffers)
    la      t0, _bss_start
    la      t1, _bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:  call    main                    # returns !correct (0 = verified OK)
    # publish signature: startcycle, stopcycle, startinst, stopinst, code
    la      t2, begin_signature
    lw      t3, startcycle
    lw      t4, stopcycle
    lw      t5, startinst
    lw      t6, stopinst
    sw      t3, 0(t2)
    sw      t4, 4(t2)
    sw      t5, 8(t2)
    sw      t6, 12(t2)
    slli    a0, a0, 1               # main()=0 -> code 1 (PASS); =1 -> code 3 (FAIL)
    addi    t0, a0, 1
    sw      t0, 16(t2)
    la      t1, tohost              # halt the TB
    li      t2, 1
    sw      t2, 0(t1)
3:  j       3b

    .global start_trigger
start_trigger:
    la      t2, startcycle
    j       record_trigger
    .global stop_trigger
stop_trigger:
    la      t2, stopcycle
record_trigger:
    csrr    t0, mcycle
    csrr    t1, minstret
    sw      t0, 0(t2)
    sw      t1, 4(t2)
    ret

    .data
    .align 2
startcycle: .word 0
startinst:  .word 0
stopcycle:  .word 0
stopinst:   .word 0

    .section .tohost, "aw", @progbits
    .align  6
    .global tohost
tohost: .word 0
    .align  6
    .global begin_signature
begin_signature:
    .fill 5,4,0
