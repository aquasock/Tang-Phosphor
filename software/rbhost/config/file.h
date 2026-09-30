/* SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Replaces Rockbox's firmware file.h for standalone codec builds, as
 * lib/rbcodec/test/file.h does for warble: plain POSIX file I/O.
 */
#undef MAX_PATH
#define MAX_PATH 260
#include <unistd.h>
#include <fcntl.h>

off_t ffilesize(int fd);
