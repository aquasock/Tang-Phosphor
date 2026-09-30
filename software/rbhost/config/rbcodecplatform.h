/* SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Tang-Phosphor rbcodec platform header for a newlib bare-metal RV32 host.
 * Replaces lib/rbcodec/test/rbcodecplatform.h (Rockbox
 * lib/rbcodec/rbcodecplatform-unix.h), with byte order taken from the
 * compiler because newlib has no <endian.h> or <byteswap.h>.
 */
#ifndef RBCODECPLATFORM_H_INCLUDED
#define RBCODECPLATFORM_H_INCLUDED

#include <assert.h>
#include <fcntl.h>
#include <ctype.h>
#include <string.h>
#include <strings.h>
#include <stdlib.h>
#include <stdio.h>

#ifndef swap16
#define swap16(x) __builtin_bswap16(x)
#endif
#ifndef swap32
#define swap32(x) __builtin_bswap32(x)
#endif

#if __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error "the AE350 A25 is little-endian"
#endif
#ifndef ROCKBOX_LITTLE_ENDIAN
#define ROCKBOX_LITTLE_ENDIAN 1
#endif
#ifndef htole16
#define htole16(x) ((uint16_t)(x))
#define htole32(x) ((uint32_t)(x))
#define le16toh(x) ((uint16_t)(x))
#define le32toh(x) ((uint32_t)(x))
#define htobe16(x) __builtin_bswap16(x)
#define htobe32(x) __builtin_bswap32(x)
#define be16toh(x) __builtin_bswap16(x)
#define be32toh(x) __builtin_bswap32(x)
#endif
#ifndef betoh16
#define betoh16 be16toh
#endif
#ifndef betoh32
#define betoh32 be32toh
#endif
#ifndef letoh16
#define letoh16 le16toh
#endif
#ifndef letoh32
#define letoh32 le32toh
#endif

/* filesize */
off_t ffilesize(int fd);

static inline bool tdspeed_alloc_buffers(int32_t **buffers,
    const int *buf_s, int nbuf)
{
    int i;
    for (i = 0; i < nbuf; i++)
    {
        buffers[i] = malloc(buf_s[i]);
        if (!buffers[i])
            return false;
    }
    return true;
}

static inline void tdspeed_free_buffers(int32_t **buffers, int nbuf)
{
    int i;
    for (i = 0; i < nbuf; i++)
    {
        free(buffers[i]);
    }
}

#endif
