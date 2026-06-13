/* SPDX-License-Identifier: Apache-2.0
 * link.ld — cosim-fw C workloads. Base 0x8000_0000 to match Spike + the arch sim
 * (RESET_VEC/MEM_BASE); _start lands first in .text.init. The runner shifts the flat
 * image down to offset 0 for $readmemh (--change-addresses=-0x80000000). */
OUTPUT_ARCH( "riscv" )
ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) }
  . = ALIGN(0x40);
  .tohost    : { *(.tohost) }
  . = ALIGN(0x40);
  .text      : { *(.text*) }
  .rodata    : { *(.rodata*) *(.srodata*) }
  . = ALIGN(0x10);
  .data      : { *(.data*) *(.sdata*) }
  . = ALIGN(0x10);
  _bss_start = .;
  .bss       : { *(.bss*) *(.sbss*) *(COMMON) }
  _bss_end   = .;
  . = ALIGN(0x10);
  . = . + 0x4000;        /* 16 KiB stack */
  _stack_top = .;
  _end = .;
}
