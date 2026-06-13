# start.S — minimal bare-metal startup for CoreMark on the custom RV32 core.
# SPDX-License-Identifier: Apache-2.0
# Set stack, zero .bss, run main(), then store 1 to `tohost` (the TB halts on it).
    .section .text.start, "ax"
    .global _start
_start:
    la      sp, _stack_top
    # zero .bss (includes the ee_printf output buffer)
    la      t0, _bss_start
    la      t1, _bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:  call    main
    # completion: store 1 to tohost (PASS marker; correctness is the CRC in output)
    la      t1, tohost
    li      t2, 1
    sw      t2, 0(t1)
3:  j       3b

    .section .tohost, "aw", @progbits
    .align  6
    .global tohost
tohost: .word 0
