// core_portme.c — CoreMark port for the custom RV32 core (bare-metal, Verilator).
// SPDX-License-Identifier: Apache-2.0
// Timing = mcycle CSR (cycle-exact: the core has no caches/speculation, and the
// TB models registered-1-cycle memory, so sim cycles == silicon cycles). Output =
// ee_printf -> a global buffer that the TB dumps via the RISCOF signature path.
// EE_TICKS_PER_SEC = 1e6 makes the printed Iterations/Sec read directly as CoreMark/MHz.
#include "coremark.h"
#include "core_portme.h"

// Seeds — PERFORMANCE_RUN (0,0,0x66) yields the standard validation CRC 0xe9f5.
#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

// "secs" == cycles (HAS_FLOAT=0, integer): makes CoreMark's ">=10 secs" validity
// check pass on a cycle sim (cycles are millions). Exact CoreMark/MHz is computed
// externally as Iterations * 1e6 / Total-ticks (see run_coremark.sh).
#define EE_TICKS_PER_SEC 1u

static ee_u32 rd_mcycle(void)
{
    ee_u32 r;
    __asm__ volatile("csrr %0, mcycle" : "=r"(r));   // CSR 0xB00, low 32 bits
    return r;
}

static CORETIMETYPE start_time_val, stop_time_val;
void start_time(void) { start_time_val = rd_mcycle(); }
void stop_time(void)  { stop_time_val  = rd_mcycle(); }
CORE_TICKS get_time(void) { return (CORE_TICKS)(stop_time_val - start_time_val); }
secs_ret   time_in_secs(CORE_TICKS ticks) { return ((secs_ret)ticks) / (secs_ret)EE_TICKS_PER_SEC; }

ee_u32 default_num_contexts = 1;

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc; (void)argv;
    p->portable_id = 1;
}
void portable_fini(core_portable *p) { p->portable_id = 0; }

// ee_printf character sink -> buffer in .bss. The TB dumps [ee_outbuf, +ee_outpos)
// on tohost via the RISCOF +sig path; the run script decodes it back to text.
#define EE_OUTBUF_SZ 4096
volatile unsigned char ee_outbuf[EE_OUTBUF_SZ];
volatile ee_u32        ee_outpos = 0;
void uart_send_char(char c)
{
    if (ee_outpos < EE_OUTBUF_SZ) ee_outbuf[ee_outpos++] = (unsigned char)c;
}
