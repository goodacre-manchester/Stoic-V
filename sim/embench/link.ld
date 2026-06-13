/* link.ld — flat single-region layout for Embench-IoT on the custom core.
 * Same model as the CoreMark harness: the TB loads the image into both the
 * I-BRAM (fetch) and D-BRAM (data) at matching addresses; reset = 0x0. The 512K
 * region is the *simulation* memory (generous, so any kernel fits); the 24/16
 * KiB end-target budget is validated separately from each ELF's section sizes.
 * SPDX-License-Identifier: GPL-3.0-or-later */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 512K
}

SECTIONS {
  .text : {
    *(.text.start)
    *(.text*)
    *(.rodata*) *(.srodata*)
  } > RAM

  .data : {
    . = ALIGN(8);
    _data_start = .;
    __global_pointer$ = . + 0x800;
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
