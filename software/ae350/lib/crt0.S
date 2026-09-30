/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Entry of a program loaded by the AE350 boot ROM, which calls _start as
 * uint32_t _start(void) on its own stack with the caches and FPU enabled.
 * Sets the program's global pointer, clears .bss, calls main(), and returns
 * its value.  gp is not preserved; the loader does not use it.
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
2:	call	main
	lw	ra, 12(sp)
	addi	sp, sp, 16
	ret
