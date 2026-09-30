/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Entry for rbhost as an AE350 program (platform_ae350.c).  The boot ROM
 * calls _start as uint32_t _start(void) on its stack with the caches and
 * FPU enabled; the flat image does not include .bss, so it is cleared here.
 */
	.section .text.start, "ax"
	.globl	_start
_start:
	addi	sp, sp, -16
	sw	ra, 12(sp)
	.option push
	.option norelax
	la	gp, __global_pointer$
	.option pop
	la	t0, __bss_start
	la	t1, __bss_end
1:	bgeu	t0, t1, 2f
	sw	zero, 0(t0)
	addi	t0, t0, 4
	j	1b
2:	call	ae350_main
	lw	ra, 12(sp)
	addi	sp, sp, 16
	ret
