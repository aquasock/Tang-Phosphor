/* SPDX-License-Identifier: GPL-3.0-only
 *
 * AE350 boot ROM: code and constants in the 8 KiB block-RAM ROM at the
 * reset vector; data, .bss, and the stack in the top 1 MiB of DDR3, which
 * programs leave to the loader.  Programs run on this stack.
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
	rom (rx)  : ORIGIN = 0x80000000, LENGTH = 8K
	ram (rw)  : ORIGIN = 0x7ff00000, LENGTH = 1M
}

SECTIONS
{
	.text : { KEEP(*(.text.start)) *(.text .text.*) } > rom
	.rodata : { *(.rodata .rodata.* .srodata .srodata.*) . = ALIGN(4); } > rom
	__data_load = LOADADDR(.rodata) + SIZEOF(.rodata);
	.data : AT(__data_load) {
		__data_start = .;
		*(.data .data.* .sdata .sdata.*)
		. = ALIGN(4);
		__data_end = .;
	} > ram
	ASSERT(__data_load + SIZEOF(.data) <= ORIGIN(rom) + LENGTH(rom), "boot ROM overflow")
	.bss (NOLOAD) : {
		__bss_start = .;
		*(.sbss .sbss.* .bss .bss.* COMMON)
		. = ALIGN(4);
		__bss_end = .;
	} > ram
	__stack_top = ORIGIN(ram) + LENGTH(ram);
	/DISCARD/ : { *(.eh_frame) *(.comment) *(.riscv.attributes) }
}
