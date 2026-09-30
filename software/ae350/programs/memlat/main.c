/* SPDX-License-Identifier: GPL-3.0-only
 *
 * AE350 data-memory cost in DDR3, in core cycles per access, with the boot
 * ROM's cache settings.  Ported from Tang-PSX software/programs/memlat, so
 * the results compare directly with its core-reference AE350-009/010.
 * Each region holds one 32-byte node per cache line.
 *
 *   L16K ... L4M   dependent loads along a random single cycle of nodes
 *                  (Sattolo), so every load waits for the previous one;
 *                  16 KiB fits the 32 KiB D-cache and the others do not
 *   Q4M            loads of consecutive lines, independent of each other
 *   S4M            one store per line, including write-back of the dirty
 *                  lines each store evicts
 *
 * The D-cache is written back and invalidated before each measurement.
 * Results, in tenths of a cycle, go to the log and to USER(0..6): L16K,
 * L64K, L96K, L256K, L4M, Q4M, S4M.  USER(7..9) hold the RAM bridge's read
 * count, read-latency sum, and maximum (100 MHz cycles) for the L4M chase.
 */
#include <stdint.h>

#include "ae350.h"

#define LINE_BYTES   32u
#define REGION_BYTES (4u << 20)
#define NODES        (REGION_BYTES / LINE_BYTES)
#define CHASE_LOADS  (1u << 20)

struct node {
	struct node *next;
	uint32_t pad[LINE_BYTES / 4u - 1u];
};

static struct node nodes[NODES] __attribute__((aligned(LINE_BYTES)));
static uint32_t order[NODES];

/* A random single cycle through the first count nodes (Sattolo). */
static void build_chain(uint32_t count)
{
	uint32_t seed = 0x12345678u;

	for (uint32_t i = 0; i < count; ++i)
		order[i] = i;
	for (uint32_t i = count - 1u; i > 0u; --i) {
		uint32_t j, t;
		seed = seed * 1664525u + 1013904223u;
		j = (uint32_t)(((uint64_t)seed * i) >> 32);   /* 0 .. i-1 */
		t = order[i];
		order[i] = order[j];
		order[j] = t;
	}
	for (uint32_t i = 0; i < count; ++i)
		nodes[order[i]].next = &nodes[order[(i + 1u) % count]];
}

/* Cycles per dependent load, times ten. */
static uint32_t chase(uint32_t bytes)
{
	struct node *p = &nodes[0];
	uint64_t start;

	build_chain(bytes / LINE_BYTES);
	ae350_flush_dcache();
	start = ae350_cycles();
	for (uint32_t i = 0; i < CHASE_LOADS; ++i)
		p = p->next;
	start = ae350_cycles() - start;
	__asm__ volatile ("" : : "r"(p));
	return (uint32_t)(start * 10u / CHASE_LOADS);
}

/* Cycles per line for consecutive independent loads, times ten. */
static uint32_t stream_read(void)
{
	uint64_t start;
	uint32_t sum = 0;

	ae350_flush_dcache();
	start = ae350_cycles();
	for (uint32_t i = 0; i < NODES; ++i)
		sum += nodes[i].pad[0];
	start = ae350_cycles() - start;
	__asm__ volatile ("" : : "r"(sum));
	return (uint32_t)(start * 10u / NODES);
}

/* Cycles per line for one store per line, including dirty evictions. */
static uint32_t stream_write(void)
{
	volatile struct node *region = nodes;
	uint64_t start;

	ae350_flush_dcache();
	start = ae350_cycles();
	for (uint32_t pass = 0; pass < 2u; ++pass)
		for (uint32_t i = 0; i < NODES; ++i)
			region[i].pad[0] = i + pass;
	start = ae350_cycles() - start;
	return (uint32_t)(start * 10u / (2u * NODES));
}

static void report(const char *label, uint32_t tenths)
{
	ae350_puts(label);
	ae350_put_decimal(tenths / 10u);
	ae350_putc('.');
	ae350_put_decimal(tenths % 10u);
}

uint32_t main(void)
{
	uint32_t result[7];
	uint32_t reads, latency_sum;

	result[0] = chase(16u << 10);
	result[1] = chase(64u << 10);
	result[2] = chase(96u << 10);
	result[3] = chase(256u << 10);
	reads = AE350_REG(AE350_BRIDGE_READS);
	latency_sum = AE350_REG(AE350_BRIDGE_LAT_SUM);
	result[4] = chase(REGION_BYTES);
	AE350_REG(AE350_USER(7)) = AE350_REG(AE350_BRIDGE_READS) - reads;
	AE350_REG(AE350_USER(8)) = AE350_REG(AE350_BRIDGE_LAT_SUM) - latency_sum;
	AE350_REG(AE350_USER(9)) = AE350_REG(AE350_BRIDGE_LAT_MAX);
	result[5] = stream_read();
	result[6] = stream_write();
	for (uint32_t i = 0; i < 7u; ++i)
		AE350_REG(AE350_USER(i)) = result[i];
	report("L16K ", result[0]);
	report(" L64K ", result[1]);
	report(" L96K ", result[2]);
	report("\nL256K ", result[3]);
	report(" L4M ", result[4]);
	report("\nQ4M ", result[5]);
	report(" S4M ", result[6]);
	ae350_putc('\n');
	return 0x3e3a7001u;
}
