/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Whether the A25 can watch a memory range with two chained debug triggers:
 * trigger 0 matches addresses at or above the range's base and is chained
 * to trigger 1, which matches addresses below its end and raises a
 * breakpoint exception, so only a load inside the range traps.  This is the
 * mechanism the boot ROM's frame guard needs.  Results:
 *   USER(0)  tdata1 of trigger 0 read back (bit 11 is chain)
 *   USER(1)  tdata1 of trigger 1 read back
 *   USER(2)  0x600d0002 once a load below the range has completed
 *   USER(3)  0x600d0003 once a load at 0xe8000000 (fabric registers, above
 *            the range) has completed
 *   USER(4)  the address of the load inside the range
 *   USER(6)  tcontrol read back after setting mte (bit 3): debug spec 0.13.2
 *            lets M-mode triggers fire only while mte is set
 * The load inside the range should then trap: state 0x88, mcause 3
 * (breakpoint), mepc at that load.  USER(5) 0x600d0005 means it did not.
 */
#include <stdint.h>

#include "ae350.h"

#define CSR_READ(csr) ({ uint32_t v_; __asm__ volatile ("csrr %0, " #csr : "=r"(v_)); v_; })
#define CSR_WRITE(csr, v) __asm__ volatile ("csrw " #csr ", %0" :: "r"((uint32_t)(v)))

/* mcontrol (debug spec 0.13): type 2, M-mode, load and store. */
#define MCONTROL       (2u << 28 | 1u << 6 | 1u << 1 | 1u << 0)
#define MATCH_GE       (2u << 7)
#define MATCH_LT       (3u << 7)
#define CHAIN          (1u << 11)

static volatile uint32_t area[32] __attribute__((aligned(32)));

uint32_t main(void)
{
	uint32_t base = (uint32_t)&area[8];
	uint32_t end = (uint32_t)&area[16];

	CSR_WRITE(0x7a0, 0);
	CSR_WRITE(0x7a1, 0);
	CSR_WRITE(0x7a2, base);
	CSR_WRITE(0x7a1, MCONTROL | MATCH_GE | CHAIN);
	AE350_REG(AE350_USER(0)) = CSR_READ(0x7a1);
	CSR_WRITE(0x7a0, 1);
	CSR_WRITE(0x7a1, 0);
	CSR_WRITE(0x7a2, end);
	CSR_WRITE(0x7a1, MCONTROL | MATCH_LT);
	AE350_REG(AE350_USER(1)) = CSR_READ(0x7a1);
	CSR_WRITE(0x7a5, 1u << 3);
	AE350_REG(AE350_USER(6)) = CSR_READ(0x7a5);

	(void)area[2];
	AE350_REG(AE350_USER(2)) = 0x600d0002u;
	(void)AE350_REG(AE350_MAGIC);
	AE350_REG(AE350_USER(3)) = 0x600d0003u;
	AE350_REG(AE350_USER(4)) = (uint32_t)&area[10];
	(void)area[10];
	AE350_REG(AE350_USER(5)) = 0x600d0005u;
	for (;;)
		;
}
