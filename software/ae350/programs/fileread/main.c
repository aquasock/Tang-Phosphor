/* SPDX-License-Identifier: GPL-3.0-only
 *
 * File-request probe (include/ae350_request.h).  Run with TinyTang's
 * `phosphor run /ae350/fileread.tpi /music/test.wav`, which serves the
 * requests from the card; the ranges are chosen for that file, the 10 s
 * 44.1 kHz stereo corpus WAV of 1764044 bytes: its header, a block from the
 * start, an unaligned odd-length range, its last 1000 bytes, a range running
 * 90 bytes past its end, and then the whole file, timed.
 *
 * USER(0..5) hold the CRC-32 (zlib) of the bytes each request returned,
 * USER(6..11) the byte counts (or a negative ae350_request_receive error),
 * and USER(12) the whole-file request's time in milliseconds.  Each line is
 * also logged.  Returns 0x600d0000 plus the number of failed requests.
 */
#include <stdint.h>

#include "ae350.h"
#include "ae350_request.h"

#define TIMEOUT_TICKS (10u * AE350_TIME_HZ)

struct range {
	uint32_t offset;
	uint32_t length;
};

static const struct range ranges[] = {
	{ 0u, 44u },
	{ 0u, 65536u },
	{ 12345u, 100001u },
	{ 1763044u, 1000u },
	{ 1764034u, 100u },
	{ 0u, 2u << 20 },
};

#define RANGES (sizeof(ranges) / sizeof(ranges[0]))

static uint8_t buffer[(2u << 20) + 4u] __attribute__((aligned(32)));

static uint32_t crc32(const uint8_t *data, uint32_t size)
{
	uint32_t crc = 0xffffffffu;

	for (uint32_t i = 0; i < size; ++i) {
		crc ^= data[i];
		for (int bit = 0; bit < 8; ++bit)
			crc = (crc >> 1) ^ (0xedb88320u & -(crc & 1u));
	}
	return ~crc;
}

static void put_hex(uint32_t value)
{
	static const char digits[] = "0123456789abcdef";

	for (int shift = 28; shift >= 0; shift -= 4)
		ae350_putc(digits[(value >> shift) & 15u]);
}

uint32_t main(void)
{
	uint32_t failures = 0;

	for (uint32_t i = 0; i < 13u; ++i)
		AE350_REG(AE350_USER(i)) = 0;
	ae350_puts("fileread\n");
	for (uint32_t i = 0; i < RANGES; ++i) {
		uint64_t start = ae350_time();
		ae350_request(ranges[i].offset, ranges[i].length);
		int32_t got = ae350_request_receive(buffer, sizeof(buffer), TIMEOUT_TICKS);
		uint32_t ms = (uint32_t)((ae350_time() - start) / (AE350_TIME_HZ / 1000u));
		uint32_t crc = got >= 0 ? crc32(buffer, (uint32_t)got) : 0u;

		if (got < 0)
			++failures;
		AE350_REG(AE350_USER(i)) = crc;
		AE350_REG(AE350_USER(6u + i)) = (uint32_t)got;
		if (i == RANGES - 1u)
			AE350_REG(AE350_USER(12)) = ms;
		ae350_puts("req ");
		ae350_put_decimal(ranges[i].offset);
		ae350_putc('+');
		ae350_put_decimal(ranges[i].length);
		ae350_puts(" got ");
		if (got < 0) {
			ae350_putc('-');
			ae350_put_decimal((uint32_t)-got);
		} else {
			ae350_put_decimal((uint32_t)got);
		}
		ae350_puts(" crc ");
		put_hex(crc);
		ae350_puts(" ms ");
		ae350_put_decimal(ms);
		ae350_putc('\n');
	}
	return 0x600d0000u | failures;
}
