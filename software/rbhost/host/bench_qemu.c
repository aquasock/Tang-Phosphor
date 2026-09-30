/* SPDX-License-Identifier: GPL-3.0-only
 *
 * Runs the AE350 benchmark program (platform_ae350.c) under qemu-riscv32
 * (linux-user): the fabric register window and the output buffer are mapped
 * as ordinary memory, ae350_main() runs exactly as on hardware, and the log
 * ring and result registers are printed.  This gives the hardware run's
 * reference output size and CRC-32 and instruction count from the same
 * code.
 */
#include <stdint.h>

#include "ae350.h"

uint32_t ae350_main(void);

#define SYS_write      64
#define SYS_exit_group 94
#define SYS_mmap       222

static long syscall6(long number, long a0, long a1, long a2, long a3, long a4, long a5)
{
    register long r_a0 __asm__("a0") = a0;
    register long r_a1 __asm__("a1") = a1;
    register long r_a2 __asm__("a2") = a2;
    register long r_a3 __asm__("a3") = a3;
    register long r_a4 __asm__("a4") = a4;
    register long r_a5 __asm__("a5") = a5;
    register long r_a7 __asm__("a7") = number;
    __asm__ volatile("ecall"
                     : "+r"(r_a0)
                     : "r"(r_a1), "r"(r_a2), "r"(r_a3), "r"(r_a4), "r"(r_a5), "r"(r_a7)
                     : "memory");
    return r_a0;
}

static void map(uint32_t address, uint32_t size)
{
    /* PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_FIXED | MAP_ANONYMOUS */
    long result = syscall6(SYS_mmap, address, size, 3, 0x32, -1, 0);
    if ((uint32_t)result != address)
        syscall6(SYS_exit_group, 3, 0, 0, 0, 0, 0);
}

static void put(const char *text, uint32_t size)
{
    syscall6(SYS_write, 1, (long)text, size, 0, 0, 0);
}

static void put_hex(const char *label, uint32_t value)
{
    char text[16];
    uint32_t n = 0;
    while (*label)
        text[n++] = *label++;
    for (int shift = 28; shift >= 0; shift -= 4)
        text[n++] = "0123456789abcdef"[(value >> shift) & 15u];
    text[n++] = '\n';
    put(text, n);
}

void bench_qemu_main(void)
{
    map(AE350_REGS_BASE, 0x1000);
    map(0x48000000u, 64u << 20);
    uint32_t result = ae350_main();

    uint32_t head = AE350_REG(AE350_LOG_HEAD);
    const char *ring = (const char *)(AE350_REGS_BASE + AE350_LOG_RING);
    put("log:\n", 5);
    if (head <= AE350_LOG_BYTES) {
        put(ring, head);
    } else {
        put(ring + head % AE350_LOG_BYTES, AE350_LOG_BYTES - head % AE350_LOG_BYTES);
        put(ring, head % AE350_LOG_BYTES);
    }
    put_hex("result ", result);
    for (uint32_t i = 0; i < 16; ++i)
        put_hex("user   ", AE350_REG(AE350_USER(i)));
    syscall6(SYS_exit_group, 0, 0, 0, 0, 0, 0);
}
