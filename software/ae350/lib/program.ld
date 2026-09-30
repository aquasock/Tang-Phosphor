/* SPDX-License-Identifier: GPL-3.0-only
 *
 * AE350 program loaded by the boot ROM at the start of DDR3.  The image
 * payload is the flat binary of the loadable sections; .bss is cleared by
 * crt0.S.  Everything above __end up to 0x7ff00000 is free for the program.
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
	ddr (rwx) : ORIGIN = 0x40000000, LENGTH = 0x3ff00000
}

SECTIONS
{
	.text : { KEEP(*(.text.start)) *(.text .text.*) } > ddr
	.rodata : ALIGN(8) { *(.rodata .rodata.* .srodata .srodata.*) } > ddr
	.data : ALIGN(8) {
		*(.data .data.*)
		__global_pointer$ = . + 0x800;
		*(.sdata .sdata.*)
		. = ALIGN(4);
	} > ddr
	.bss (NOLOAD) : ALIGN(8) {
		__bss_start = .;
		*(.sbss .sbss.* .bss .bss.* COMMON)
		. = ALIGN(4);
		__bss_end = .;
	} > ddr
	__end = .;
	/DISCARD/ : { *(.eh_frame) *(.comment) *(.riscv.attributes) }
}
