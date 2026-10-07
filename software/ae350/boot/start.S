/* SPDX-License-Identifier: GPL-3.0-only
 *
 * AE350 reset entry at 0x80000000.  Enables both L1 caches (Tang-PSX
 * core-reference AE350-002) and the FPU (mstatus.FS = Initial), which
 * Rockbox codecs built for ilp32d need, sets up the stack and trap vector
 * in the DDR3 region reserved for the loader, copies .data, clears .bss,
 * and runs the loader.  The loader is built without a global pointer, so
 * programs may use gp freely.
 *
 * The debug triggers are cleared here so nothing a previous program set can
 * fire in the loader; see boot_call for the one use the loader makes of them.
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
	csrw	0x7a5, zero		/* tcontrol: no M-mode triggers */
	li	t0, 5
0:	csrw	0x7a0, t0		/* tselect 5..0 */
	csrw	0x7a1, zero		/* tdata1: disabled */
	addi	t0, t0, -1
	bgez	t0, 0b

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

	/* uint32_t boot_call(uint32_t entry): run a program with its caller's
	 * frames guarded.  Everything from this frame up to __stack_top belongs
	 * to the loader -- including the image header, whose entry and load
	 * fields are the program's own entry address -- and a correct program
	 * never loads or stores there.  Two chained address triggers (debug
	 * spec 0.13: mcontrol, M-mode, load and store; trigger 0 at or above
	 * this frame, trigger 1 below __stack_top) raise a breakpoint exception
	 * on the instruction that does, which trap_entry reports with its pc.
	 * M-mode triggers fire only while tcontrol.mte is set, and a trap clears
	 * it, so the trap handler's own use of the stack cannot trigger again;
	 * mte is cleared before this frame is read back after the call.
	 *
	 * The stack the program will use is first filled with 0xbadbad00.  It
	 * holds whatever the loader's own calls left there -- among it the
	 * image's load address, which is also the program's entry -- and a
	 * program that reads a local before writing it would otherwise get that
	 * stale value.  Poisoned, a value used as an address faults at
	 * 0xbadbad00, which trap_entry records with the caller's ra. */
	.globl	boot_call
boot_call:
	addi	sp, sp, -16
	sw	ra, 12(sp)
	la	t0, __bss_end
	li	t1, 0xbadbad00
1:	bgeu	t0, sp, 2f
	sw	t1, 0(t0)
	addi	t0, t0, 4
	j	1b
2:
	csrw	0x7a0, zero
	csrw	0x7a1, zero
	csrw	0x7a2, sp
	li	t0, (2 << 28) | (2 << 7) | (1 << 11) | (1 << 6) | 3	/* >=, chain */
	csrw	0x7a1, t0
	li	t0, 1
	csrw	0x7a0, t0
	csrw	0x7a1, zero
	la	t0, __stack_top
	csrw	0x7a2, t0
	li	t0, (2 << 28) | (3 << 7) | (1 << 6) | 3		/* < */
	csrw	0x7a1, t0
	/* Triggers 2-5 trap any instruction fetched from the boot ROM while the
	 * program runs, except the jump into it and the return to
	 * boot_call_return: a program never executes loader code, and a trap
	 * enters trap_entry with mte already cleared, so neither the handler nor
	 * a normal return fires them.  Two chained ranges: [ROM start,
	 * boot_call_jump) and (boot_call_return, ROM end). */
	li	t2, (2 << 28) | (2 << 7) | (1 << 11) | (1 << 6) | (1 << 2)	/* >=, chain */
	li	t3, (2 << 28) | (3 << 7) | (1 << 6) | (1 << 2)			/* < */
	li	t0, 2
	csrw	0x7a0, t0
	csrw	0x7a1, zero
	la	t0, _start
	csrw	0x7a2, t0
	csrw	0x7a1, t2
	li	t0, 3
	csrw	0x7a0, t0
	csrw	0x7a1, zero
	la	t0, boot_call_jump
	csrw	0x7a2, t0
	csrw	0x7a1, t3
	li	t0, 4
	csrw	0x7a0, t0
	csrw	0x7a1, zero
	la	t0, boot_call_return + 4
	csrw	0x7a2, t0
	csrw	0x7a1, t2
	li	t0, 5
	csrw	0x7a0, t0
	csrw	0x7a1, zero
	la	t0, _start + 8192
	csrw	0x7a2, t0
	csrw	0x7a1, t3
	li	t0, 1 << 3
	csrw	0x7a5, t0		/* tcontrol.mte */
boot_call_jump:
	jalr	a0
boot_call_return:
	csrw	0x7a5, zero
	lw	ra, 12(sp)
	addi	sp, sp, 16
	ret

	/* Any trap is reported and halts; Tang-Control restarts the CPU.  ra and
	 * sp are passed as they were at the trap, so a breakpoint from
	 * boot_call's guard names its caller as well as the instruction. */
	.align	2
	.globl	trap_entry
trap_entry:
	mv	a3, ra
	mv	a4, sp
	la	sp, __stack_top
	csrr	a0, mcause
	csrr	a1, mepc
	csrr	a2, mtval
	call	boot_trap
6:	wfi
	j	6b
