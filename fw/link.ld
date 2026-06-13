/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 John Goodacre */
/* link.ld — firmware layout for the custom core.
 * Reset vector = ORIGIN(IMEM). Use 0x00000000 for the app-direct build, or set
 * to 0x00007800 for the baked boot-ROM build (C_BASE_VECTORS).
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 64K   /* instruction BRAM (fetch)   */
  DMEM (rw) : ORIGIN = 0x10000000, LENGTH = 64K   /* data BRAM                  */
}

SECTIONS {
  .text : {
    *(.text.start)
    *(.text*)
    *(.rodata*)
  } > IMEM

  .data : {
    _data_start = .;
    *(.data*)
    _data_end = .;
  } > DMEM

  .bss (NOLOAD) : {
    _bss_start = .;
    *(.bss*)
    *(COMMON)
    _bss_end = .;
  } > DMEM

  _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
}
