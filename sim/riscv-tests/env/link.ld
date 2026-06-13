/* link.ld — riscv-tests env for the custom core. Base 0x8000_0000 to match the
 * arch sim build (RESET_VEC/MEM_BASE); _start/rvtest_entry_point lands first in
 * .text.init at 0x8000_0000. run_riscv_tests.sh shifts the flat image down to
 * offset 0 for $readmemh. */
OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) }
  . = ALIGN(0x1000);
  .tohost : { *(.tohost) }
  . = ALIGN(0x1000);
  .text : { *(.text) }
  . = ALIGN(0x1000);
  .data : { *(.data) }
  .bss : { *(.bss) }
  _end = .;
}
