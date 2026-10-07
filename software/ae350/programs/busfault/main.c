/* SPDX-License-Identifier: GPL-3.0-only
 *
 * What the A25 does with an AHB ERROR on a cacheable load.  The RAM bridge
 * answers any address outside DDR3 with ERROR; the question is whether the
 * core traps (the boot ROM then records mcause, mepc and mtval and reports
 * state 0x88) or takes the beat's data and carries on.
 *
 * A line holding a known pattern is written, written back and invalidated,
 * then loaded, so the bridge's line buffer holds it; then address 0 is
 * loaded.  Results in USER(0..4):
 *   USER(0)  0x600d0001 once the pattern line has been loaded
 *   USER(1)  the word the pattern load returned (0xa5a50000)
 *   USER(2)  the word the load from address 0 returned
 *   USER(3)  0x600d0003 once the load from address 0 has completed
 *   USER(4)  the RAM bridge's ERROR count before the load from address 0
 * A trap leaves USER(3) clear and the loader in state 0x88.
 */
#include <stdint.h>

#include "ae350.h"

#define LINE_BYTES 32u

static uint32_t pattern[64] __attribute__((aligned(LINE_BYTES)));

uint32_t main(void)
{
	for (uint32_t i = 0; i < 64u; ++i)
		pattern[i] = 0xa5a50000u | i;
	ae350_flush_dcache();

	/* One line fill from DDR3: the bridge now holds this line. */
	AE350_REG(AE350_USER(1)) = ((volatile uint32_t *)pattern)[0];
	AE350_REG(AE350_USER(0)) = 0x600d0001u;
	AE350_REG(AE350_USER(4)) = AE350_REG(AE350_BRIDGE_ERRORS);

	uint32_t v = *(volatile uint32_t *)0u;
	AE350_REG(AE350_USER(2)) = v;
	AE350_REG(AE350_USER(3)) = 0x600d0003u;
	return 0x600d0000u;
}
