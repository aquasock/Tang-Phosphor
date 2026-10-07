/* SPDX-License-Identifier: GPL-3.0-only
 *
 * File requests from an AE350 program to the BL616, after Tang-PSX's
 * disc_request (software/common/tpx_api.h, served by Tang-Control's
 * core/tangpsx.cpp).  The program writes a byte offset and length into the
 * mailbox in USER(13..15) and then a new sequence number; the BL616 polls
 * the sequence and answers with one stream session of that byte range of
 * the file it is serving: START, DATA words (four bytes, least significant
 * first, the last one zero-padded), and END carrying the byte count, which
 * is short of the length asked for when the range runs past the end of the
 * file.  A request of length 0 asks for the file's size instead, answered as
 * a four-byte session holding it, least significant byte first.  One request
 * is outstanding at a time.
 *
 * USER(13..15) are also where the boot ROM records a trap, which is harmless:
 * the BL616 serves requests only while the loader is in RUN.  The sequence
 * continues from whatever the word holds, so a program must not clear it;
 * the BL616 takes its baseline before the program is sent.
 */
#ifndef AE350_REQUEST_H
#define AE350_REQUEST_H

#include <stdint.h>

#include "ae350.h"

#define AE350_REQUEST_SEQUENCE AE350_USER(13)
#define AE350_REQUEST_OFFSET   AE350_USER(14)
#define AE350_REQUEST_LENGTH   AE350_USER(15)

/* Receive errors (negative return values of ae350_request_receive). */
#define AE350_REQUEST_TIMEOUT  (-1)
#define AE350_REQUEST_CANCEL   (-2)
#define AE350_REQUEST_OVERFLOW (-3)
#define AE350_REQUEST_COUNT    (-4)   /* END count disagrees with the words */

static inline void ae350_request(uint32_t offset, uint32_t length)
{
	uint32_t sequence = AE350_REG(AE350_REQUEST_SEQUENCE) + 1u;

	AE350_REG(AE350_REQUEST_OFFSET) = offset;
	AE350_REG(AE350_REQUEST_LENGTH) = length;
	__asm__ volatile ("fence w, w" ::: "memory");
	AE350_REG(AE350_REQUEST_SEQUENCE) = sequence;
}

/*
 * Receive the session answering the last request into buffer, which holds
 * capacity bytes.  Returns the byte count from END, or a negative error.
 * timeout is in 75 MHz bus-clock ticks, counted from the call to the first
 * entry and then between entries.
 */
static inline int32_t ae350_request_receive(uint8_t *buffer, uint32_t capacity,
					    uint32_t timeout)
{
	uint32_t received = 0;
	int started = 0;

	for (;;) {
		uint32_t start = AE350_REG(AE350_TIME_LOW);
		uint32_t status;

		while (!((status = AE350_REG(AE350_STREAM_STATUS)) & 1u))
			if (AE350_REG(AE350_TIME_LOW) - start > timeout)
				return AE350_REQUEST_TIMEOUT;
		uint32_t tag = (status >> 1) & 3u;
		uint32_t data = AE350_REG(AE350_STREAM_DATA);
		AE350_REG(AE350_STREAM_POP) = 0;

		if (tag == AE350_TAG_CANCEL)
			return AE350_REQUEST_CANCEL;
		if (tag == AE350_TAG_START) {
			started = 1;
			received = 0;
			continue;
		}
		if (!started)
			continue;
		if (tag == AE350_TAG_END) {
			if (data > received || received - data > 3u)
				return AE350_REQUEST_COUNT;
			return (int32_t)data;
		}
		if (received + 4u > capacity)
			return AE350_REQUEST_OVERFLOW;
		for (int i = 0; i < 4; ++i) {
			buffer[received++] = (uint8_t)data;
			data >>= 8;
		}
	}
}

#endif
