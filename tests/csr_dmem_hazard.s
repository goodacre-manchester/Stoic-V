# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# csr_dmem_hazard.s — the CRV-surfaced CSR-RMW divergence (stall-coincident).
#
# A CSR read-modify-write instruction reads the OLD CSR value into rd and commits the
# new value at its EX edge. But when the CSR instruction is HELD IN EX by a `dmem_stall`
# (an older load/store awaiting its DReady in the single-outstanding gap), an ungated
# `csr_we` stays asserted across the freeze: the write commits on the first stalled
# cycle, so on the cycle the instruction finally advances `csr_rdata` (-> rd) is already
# the NEW value. rd then captures the modified CSR instead of the architectural OLD value.
#
# To raise dmem_stall WHILE the CSR is in EX, the CSR must be the IMMEDIATE next
# instruction after the SECOND of two back-to-back memory accesses (one isolated access
# followed by a non-memory op does NOT stall). The write SOURCE is therefore pre-loaded
# BEFORE the memory traffic. This is the exact CRV pattern (`sh; lhu; csrrw rd,mscratch`,
# seed 4) that long random programs hit and the simple forward case (csr_hazard.s) does
# not. Each block seeds mscratch, then runs back-to-back accesses + an immediate
# `csrrw rd, mscratch, rs` whose rd MUST equal the OLD mscratch. SIM: +dfree=1 +max=20000
.include "test.h"
.section .text.start
.global _start
_start:
    li   t3, 0x100             # scratch data base (< TOHOST 0x7000)

    # ---- block 1: store; store; csrrw (immediate) ----
    li   s1, 0xAAAA0000
    csrrw x0, mscratch, s1     # mscratch = 0xAAAA0000
    li   s2, 0xBBBB0000        # write source, ready BEFORE the memory ops
    sw   x0, 0(t3)
    sw   x0, 4(t3)             # back-to-back accesses -> dmem_stall gap
    csrrw s3, mscratch, s2     # IMMEDIATE: s3 := OLD mscratch; mscratch := 0xBBBB0000
    CHECK_EQ s3, 0xAAAA0000, 1

    # ---- block 2: store; load; csrrw (immediate) — the exact CRV seed-4 shape ----
    li   s1, 0x12340000
    csrrw x0, mscratch, s1     # mscratch = 0x12340000
    li   s4, 0x99990000        # write source ready early
    li   s5, 0x5A5A5A5A
    sw   s5, 8(t3)
    lw   s6, 8(t3)             # store->load back-to-back -> dmem_stall
    csrrw s7, mscratch, s4     # IMMEDIATE: s7 := OLD mscratch; mscratch := 0x99990000
    CHECK_EQ s7, 0x12340000, 2
    CHECK_EQ s6, 0x5A5A5A5A, 3 # the load itself must still be correct

    # ---- block 3: csrrs (set) immediate after back-to-back loads ----
    li   s1, 0x0000FFFF
    csrrw x0, mscratch, s1     # mscratch = 0x0000FFFF
    li   s8, 0xFFFF0000        # set-mask source ready early
    lw   x0, 12(t3)
    lw   x0, 16(t3)            # back-to-back loads -> dmem_stall
    csrrs s9, mscratch, s8     # IMMEDIATE: s9 := OLD mscratch (0x0000FFFF); mscratch := 0xFFFFFFFF
    CHECK_EQ s9, 0x0000FFFF, 4

    # ---- block 4: csrrc (clear) immediate after back-to-back stores ----
    li   s1, 0xFFFFFFFF
    csrrw x0, mscratch, s1     # mscratch = 0xFFFFFFFF
    li   s10, 0x0F0F0F0F       # clear-mask source ready early
    sw   x0, 20(t3)
    sw   x0, 24(t3)            # back-to-back stores -> dmem_stall
    csrrc s11, mscratch, s10   # IMMEDIATE: s11 := OLD mscratch (0xFFFFFFFF); mscratch := 0xF0F0F0F0
    CHECK_EQ s11, 0xFFFFFFFF, 5

    TEST_PASS
