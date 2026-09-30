/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Loads a Rockbox codec linked by codec.ld: a static little-endian RV32 ELF
 * executable whose PT_LOAD segments all lie in the codec buffer.  Segment
 * bytes are copied from the file, the remainder of each segment (.bss) is
 * zeroed, and the entry address is returned as the codec header.
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "codec_loader.h"

extern char __codec_start[];
extern char __codec_end[];

#define EI_NIDENT 16
#define ET_EXEC 2
#define EM_RISCV 243
#define PT_LOAD 1

struct elf32_header {
    unsigned char ident[EI_NIDENT];
    uint16_t type;
    uint16_t machine;
    uint32_t version;
    uint32_t entry;
    uint32_t phoff;
    uint32_t shoff;
    uint32_t flags;
    uint16_t ehsize;
    uint16_t phentsize;
    uint16_t phnum;
    uint16_t shentsize;
    uint16_t shnum;
    uint16_t shstrndx;
};

struct elf32_phdr {
    uint32_t type;
    uint32_t offset;
    uint32_t vaddr;
    uint32_t paddr;
    uint32_t filesz;
    uint32_t memsz;
    uint32_t flags;
    uint32_t align;
};

static int read_at(int fd, uint32_t offset, void *buffer, uint32_t size)
{
    if (lseek(fd, offset, SEEK_SET) != (off_t)offset)
        return -1;
    char *bytes = buffer;
    while (size > 0) {
        ssize_t actual = read(fd, bytes, size);
        if (actual <= 0)
            return -1;
        bytes += actual;
        size -= actual;
    }
    return 0;
}

static int in_codec_buffer(uint32_t address, uint32_t size)
{
    uintptr_t start = (uintptr_t)__codec_start;
    uintptr_t end = (uintptr_t)__codec_end;
    return address >= start && address <= end && size <= end - address;
}

struct codec_header *codec_load(const char *path)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "error: cannot open codec %s\n", path);
        return NULL;
    }

    struct elf32_header header;
    struct codec_header *result = NULL;
    if (read_at(fd, 0, &header, sizeof(header)) != 0 ||
            memcmp(header.ident, "\177ELF\1\1", 6) != 0 ||
            header.type != ET_EXEC || header.machine != EM_RISCV ||
            header.phentsize != sizeof(struct elf32_phdr)) {
        fprintf(stderr, "error: %s is not an RV32 codec image\n", path);
        goto done;
    }

    memset(__codec_start, 0, __codec_end - __codec_start);
    for (unsigned index = 0; index < header.phnum; index++) {
        struct elf32_phdr segment;
        if (read_at(fd, header.phoff + index * sizeof(segment), &segment,
                    sizeof(segment)) != 0)
            goto bad;
        if (segment.type != PT_LOAD)
            continue;
        if (segment.filesz > segment.memsz ||
                !in_codec_buffer(segment.vaddr, segment.memsz))
            goto bad;
        if (read_at(fd, segment.offset, (void *)(uintptr_t)segment.vaddr,
                    segment.filesz) != 0)
            goto bad;
    }
    if (!in_codec_buffer(header.entry, 1))
        goto bad;

    __asm__ volatile("fence rw, rw\n\tfence.i" ::: "memory");
    result = (struct codec_header *)(uintptr_t)header.entry;
    goto done;

bad:
    fprintf(stderr, "error: %s has a segment outside the codec buffer\n", path);
done:
    close(fd);
    return result;
}
