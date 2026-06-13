# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# crt0.S — minimal C runtime for the cosim-fw workloads (M-mode, bare metal, no libc).
# Sets sp, zeroes .bss, calls main(), then signals exit via the HTIF `tohost` symbol
# (value 1) — which both Spike (HTIF) and tb_top (+tohost=<addr> store-detect) halt on.
.section .text.init
.global _start
_start:
    la    sp, _stack_top
    # zero .bss
    la    t0, _bss_start
    la    t1, _bss_end
1:  bgeu  t0, t1, 2f
    sw    zero, 0(t0)
    addi  t0, t0, 4
    j     1b
2:  call  main
    # exit: write 1 to tohost (HTIF / tb_top end-of-test)
    la    t0, tohost
    li    t1, 1
    sw    t1, 0(t0)
3:  j     3b

.section .tohost, "aw", @progbits
.align 6
.global tohost
tohost:   .dword 0
.global fromhost
fromhost: .dword 0
