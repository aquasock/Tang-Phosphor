/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Entry point for the rbhost qemu-riscv32 (linux-user) build.  QEMU's ELF
 * loader provides the stack, argc/argv, and a zeroed .bss; the hardware
 * build will provide its own reset entry.
 */
	.section .text.start, "ax"
	.globl _start
_start:
	.option push
	.option norelax
	la	gp, __global_pointer$
	.option pop
	lw	a0, 0(sp)
	addi	a1, sp, 4
	call	main
	call	exit
1:	j	1b
