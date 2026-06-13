# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# wcet_probe.s — WCET latency probe. One dependent-op chain, parameterized by the
# assembler:  --defsym OP=<0..3>  --defsym K=<count>  --defsym A=<seed0> --defsym B=<seed1>
#   OP=0 div   OP=1 mul   OP=2 load-use   OP=3 taken-branch
# The TB prints total CYCLES on completion; run_wcet.sh assembles the SAME source at K
# and 2K and takes the slope (cyc2K-cycK)/K = the per-op latency (fixed prologue/fill/
# drain cancels). It also assembles div/mul at fixed K with DIFFERENT operand seeds and
# asserts the cycle count is IDENTICAL — the data-independence (WCET) contract for the
# operand-dependent-risk FUs. SIM: +max=400000
.include "test.h"
.ifndef OP
.equ OP, 0
.endif
.ifndef K
.equ K, 64
.endif
.ifndef A
.equ A, 0x40000000
.endif
.ifndef B
.equ B, 7
.endif
.section .text.start
.global _start
_start:
    li   t3, 0x400              # scratch base (< TOHOST 0x7000) for load-use
    li   a1, B
    li   a0, A
    sw   a0, 0(t3)              # seed the load-use slot

.if OP == 0                     # ---- divide: dependent chain (non-early-terminating) ----
    .rept K
    div  a0, a0, a1
    .endr
.elseif OP == 1                 # ---- multiply: dependent chain ----
    .rept K
    mul  a0, a0, a1
    .endr
.elseif OP == 2                 # ---- load-use: each load feeds the next address-independent add, dependent ----
    .rept K
    lw   a0, 0(t3)
    add  a0, a0, a1
    .endr
.else                           # ---- taken branch: each unconditionally taken (P_REDIR refetch) ----
    .rept K
    beq  x0, x0, .+8
    add  a0, a0, a1             # skipped (branch target is the next insn after this)
    .endr
.endif

    TEST_PASS                   # TB prints CYCLES=<total>
