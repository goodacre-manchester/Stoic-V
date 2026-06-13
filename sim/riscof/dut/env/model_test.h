#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H
// model_test.h — RISCOF DUT (our core). Byte-identical to the shipped
// spike_simple plugin's model_test.h so the DUT and reference builds emit the
// same code/data (hence the same signatures). The only difference is who dumps
// the signature: Spike does it via HTIF (+signature); our core has no HTIF, so
// the SIM writes it (the test still ends by storing 1 to the `tohost` symbol,
// which tb_top watches via +tohost). See sim/riscof/dut/.
#if XLEN == 64
  #define ALIGNMENT 3
#else
  #define ALIGNMENT 2
#endif

#ifndef RVMODEL_PMP_GRAIN
  #define RVMODEL_PMP_GRAIN   0
#endif

#ifndef RVMODEL_NUM_PMPS
  #define RVMODEL_NUM_PMPS    16
#endif


#define RVMODEL_DATA_SECTION \
        .pushsection .tohost,"aw",@progbits;                            \
        .align 8; .global tohost; tohost: .dword 0;                     \
        .align 8; .global fromhost; fromhost: .dword 0;                 \
        .popsection;                                                    \
        .align 8; .global begin_regstate; begin_regstate:               \
        .word 128;                                                      \
        .align 8; .global end_regstate; end_regstate:                   \
        .word 4;

//RV_COMPLIANCE_HALT
#define RVMODEL_HALT    ;\
li x1, 1                ;\
1:                      ;\
    sw x1, tohost, t2   ;\
    j 1b                ;\

#define RVMODEL_BOOT

//RV_COMPLIANCE_DATA_BEGIN
#define RVMODEL_DATA_BEGIN                                              \
  RVMODEL_DATA_SECTION                                                        \
  .align ALIGNMENT;\
  .global begin_signature; begin_signature:

//RV_COMPLIANCE_DATA_END
#define RVMODEL_DATA_END                                                      \
.align ALIGNMENT;\
  .global end_signature; end_signature:

//RVTEST_IO_INIT
#define RVMODEL_IO_INIT
//RVTEST_IO_WRITE_STR
#define RVMODEL_IO_WRITE_STR(_R, _STR)
//RVTEST_IO_CHECK
#define RVMODEL_IO_CHECK()
//RVTEST_IO_ASSERT_GPR_EQ
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
//RVTEST_IO_ASSERT_SFPR_EQ
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
//RVTEST_IO_ASSERT_DFPR_EQ
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

#define RVMODEL_SET_MSW_INT

#define RVMODEL_CLEAR_MSW_INT

#define RVMODEL_CLEAR_MTIMER_INT

#define RVMODEL_CLEAR_MEXT_INT


#endif // _COMPLIANCE_MODEL_H
