/* SPDX-License-Identifier: GPL-3.0-only
 *
 * AE350 reset entry at 0x80000000.  Enables both L1 caches (Tang-PSX
 * core-reference AE350-002) and the FPU (mstatus.FS = Initial), which
 * Rockbox codecs built for ilp32d need, sets up the stack and trap vector
 * in the DDR3 region reserved for the loader, copies .data, clears .bss,
 * and runs the loader.  The loader is built without a global pointer, so
 * programs may use gp freely.
 */
	.section .text.start, "ax"
	.globl	_start
_start:
	li	t0, 3
	csrs	0x7ca, t0
	fence.i
	li	t0, 0x2000
	csrs	mstatus, t0
	csrw	fcsr, zero
	la	sp, __stack_top
	la	t0, trap_entry
	csrw	mtvec, t0

	la	t0, __data_load
	la	t1, __data_start
	la	t2, __data_end
1:	bgeu	t1, t2, 2f
	lw	t3, 0(t0)
	sw	t3, 0(t1)
	addi	t0, t0, 4
	addi	t1, t1, 4
	j	1b
2:	la	t1, __bss_start
	la	t2, __bss_end
3:	bgeu	t1, t2, 4f
	sw	zero, 0(t1)
	addi	t1, t1, 4
	j	3b
4:	call	boot_main
5:	j	5b

	/* Any trap is reported and halts; Tang-Control restarts the CPU. */
	.align	2
	.globl	trap_entry
trap_entry:
	la	sp, __stack_top
	csrr	a0, mcause
	csrr	a1, mepc
	csrr	a2, mtval
	call	boot_trap
6:	wfi
	j	6b
