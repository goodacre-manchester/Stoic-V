/* link.ld — RISCOF DUT (our core). Byte-identical layout to the Spike
 * reference plugin's env/link.ld so the two builds place every instruction and
 * datum at the same address; PC-relative signatures (auipc/jal/jalr) then
 * compare equal. The arch-test sim boots the core at 0x80000000 (RESET_VEC) and
 * its BRAM window is based there (MEM_BASE); run_dut.sh shifts the flat image
 * down to offset 0 for $readmemh. */
OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)

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
  .data.string : { *(.data.string)}
  .bss : { *(.bss) }
  _end = .;
}
