/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Tang-Phosphor AE350 + DDR3 image (src/ae350/ae350_ddr3_top.sv): memory
 * map, fabric registers (src/ae350/ae350_exts_regs.sv), program image
 * format, and A25 control-register helpers.
 *
 * Memory map:
 *   0x40000000-0x7fefffff  DDR3, programs (default load address 0x40000000)
 *   0x7ff00000-0x7fffffff  DDR3, boot ROM data and the shared stack
 *   0x80000000             boot ROM (reset vector)
 *   0xe8000000             fabric registers (uncached)
 */
#ifndef AE350_H
#define AE350_H

#include <stdint.h>

#define AE350_DDR3_BASE        0x40000000u
#define AE350_PROGRAM_END      0x7ff00000u
#define AE350_REGS_BASE        0xe8000000u

#define AE350_REG(offset)      (*(volatile uint32_t *)(AE350_REGS_BASE + (offset)))
#define AE350_MAGIC            0x00u
#define AE350_ABI              0x04u
#define AE350_FLAGS            0x08u
#define AE350_TIME_LOW         0x0cu   /* 75 MHz bus clock; reading latches the high word */
#define AE350_TIME_HIGH        0x10u
#define AE350_STATE            0x20u
#define AE350_IMAGE_BYTES      0x24u
#define AE350_IMAGE_CRC        0x28u
#define AE350_RESULT           0x2cu
#define AE350_LOG_HEAD         0x30u
#define AE350_USER(n)          (0x40u + 4u * (n))   /* 16 program result words */
#define AE350_STREAM_STATUS    0x80u
#define AE350_STREAM_DATA      0x84u
#define AE350_STREAM_POP       0x88u
#define AE350_PLAY_DATA        0x90u   /* four bytes, least significant first */
#define AE350_PLAY_CTRL        0x94u   /* W: 1 start, 2 end, 4 cancel; R: bit 0 room */
#define AE350_PLAY_BYTE        0x98u   /* one byte; play writes wait while full */
#define AE350_PLAY_RATE        0x9cu   /* sample rate carried by the next START */
#define AE350_BRIDGE_READS     0xa0u
#define AE350_BRIDGE_WRITES    0xa4u
#define AE350_BRIDGE_LAT_SUM   0xa8u
#define AE350_BRIDGE_LAT_MAX   0xacu
#define AE350_BRIDGE_HITS      0xb0u
#define AE350_BRIDGE_ERRORS    0xb4u
#define AE350_LOG_RING         0x100u
#define AE350_LOG_BYTES        512u

#define AE350_REGS_MAGIC       0x54504133u  /* "TPA3" */
#define AE350_TIME_HZ          75000000u

/* Stream entry tags. */
#define AE350_TAG_DATA         0u
#define AE350_TAG_START        1u
#define AE350_TAG_END          2u
#define AE350_TAG_CANCEL       3u

/* Loader states (AE350_STATE bits 7:0; bits 31:16 count completed runs). */
#define AE350_STATE_BOOT       0x00u
#define AE350_STATE_WAIT       0x01u
#define AE350_STATE_RECEIVE    0x02u
#define AE350_STATE_RUN        0x03u
#define AE350_STATE_RETURNED   0x04u
#define AE350_STATE_BAD_HEADER 0x81u
#define AE350_STATE_BAD_RANGE  0x82u
#define AE350_STATE_TRUNCATED  0x83u
#define AE350_STATE_LENGTH     0x84u
#define AE350_STATE_CRC        0x85u
#define AE350_STATE_CANCELLED  0x86u
#define AE350_STATE_OVERFLOW   0x87u
#define AE350_STATE_TRAP       0x88u   /* USER(13..15) = mcause, mepc, mtval */

/*
 * Program image: this 32-byte header, then the payload, a flat binary
 * padded to a multiple of four bytes.  The loader copies the payload to
 * `load`, checks the CRC-32 (zlib polynomial) of the payload, and calls
 * `entry` as uint32_t entry(void) with the caches and FPU enabled, on the
 * loader's stack.  The return value is published in AE350_RESULT.
 */
#define AE350_IMAGE_MAGIC      0x31495054u  /* "TPI1" */
#define AE350_IMAGE_HEADER     32u

struct ae350_image_header {
	uint32_t magic;
	uint32_t header_bytes;
	uint32_t load;
	uint32_t entry;
	uint32_t payload_bytes;
	uint32_t payload_crc;
	uint32_t reserved[2];
};

/* AndeStar V5 cache control (Tang-PSX core-reference AE350-002). */
#define AE350_CSR_MCACHE_CTL   0x7ca
#define AE350_CSR_MCCTLCOMMAND 0x7cc
#define AE350_CCTL_L1D_WBINVAL_ALL 6u

#define AE350_CSR_STR_(x) #x
#define AE350_CSR_STR(x) AE350_CSR_STR_(x)
#define AE350_CSR_READ(csr) ({ uint32_t v_; \
	__asm__ volatile ("csrr %0, " AE350_CSR_STR(csr) : "=r" (v_)); v_; })
#define AE350_CSR_WRITE(csr, value) \
	__asm__ volatile ("csrw " AE350_CSR_STR(csr) ", %0" :: "r" ((uint32_t)(value)) : "memory")

static inline uint64_t ae350_cycles(void)
{
	uint32_t high, low, check;
	do {
		__asm__ volatile ("rdcycleh %0" : "=r" (high));
		__asm__ volatile ("rdcycle %0" : "=r" (low));
		__asm__ volatile ("rdcycleh %0" : "=r" (check));
	} while (high != check);
	return ((uint64_t)high << 32) | low;
}

static inline uint64_t ae350_instructions(void)
{
	uint32_t high, low, check;
	do {
		__asm__ volatile ("rdinstreth %0" : "=r" (high));
		__asm__ volatile ("rdinstret %0" : "=r" (low));
		__asm__ volatile ("rdinstreth %0" : "=r" (check));
	} while (high != check);
	return ((uint64_t)high << 32) | low;
}

static inline uint64_t ae350_time(void)
{
	uint32_t low = AE350_REG(AE350_TIME_LOW);
	return ((uint64_t)AE350_REG(AE350_TIME_HIGH) << 32) | low;
}

/* Write back and invalidate the whole L1 data cache. */
static inline void ae350_flush_dcache(void)
{
	__asm__ volatile ("fence rw, rw" ::: "memory");
	AE350_CSR_WRITE(AE350_CSR_MCCTLCOMMAND, AE350_CCTL_L1D_WBINVAL_ALL);
	__asm__ volatile ("fence rw, rw" ::: "memory");
}

/* Append to the log ring that Tang-Control reads (tools/ae350_run.py). */
static inline void ae350_putc(char c)
{
	uint32_t head = AE350_REG(AE350_LOG_HEAD);
	((volatile uint8_t *)(AE350_REGS_BASE + AE350_LOG_RING))[head % AE350_LOG_BYTES] = (uint8_t)c;
	AE350_REG(AE350_LOG_HEAD) = head + 1u;
}

static inline void ae350_puts(const char *text)
{
	while (*text)
		ae350_putc(*text++);
}

static inline void ae350_put_decimal(uint32_t value)
{
	char digits[10];
	int n = 0;
	do {
		digits[n++] = (char)('0' + value % 10u);
		value /= 10u;
	} while (value);
	while (n)
		ae350_putc(digits[--n]);
}

#endif
