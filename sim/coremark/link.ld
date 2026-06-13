/* link.ld — flat single-region layout for CoreMark on the custom core.
 * The TB loads the image into both the I-BRAM (fetch) and D-BRAM (data); text is
 * fetched from one, data/bss/stack accessed in the other, at matching addresses.
 * Reset = 0x0. SPDX-License-Identifier: Apache-2.0 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 256K
}

SECTIONS {
  .text : {
    *(.text.start)
    *(.text*)
    *(.rodata*) *(.srodata*)
  } > RAM

  .data : {
    . = ALIGN(4);
    _data_start = .;
    *(.data*) *(.sdata*)
    _data_end = .;
  } > RAM

  .tohost ALIGN(64) : { *(.tohost) } > RAM

  .bss (NOLOAD) : {
    . = ALIGN(4);
    _bss_start = .;
    *(.bss*) *(.sbss*) *(COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > RAM

  . = ALIGN(16);
  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
