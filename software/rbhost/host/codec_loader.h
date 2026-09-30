/* SPDX-License-Identifier: GPL-3.0-only */
#ifndef CODEC_LOADER_H
#define CODEC_LOADER_H

struct codec_header;

/* Load a codec ELF image into the codec buffer and return its header (the
 * ELF entry address), or NULL after printing the reason. */
struct codec_header *codec_load(const char *path);

#endif
