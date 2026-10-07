/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Which debug triggers (RISC-V debug spec 0.13, tselect/tdata1/tdata2/tinfo)
 * the A25 exposes to M-mode code.  For each tselect 0..6 the written index
 * is read back (an unimplemented index reads back different), then tdata1
 * and tinfo are read.  Results in USER(0..15):
 *   USER(2n)    for n = 0..6, tselect read back after writing n in the low
 *               byte, and tinfo in bits 31:16
 *   USER(2n+1)  tdata1 (bits 31:28 the trigger type: 2 address/data match)
 *   USER(14)    0, USER(15) 0x600d0000 once every index has been read
 * A CSR the core lacks raises an illegal-instruction trap, which the boot ROM
 * records as state 0x88 with mepc at the access.  The program then spins
 * rather than returning, so the loader stays in RUN and a host that would
 * restart a returned AE350 (which clears these words) leaves them readable.
 */
#include <stdint.h>

#include "ae350.h"

#define CSR_READ(csr) ({ uint32_t v_; __asm__ volatile ("csrr %0, " #csr : "=r"(v_)); v_; })
#define CSR_WRITE(csr, v) __asm__ volatile ("csrw " #csr ", %0" :: "r"((uint32_t)(v)))

uint32_t main(void)
{
	for (uint32_t n = 0; n < 7u; ++n) {
		CSR_WRITE(0x7a0, n);
		uint32_t sel = CSR_READ(0x7a0);
		uint32_t tdata1 = CSR_READ(0x7a1);
		uint32_t tinfo = CSR_READ(0x7a4);
		AE350_REG(AE350_USER(2u * n)) = (tinfo << 16) | (sel & 0xffu);
		AE350_REG(AE350_USER(2u * n + 1u)) = tdata1;
	}
	AE350_REG(AE350_USER(15)) = 0x600d0000u;
	for (;;)
		;
}
