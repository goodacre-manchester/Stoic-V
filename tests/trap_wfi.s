# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# trap_wfi.s — wfi must be a legal instruction (NOP-or-sleep), never trap; execution continues.
.include "test.h"
.section .text.start
.global _start
_start:
    li   s0, 0x1234
    wfi                      # legal NOP in v1
    addi s0, s0, 1           # must execute after wfi
    CHECK_EQ s0, 0x1235, 1
    TEST_PASS
