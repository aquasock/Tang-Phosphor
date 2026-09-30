/* SPDX-License-Identifier: GPL-3.0-only
 * qemu-riscv32 entry for bench_qemu.c; QEMU zeroes .bss. */
	.section .text.start_qemu, "ax"
	.globl	_start_qemu
_start_qemu:
	.option push
	.option norelax
	la	gp, __global_pointer$
	.option pop
	call	bench_qemu_main
1:	j	1b
