# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# regzero.s — GPRs power up to a DEFINED 0 (Xilinx LUTRAM init value), so the
# simulation matches FPGA silicon. Reads several never-written GPRs and asserts
# they read 0. In Verilator (2-state) an unwritten reg is 0, so this passes; on a
# real FPGA the regfile is distributed RAM that configures to 0, so it reads 0;
# but in Vivado xsim (4-state) `rv_regfile.regs` powers up X unless given an
# initial value — so WITHOUT the fix this FAILs under xsim, and WITH it (regfile
# `initial` = 0) it passes, closing the xsim-vs-silicon gap. An X here is exactly
# what propagates into a load base (-> wrong/0 address) or a ret/jalr (-> PC 0)
# when firmware touches an untouched register, the P7.1 wedge mechanism.
# SIM: +max=20000
.include "test.h"
.section .text.start
.global _start
_start:
    # OR together a spread of never-written GPRs (callee-saved + temporaries that
    # a library-refactored firmware is most likely to touch before its own write).
    or   s0, x9,  x18         # s2, s3-range, never written
    or   s0, s0,  x21
    or   s0, s0,  x24
    or   s0, s0,  x27
    or   s0, s0,  x28
    CHECK_EQ s0, 0, 1

    # an unwritten register used as a LOAD BASE must address 0 (defined), not X.
    lw   s1, 0(x19)          # base x19 unwritten -> must be 0 -> reads mem[0]
    # mem[0] is the first instruction word of this image; just require it is DEFINED
    # and equal to itself (no X): xor with itself = 0.
    xor  s2, s1, s1
    CHECK_EQ s2, 0, 2

    TEST_PASS
