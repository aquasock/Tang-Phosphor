/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Chain loader for testing how a program image must be committed before it
 * is run.  Linked high (0x7e000000), it requests a TPI image from the BL616
 * through the file-request mailbox (ae350_request.h), as `phosphor run
 * /ae350/chainload.tpi <image.tpi>` serves it, copies the payload to its load
 * address through the data cache as the boot ROM does, checks the payload's
 * CRC-32 there, and calls its entry:
 *
 *   CHAIN_FLUSH 0  fence rw, rw; fence.i -- the boot ROM's sequence
 *   CHAIN_FLUSH 1  the whole L1 data cache written back and invalidated
 *                  (L1D_WBINVAL_ALL), a 1 ms wait, then fence.i -- Tang-PSX's
 *   CHAIN_FLUSH 2  mode 0, then entered with the boot ROM's stack pointer
 *
 * USER(10) is the image's payload size, USER(11) its CRC as copied, and
 * USER(12) the mode.  A program that returns has its result returned.
 */
#include <stdint.h>

#include "ae350.h"
#include "ae350_request.h"

#ifndef CHAIN_FLUSH
#define CHAIN_FLUSH 0
#endif

#define CHUNK (64u << 10)
#define TIMEOUT_TICKS (10u * AE350_TIME_HZ)

static uint8_t buffer[CHUNK + 4u] __attribute__((aligned(32)));

#ifdef CHAIN_TIMER
/* The timer interrupt's handler: the registers of the interrupted code into
 * USER(0..7) and the trap CSRs into USER(13..15), then a halt.  It saves
 * nothing, since the program is not resumed. */
__attribute__((naked, aligned(4))) static void dump_trap(void)
{
	__asm__ volatile (
		"lui t6, 0xe8000\n\t"
		"sw s2, 0x40(t6)\n\t"
		"sw a2, 0x44(t6)\n\t"
		"sw a3, 0x48(t6)\n\t"
		"sw a4, 0x4c(t6)\n\t"
		"sw s5, 0x50(t6)\n\t"
		"sw s6, 0x54(t6)\n\t"
		"sw s9, 0x58(t6)\n\t"
		"sw sp, 0x5c(t6)\n\t"
		"csrr t5, mcause\n\t"
		"sw t5, 0x74(t6)\n\t"
		"csrr t5, mepc\n\t"
		"sw t5, 0x78(t6)\n\t"
		"li t5, 0x99\n\t"
		"sw t5, 0x20(t6)\n\t"
		"1: j 1b\n\t");
}
#endif

uint32_t main(void)
{
	struct ae350_image_header header;
	uint32_t crc = 0xffffffffu;

	AE350_REG(AE350_USER(12)) = CHAIN_FLUSH;
#ifdef CHAIN_TIMER
	/* A program-counter sample: the machine timer (PLMT at 0xe6000000,
	 * mtime at +0, hart 0's mtimecmp at +8, counting at the 75 MHz bus
	 * clock) interrupts 3 s from now, and the boot ROM's trap handler
	 * records mcause, mepc and mtval in USER(13..15).  USER(8) is mtime's
	 * low word here, to show the timer counts. */
	{
		volatile uint32_t *plmt = (volatile uint32_t *)0xe6000000u;
		uint32_t hi, lo;
		do {
			hi = plmt[1];
			lo = plmt[0];
		} while (hi != plmt[1]);
		uint64_t when = ((uint64_t)hi << 32 | lo) + 3ull * AE350_TIME_HZ;
		AE350_REG(AE350_USER(8)) = lo;
		plmt[3] = 0xffffffffu;
		plmt[2] = (uint32_t)when;
		plmt[3] = (uint32_t)(when >> 32);
		AE350_CSR_WRITE(mtvec, (uint32_t)(uintptr_t)dump_trap);
		__asm__ volatile ("csrs mie, %0" :: "r"(1u << 7));
		__asm__ volatile ("csrs mstatus, %0" :: "r"(1u << 3));
	}
#endif
#ifdef CHAIN_TRIGGER
	/* Trap on any execute, load or store below address 32: an mcontrol
	 * trigger (debug spec 0.13.2: type 2, match 3 "less than", M-mode),
	 * enabled in M-mode by tcontrol.mte (Tang-Phosphor core-reference, A25
	 * debug triggers).  The boot ROM's trap handler then records mcause,
	 * mepc and mtval in USER(13..15).  USER(9) is tdata1 as it reads back. */
	AE350_CSR_WRITE(0x7a0, 0u);
	AE350_CSR_WRITE(0x7a1, 0u);
	AE350_CSR_WRITE(0x7a2, 32u);
	AE350_CSR_WRITE(0x7a1, (2u << 28) | (3u << 7) | (1u << 6) | 7u);
	__asm__ volatile ("csrs 0x7a5, %0" :: "r"(8u));
	AE350_REG(AE350_USER(9)) = AE350_CSR_READ(0x7a1);
#endif
	ae350_request(0, sizeof(header));
	if (ae350_request_receive(buffer, sizeof(buffer), TIMEOUT_TICKS) != (int32_t)sizeof(header))
		return 0xbad00001u;
	__builtin_memcpy(&header, buffer, sizeof(header));
	if (header.magic != AE350_IMAGE_MAGIC || header.load < AE350_DDR3_BASE ||
	    header.load + header.payload_bytes > 0x7e000000u)
		return 0xbad00002u;
	AE350_REG(AE350_USER(10)) = header.payload_bytes;

	uint32_t *to = (uint32_t *)header.load;
	for (uint32_t at = 0; at < header.payload_bytes; at += CHUNK) {
		uint32_t want = header.payload_bytes - at < CHUNK ? header.payload_bytes - at : CHUNK;
		ae350_request(sizeof(header) + at, want);
		if (ae350_request_receive(buffer, sizeof(buffer), TIMEOUT_TICKS) != (int32_t)want)
			return 0xbad00003u;
		for (uint32_t i = 0; i < want / 4u; ++i) {
			uint32_t word = ((uint32_t *)buffer)[i];
			*to++ = word;
			crc ^= word;
			for (int bit = 0; bit < 32; ++bit)
				crc = (crc >> 1) ^ (0xedb88320u & -(crc & 1u));
		}
	}
	AE350_REG(AE350_USER(11)) = ~crc;
	if (~crc != header.payload_crc)
		return 0xbad00004u;

	ae350_puts(CHAIN_FLUSH ? "chain flush\n" : "chain fence\n");
#if CHAIN_FLUSH == 1
	ae350_flush_dcache();
	uint32_t start = AE350_REG(AE350_TIME_LOW);
	while (AE350_REG(AE350_TIME_LOW) - start < AE350_TIME_HZ / 1000u)
		;
#endif
	__asm__ volatile ("fence rw, rw\n\tfence.i" ::: "memory");
#if CHAIN_FLUSH == 2
	/* The boot ROM's stack pointer at the call (boot_main's 96-byte frame
	 * below 0x80000000); the program is entered there and never returns. */
	__asm__ volatile ("mv sp, %0\n\tjr %1" :: "r"(0x7fffffa0u), "r"(header.entry) : "memory");
	__builtin_unreachable();
#endif
	return ((uint32_t (*)(void))header.entry)();
}
