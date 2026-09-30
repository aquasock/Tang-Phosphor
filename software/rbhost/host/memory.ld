/* SPDX-License-Identifier: GPL-3.0-only
 *
 * rbhost memory map, shared by the host and codec link scripts.  The host
 * runs from RAM_BASE; one codec at a time is linked to CODEC_BASE, as Rockbox
 * native targets load codecs into a single codec buffer.  CODEC_SIZE matches
 * the Rockbox configuration the codecs are compiled with.
 */
RAM_BASE   = 0x40000000;
CODEC_BASE = 0x41000000;
CODEC_SIZE = 0x00100000;
HEAP_BASE  = 0x41100000;
HEAP_END   = 0x43000000;
