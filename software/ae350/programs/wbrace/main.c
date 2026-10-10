/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Write-back then refill of the same cache line, straight away, through the
 * RAM bridge: whether a line fill can return DDR3's contents from before a
 * write-back of that line that was issued just ahead of it.
 *
 *   cctl      8 words stored to a line, the line written back and invalidated
 *             on its own (mcctlbeginaddr + L1D_VA_WBINVAL), then read back
 *   evict     8 words stored to a line and to the four other lines of its
 *             set (32 KiB 4-way, 8 KiB apart), so the first is evicted dirty,
 *             then the first read back
 *
 * Each runs over 64K lines with a fresh pattern per pass.  USER(0) and
 * USER(1) count mismatched words in each; USER(2) is the first bad address,
 * USER(3) the expected word and USER(4) the word read.  Returns 0x600d0000
 * plus the total mismatches, saturated at 0xffff.
 */
#include <stdint.h>

#include "ae350.h"

#define CSR_MCCTLBEGINADDR 0x7cb
#define CCTL_L1D_VA_WBINVAL 2u

#define BASE       0x60000000u
#define LINES      65536u
#define SET_STRIDE 8192u      /* 32 KiB / 4 ways */
#define PASSES     4u

static uint32_t bad[2];
static uint32_t first_addr, first_expected, first_observed;

static uint32_t pattern(uint32_t address, uint32_t pass)
{
	uint32_t x = address * 2654435761u ^ (pass + 1u) * 0x9e3779b9u;
	x ^= x >> 15;
	return x * 2246822519u;
}

static void check(int which, volatile uint32_t *line, uint32_t pass)
{
	for (uint32_t w = 0; w < 8u; ++w) {
		uint32_t expected = pattern((uint32_t)(uintptr_t)&line[w], pass);
		uint32_t observed = line[w];
		if (observed != expected) {
			if (!bad[0] && !bad[1]) {
				first_addr = (uint32_t)(uintptr_t)&line[w];
				first_expected = expected;
				first_observed = observed;
			}
			++bad[which];
		}
	}
}

static void fill(volatile uint32_t *line, uint32_t pass)
{
	for (uint32_t w = 0; w < 8u; ++w)
		line[w] = pattern((uint32_t)(uintptr_t)&line[w], pass);
}

uint32_t main(void)
{
	for (uint32_t i = 0; i < 13u; ++i)
		AE350_REG(AE350_USER(i)) = 0;
	ae350_puts("wbrace\n");
	for (uint32_t pass = 0; pass < PASSES; ++pass) {
		ae350_flush_dcache();
		for (uint32_t i = 0; i < LINES; ++i) {
			volatile uint32_t *line = (volatile uint32_t *)(BASE + 32u * i);
			fill(line, pass);
			AE350_CSR_WRITE(CSR_MCCTLBEGINADDR, (uint32_t)(uintptr_t)line);
			AE350_CSR_WRITE(AE350_CSR_MCCTLCOMMAND, CCTL_L1D_VA_WBINVAL);
			check(0, line, pass);
		}
		ae350_flush_dcache();
		for (uint32_t i = 0; i < LINES; ++i) {
			uint32_t base = BASE + 0x01000000u + 32u * (i % (SET_STRIDE / 32u)) +
					SET_STRIDE * 5u * (i / (SET_STRIDE / 32u));
			for (uint32_t k = 0; k < 5u; ++k)
				fill((volatile uint32_t *)(base + SET_STRIDE * k), pass);
			check(1, (volatile uint32_t *)base, pass);
		}
	}
	AE350_REG(AE350_USER(0)) = bad[0];
	AE350_REG(AE350_USER(1)) = bad[1];
	AE350_REG(AE350_USER(2)) = first_addr;
	AE350_REG(AE350_USER(3)) = first_expected;
	AE350_REG(AE350_USER(4)) = first_observed;
	ae350_puts("cctl ");
	ae350_put_decimal(bad[0]);
	ae350_puts(" evict ");
	ae350_put_decimal(bad[1]);
	ae350_putc('\n');
	uint32_t total = bad[0] + bad[1];
	return 0x600d0000u | (total > 0xffffu ? 0xffffu : total);
}
