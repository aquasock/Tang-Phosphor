/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Links one Rockbox codec as a static ELF executable at CODEC_BASE.  The ELF
 * entry address is the codec's struct codec_header (__header), which the
 * host checks for magic, target ID, and API version before calling it.
 * No __global_pointer$ is defined, so the codec never relaxes accesses
 * against the host's gp.
 */
INCLUDE memory.ld
OUTPUT_ARCH(riscv)
ENTRY(__header)

PHDRS
{
	image PT_LOAD FLAGS(7);
}

SECTIONS
{
	. = CODEC_BASE;
	.text : { *(.text .text.*) } :image
	.rodata : { *(.rodata .rodata.*) *(.srodata .srodata.*) } :image
	.data : { *(.data .data.*) *(.sdata .sdata.*) } :image
	.bss : { *(.sbss .sbss.*) *(.bss .bss.*) *(COMMON) } :image
	__codec_image_end = .;
	ASSERT(__codec_image_end <= CODEC_BASE + CODEC_SIZE, "codec exceeds CODEC_SIZE")
	/DISCARD/ : { *(.comment) *(.note .note.*) *(.eh_frame) *(.riscv.attributes) }
}
