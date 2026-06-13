OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  . = 0x00000000;
  .text : { *(.text.start) *(.text*) }
  . = 0x00004000;
  .data : { *(.data*) *(.rodata*) }
  .bss  : { *(.bss*) *(COMMON) }
  _stack_top = 0x00008000;
}
