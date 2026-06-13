#ifndef _FABRICRV_RISCV_TEST_H
#define _FABRICRV_RISCV_TEST_H
// Custom riscv-test-env for the custom RV32 core.
//
// The stock p-env (riscv-test-env/p) signals completion with `ecall` handled by
// a trap_vector, and enters tests via `mret` to U-mode. This v1 core is M-mode
// only and omits precise synchronous exceptions (README §10.3 carve-out), so
// `ecall` does not trap. This env therefore runs bare-metal in M-mode and
// signals pass/fail with a DIRECT store to `tohost` (which tb_top watches via
// +tohost): value 1 = pass, (TESTNUM<<1)|1 (odd, >1) = fail — matching the unit
// TB's completion semantics. Links at 0x8000_0000 (see link.ld) to match the
// arch sim build (RESET_VEC/MEM_BASE).

//-----------------------------------------------------------------------
// Mode/init macros. Tests invoke `init` from RVTEST_CODE_BEGIN; we need no
// per-mode setup (M-mode already, no FP/V), so init is empty.
//-----------------------------------------------------------------------
#define RVTEST_RV32U   .macro init; .endm
#define RVTEST_RV32M   .macro init; .endm
#define RVTEST_RV32S   .macro init; .endm
#define RVTEST_RV64U   .macro init; .endm
#define RVTEST_RV64M   .macro init; .endm

#define TESTNUM gp

//-----------------------------------------------------------------------
// Code begin: reset entry at 0x8000_0000 (start of .text.init), no traps.
//-----------------------------------------------------------------------
#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                           \
        .align 6;                                                      \
        .globl rvtest_entry_point;                                     \
rvtest_entry_point:                                                    \
        .globl _start;                                                 \
_start:                                                                \
        init;

#define RVTEST_CODE_END

//-----------------------------------------------------------------------
// Pass/fail: direct tohost store, then spin (tb_top ends the run on the store).
//-----------------------------------------------------------------------
#define RVTEST_PASS                                                    \
        li TESTNUM, 1;                                                 \
        sw TESTNUM, tohost, t0;                                        \
1:      j 1b;

#define RVTEST_FAIL                                                    \
        slli TESTNUM, TESTNUM, 1;                                      \
        ori  TESTNUM, TESTNUM, 1;                                      \
        sw TESTNUM, tohost, t0;                                        \
1:      j 1b;

//-----------------------------------------------------------------------
// Data section + HTIF-style tohost/fromhost (a plain word here) + signature.
//-----------------------------------------------------------------------
#define RVTEST_DATA_BEGIN                                              \
        .pushsection .tohost,"aw",@progbits;                          \
        .align 6; .global tohost; tohost: .dword 0;                   \
        .align 6; .global fromhost; fromhost: .dword 0;               \
        .popsection;                                                  \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END  .align 4; .global end_signature; end_signature:

#endif // _FABRICRV_RISCV_TEST_H
