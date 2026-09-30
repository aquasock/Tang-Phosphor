/* SPDX-License-Identifier: GPL-3.0-only
 *
 * DDR3 and RAM-bridge checks run from DDR3 with the caches on.  The D-cache
 * is written back and invalidated before every verify pass, so each check
 * reads DDR3 through the bridge.
 *
 *   address   walking address bits: 0x7e000000 xor (1 << bit) for bits 2-29
 *             each get a distinct word, so a stuck or shorted address or
 *             bank line aliases two of them (1 GiB span)
 *   lanes     byte and halfword stores into every byte lane of eight lines,
 *             against a shadow copy (bridge byte enables, DDR3 masks)
 *   interleave  a read immediately after each write to the same word, with
 *             the caches written back every 64 words
 *   pattern   64 MiB of xorshift data at 0x44000000, written, then verified
 *   fpu       a double-precision product, proving mstatus.FS is enabled
 *
 * USER(0) passed checks (bit per check, in the order above), USER(1) the
 * failing address, USER(2) expected, USER(3) observed, USER(4) and USER(5)
 * pattern write and verify core cycles.  Returns 0x600d0000 | passed.
 */
#include <stdint.h>

#include "ae350.h"

#define WALK_BASE      0x7e000000u
#define LANE_BASE      0x7d000000u
#define LANE_BYTES     256u
#define INTERLEAVE_BASE 0x7c000000u
#define INTERLEAVE_WORDS 65536u
#define PATTERN_BASE   0x44000000u
#define PATTERN_WORDS  (64u << 20) / 4u

static uint32_t passed;

static uint32_t pattern(uint32_t index)
{
	uint32_t value = index + 0x9e3779b9u;
	value ^= value << 13;
	value ^= value >> 17;
	value ^= value << 5;
	return value;
}

static int fail(const char *name, uintptr_t address, uint32_t expected,
		uint32_t observed)
{
	AE350_REG(AE350_USER(1)) = (uint32_t)address;
	AE350_REG(AE350_USER(2)) = expected;
	AE350_REG(AE350_USER(3)) = observed;
	ae350_puts("FAIL ");
	ae350_puts(name);
	ae350_putc('\n');
	return -1;
}

static void pass(uint32_t bit, const char *name)
{
	passed |= bit;
	AE350_REG(AE350_USER(0)) = passed;
	ae350_puts(name);
	ae350_puts(" ok\n");
}

static int check_address(void)
{
	*(volatile uint32_t *)WALK_BASE = 0xa5a5a5a5u;
	for (uint32_t bit = 2; bit <= 29; ++bit)
		*(volatile uint32_t *)(WALK_BASE ^ (1u << bit)) = pattern(0x1000u + bit);
	ae350_flush_dcache();
	if (*(volatile uint32_t *)WALK_BASE != 0xa5a5a5a5u)
		return fail("address", WALK_BASE, 0xa5a5a5a5u,
			    *(volatile uint32_t *)WALK_BASE);
	for (uint32_t bit = 2; bit <= 29; ++bit) {
		uintptr_t address = WALK_BASE ^ (1u << bit);
		uint32_t value = *(volatile uint32_t *)address;
		if (value != pattern(0x1000u + bit))
			return fail("address", address, pattern(0x1000u + bit), value);
	}
	return 0;
}

static int check_lanes(void)
{
	static uint8_t shadow[LANE_BYTES];
	volatile uint32_t *words = (volatile uint32_t *)LANE_BASE;
	volatile uint16_t *halves = (volatile uint16_t *)LANE_BASE;
	volatile uint8_t *bytes = (volatile uint8_t *)LANE_BASE;

	for (uint32_t i = 0; i < LANE_BYTES / 4u; ++i) {
		uint32_t value = pattern(0x2000u + i);
		words[i] = value;
		for (uint32_t b = 0; b < 4; ++b)
			shadow[4u * i + b] = (uint8_t)(value >> (8u * b));
	}
	for (uint32_t i = 0; i < LANE_BYTES; i += 3u) {
		uint8_t value = (uint8_t)(0x5bu ^ (i * 29u));
		bytes[i] = value;
		shadow[i] = value;
	}
	for (uint32_t i = 2; i < LANE_BYTES; i += 10u) {
		uint16_t value = (uint16_t)(0xc3a5u ^ (i * 0x0101u));
		halves[i / 2u] = value;
		shadow[i] = (uint8_t)value;
		shadow[i + 1u] = (uint8_t)(value >> 8);
	}
	ae350_flush_dcache();
	for (uint32_t i = 0; i < LANE_BYTES / 4u; ++i) {
		uint32_t expected = shadow[4u * i] | (uint32_t)shadow[4u * i + 1u] << 8 |
			(uint32_t)shadow[4u * i + 2u] << 16 | (uint32_t)shadow[4u * i + 3u] << 24;
		if (words[i] != expected)
			return fail("lanes", (uintptr_t)&words[i], expected, words[i]);
	}
	return 0;
}

static int check_interleave(void)
{
	volatile uint32_t *ram = (volatile uint32_t *)INTERLEAVE_BASE;

	for (uint32_t i = 0; i < INTERLEAVE_WORDS; ++i) {
		uint32_t value = pattern(0x40000u + i);
		ram[i] = value;
		if (ram[i] != value)
			return fail("interleave", (uintptr_t)&ram[i], value, ram[i]);
		if (i % 64u == 63u)
			ae350_flush_dcache();
	}
	ae350_flush_dcache();
	for (uint32_t i = 0; i < INTERLEAVE_WORDS; ++i)
		if (ram[i] != pattern(0x40000u + i))
			return fail("interleave", (uintptr_t)&ram[i],
				    pattern(0x40000u + i), ram[i]);
	return 0;
}

static int check_pattern(void)
{
	volatile uint32_t *ram = (volatile uint32_t *)PATTERN_BASE;
	uint64_t start = ae350_cycles();

	for (uint32_t i = 0; i < PATTERN_WORDS; ++i)
		ram[i] = pattern(i);
	ae350_flush_dcache();
	AE350_REG(AE350_USER(4)) = (uint32_t)(ae350_cycles() - start);
	start = ae350_cycles();
	for (uint32_t i = 0; i < PATTERN_WORDS; ++i) {
		uint32_t value = ram[i];
		if (value != pattern(i))
			return fail("pattern", (uintptr_t)&ram[i], pattern(i), value);
	}
	AE350_REG(AE350_USER(5)) = (uint32_t)(ae350_cycles() - start);
	return 0;
}

static int check_fpu(void)
{
	volatile double a = 1.5;
	volatile double b = 2.25;
	double product = a * b;
	uint32_t bits = (uint32_t)(product * 1000.0);

	if (bits != 3375u)
		return fail("fpu", 0, 3375u, bits);
	return 0;
}

uint32_t main(void)
{
	ae350_puts("ddr3check\n");
	passed = 0;
	AE350_REG(AE350_USER(0)) = 0;
	if (check_address() == 0)
		pass(1u << 0, "address");
	if (check_lanes() == 0)
		pass(1u << 1, "lanes");
	if (check_interleave() == 0)
		pass(1u << 2, "interleave");
	if (check_pattern() == 0)
		pass(1u << 3, "pattern");
	if (check_fpu() == 0)
		pass(1u << 4, "fpu");
	return 0x600d0000u | passed;
}
