# SPDX-License-Identifier: Apache-2.0
# csr_hazard.s — probe the CRV-surfaced CSR divergence: a csrrw whose WRITE SOURCE was
# computed by the immediately-preceding instruction, in a back-to-back CSR RMW context.
# If the core forwards the STALE source to the CSR write, mscratch gets the wrong value
# and the read-back fails. SIM: +max=20000
.include "test.h"
.section .text.start
.global _start
_start:
    csrrw x0, mscratch, x0     # mscratch = 0
    li   t3, 0
    csrrc t3, mscratch, t3     # back-to-back CSR RMW (mscratch stays 0; t3 = 0)
    li   s3, 0x0000AAAA        # the value we want written
    li   a1, 0x11110000        # OLD a1 (the stale value)
    add  a1, x0, s3            # YOUNGEST a1 = 0x0000AAAA
    csrrw a5, mscratch, a1     # mscratch <= a1 (must be 0x0000AAAA, not the stale 0x11110000)
    csrrw a1, mscratch, x0     # a1 = old mscratch (must be 0x0000AAAA)
    CHECK_EQ a1, 0x0000AAAA, 1

    # variant: csrrs source freshly computed
    csrrw x0, mscratch, x0     # mscratch = 0
    li   a2, 0x22220000        # old
    li   t4, 0x00005555
    or   a2, x0, t4            # youngest a2 = 0x00005555
    csrrs a6, mscratch, a2     # mscratch <= 0 | a2 = 0x00005555
    csrrw a2, mscratch, x0     # a2 = old mscratch = 0x00005555
    CHECK_EQ a2, 0x00005555, 2

    TEST_PASS
