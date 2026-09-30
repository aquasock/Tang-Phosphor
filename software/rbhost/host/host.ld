/* SPDX-License-Identifier: GPL-3.0-only */
INCLUDE memory.ld
OUTPUT_ARCH(riscv)
ENTRY(_start)

PHDRS
{
	image PT_LOAD FLAGS(7);
}

SECTIONS
{
	. = RAM_BASE;
	.text : { *(.text.start) *(.text .text.*) } :image
	.rodata : { *(.rodata .rodata.*) *(.srodata .srodata.*) } :image
	.data : {
		*(.data .data.*)
		__global_pointer$ = . + 0x800;
		*(.sdata .sdata.*)
	} :image
	.init_array : {
		PROVIDE_HIDDEN(__init_array_start = .);
		KEEP(*(SORT(.init_array.*))) KEEP(*(.init_array))
		PROVIDE_HIDDEN(__init_array_end = .);
	} :image
	.bss (NOLOAD) : {
		__bss_start = .;
		*(.sbss .sbss.*) *(.bss .bss.*) *(COMMON)
		. = ALIGN(4);
		__bss_end = .;
	} :image
	ASSERT(. <= CODEC_BASE, "host image overlaps the codec buffer")

	. = CODEC_BASE;
	.codec (NOLOAD) : { __codec_start = .; . += CODEC_SIZE; __codec_end = .; } :image

	. = HEAP_BASE;
	.heap (NOLOAD) : { __heap_start = .; . += HEAP_END - HEAP_BASE; __heap_end = .; } :image
}
