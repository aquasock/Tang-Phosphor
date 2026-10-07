/* SPDX-License-Identifier: GPL-3.0-only
 *
 * AE350 boot ROM loader.  Receives program images (include/ae350.h) through
 * the Tang-Control stream (src/ae350/ae350_stream_loader.sv), copies them to
 * DDR3, checks them, runs them, and waits for the next image.  The state,
 * image size and CRC, and each program's return value are published in the
 * fabric registers for tools/ae350_run.py.  Follows the Tang-PSX Gate 1
 * loader protocol.
 */
#include <stdint.h>

#include "ae350.h"

extern char trap_entry[];
uint32_t boot_call(uint32_t entry);

static uint32_t runs;

static void set_state(uint32_t state)
{
	AE350_REG(AE350_STATE) = runs << 16 | state;
}

static uint32_t crc32_word(uint32_t crc, uint32_t word)
{
	crc ^= word;
	for (int bit = 0; bit < 32; ++bit)
		crc = (crc >> 1) ^ (0xedb88320u & -(crc & 1u));
	return crc;
}

/* Next stream entry; the tag is returned through *tag. */
static uint32_t next_entry(uint32_t *tag)
{
	uint32_t status;
	uint32_t data;

	do
		status = AE350_REG(AE350_STREAM_STATUS);
	while (!(status & 1u));
	data = AE350_REG(AE350_STREAM_DATA);
	AE350_REG(AE350_STREAM_POP) = 0;
	*tag = (status >> 1) & 3u;
	return data;
}

/*
 * Receive one image after its START.  Returns the error state, or 0 with the
 * header filled in once the END has been checked.  A START inside an image
 * restarts reception (*restart is set).
 */
static uint32_t receive(struct ae350_image_header *header, int *restart)
{
	uint32_t *words = (uint32_t *)header;
	uint32_t *payload = 0;
	uint32_t payload_words = 0;
	uint32_t received = 0;
	uint32_t crc = 0xffffffffu;
	uint32_t tag;
	uint32_t data;

	*restart = 0;
	for (;;) {
		data = next_entry(&tag);
		if (tag == AE350_TAG_START) {
			*restart = 1;
			return 0;
		}
		if (tag == AE350_TAG_CANCEL)
			return AE350_STATE_CANCELLED;
		if (tag == AE350_TAG_END) {
			if (received < AE350_IMAGE_HEADER / 4u ||
			    received != AE350_IMAGE_HEADER / 4u + payload_words)
				return AE350_STATE_TRUNCATED;
			if (data != 4u * received)
				return AE350_STATE_LENGTH;
			if (~crc != header->payload_crc)
				return AE350_STATE_CRC;
			return 0;
		}

		if (received < AE350_IMAGE_HEADER / 4u) {
			words[received++] = data;
			if (received < AE350_IMAGE_HEADER / 4u)
				continue;
			if (header->magic != AE350_IMAGE_MAGIC ||
			    header->header_bytes != AE350_IMAGE_HEADER ||
			    header->payload_bytes % 4u != 0)
				return AE350_STATE_BAD_HEADER;
			if (header->load < AE350_DDR3_BASE || header->load % 4u != 0 ||
			    header->payload_bytes > AE350_PROGRAM_END - header->load ||
			    header->entry < header->load ||
			    header->entry >= header->load + header->payload_bytes)
				return AE350_STATE_BAD_RANGE;
			payload = (uint32_t *)header->load;
			payload_words = header->payload_bytes / 4u;
			AE350_REG(AE350_IMAGE_BYTES) = header->payload_bytes;
			AE350_REG(AE350_IMAGE_CRC) = header->payload_crc;
			set_state(AE350_STATE_RECEIVE);
			continue;
		}
		if (received - AE350_IMAGE_HEADER / 4u >= payload_words)
			return AE350_STATE_LENGTH;
		payload[received - AE350_IMAGE_HEADER / 4u] = data;
		crc = crc32_word(crc, data);
		++received;
	}
}

void boot_main(void)
{
	struct ae350_image_header header;
	uint32_t tag;
	int restart = 0;

	AE350_REG(AE350_LOG_HEAD) = 0;
	ae350_puts("ae350 boot\n");
	for (;;) {
		uint32_t status;

		if (!restart) {
			set_state(AE350_STATE_WAIT);
			do
				(void)next_entry(&tag);
			while (tag != AE350_TAG_START);
		}
		status = receive(&header, &restart);
		if (restart)
			continue;
		if (AE350_REG(AE350_FLAGS) & 1u)
			status = AE350_STATE_OVERFLOW;
		if (status != 0) {
			set_state(status);
			/* Stay in the error state until the next image starts. */
			do
				(void)next_entry(&tag);
			while (tag != AE350_TAG_START);
			restart = 1;
			continue;
		}

		set_state(AE350_STATE_RUN);
		/* One line per call, so a program called twice for one image --
		 * control re-entering this loop -- shows in the log. */
		ae350_puts("run\n");
		__asm__ volatile ("fence rw, rw\n\tfence.i" ::: "memory");
		AE350_REG(AE350_RESULT) = boot_call(header.entry);
		AE350_CSR_WRITE(mtvec, trap_entry);
		++runs;
		set_state(AE350_STATE_RETURNED);
	}
}

void boot_trap(uint32_t cause, uint32_t pc, uint32_t value, uint32_t ra,
	       uint32_t sp)
{
	AE350_REG(AE350_USER(11)) = ra;
	AE350_REG(AE350_USER(12)) = sp;
	AE350_REG(AE350_USER(13)) = cause;
	AE350_REG(AE350_USER(14)) = pc;
	AE350_REG(AE350_USER(15)) = value;
	set_state(AE350_STATE_TRAP);
}
