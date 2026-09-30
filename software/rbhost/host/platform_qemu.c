/* SPDX-License-Identifier: GPL-3.0-only
 *
 * newlib system-call layer for running rbhost under qemu-riscv32 (linux-user).
 * Calls the Linux RV32 system-call ABI directly, since the toolchain's
 * libgloss uses proxy-kernel numbers that QEMU does not implement, and
 * translates newlib's open() flags to Linux values.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define LINUX_AT_FDCWD     (-100)
#define LINUX_O_WRONLY     01
#define LINUX_O_RDWR       02
#define LINUX_O_CREAT      0100
#define LINUX_O_TRUNC      01000
#define LINUX_O_APPEND     02000

#define SYS_openat     56
#define SYS_close      57
#define SYS_llseek     62
#define SYS_read       63
#define SYS_write      64
#define SYS_exit_group 94

#undef errno
extern int errno;

static long linux_syscall(long number, long a0, long a1, long a2, long a3,
                          long a4)
{
    register long r_a0 __asm__("a0") = a0;
    register long r_a1 __asm__("a1") = a1;
    register long r_a2 __asm__("a2") = a2;
    register long r_a3 __asm__("a3") = a3;
    register long r_a4 __asm__("a4") = a4;
    register long r_a7 __asm__("a7") = number;
    __asm__ volatile("ecall"
                     : "+r"(r_a0)
                     : "r"(r_a1), "r"(r_a2), "r"(r_a3), "r"(r_a4), "r"(r_a7)
                     : "memory");
    return r_a0;
}

static int result(long value)
{
    if (value < 0 && value > -4096) {
        errno = (int)-value;
        return -1;
    }
    return (int)value;
}

int _open(const char *path, int flags, int mode)
{
    int linux_flags = 0;
    if ((flags & O_ACCMODE) == O_WRONLY)
        linux_flags |= LINUX_O_WRONLY;
    else if ((flags & O_ACCMODE) == O_RDWR)
        linux_flags |= LINUX_O_RDWR;
    if (flags & O_CREAT)
        linux_flags |= LINUX_O_CREAT;
    if (flags & O_TRUNC)
        linux_flags |= LINUX_O_TRUNC;
    if (flags & O_APPEND)
        linux_flags |= LINUX_O_APPEND;
    return result(linux_syscall(SYS_openat, LINUX_AT_FDCWD, (long)path,
                                linux_flags, mode, 0));
}

int _close(int fd)
{
    return result(linux_syscall(SYS_close, fd, 0, 0, 0, 0));
}

int _read(int fd, void *buffer, size_t count)
{
    return result(linux_syscall(SYS_read, fd, (long)buffer, (long)count, 0, 0));
}

int _write(int fd, const void *buffer, size_t count)
{
    return result(linux_syscall(SYS_write, fd, (long)buffer, (long)count, 0, 0));
}

off_t _lseek(int fd, off_t offset, int whence)
{
    int64_t position = 0;
    int64_t wide = offset;
    long status = linux_syscall(SYS_llseek, fd, (long)(wide >> 32),
                                (long)(uint32_t)wide, (long)&position, whence);
    if (result(status) < 0)
        return -1;
    return (off_t)position;
}

int _fstat(int fd, struct stat *st)
{
    st->st_mode = fd <= 2 ? S_IFCHR : S_IFREG;
    st->st_blksize = 4096;
    return 0;
}

int _isatty(int fd)
{
    return fd <= 2;
}

void _exit(int status)
{
    linux_syscall(SYS_exit_group, status, 0, 0, 0, 0);
    for (;;)
        ;
}

int _kill(int pid, int signal)
{
    (void)pid;
    (void)signal;
    errno = EINVAL;
    return -1;
}

int _getpid(void)
{
    return 1;
}

extern char __heap_start[];
extern char __heap_end[];

void *_sbrk(ptrdiff_t increment)
{
    static char *brk = __heap_start;
    if (increment > __heap_end - brk || increment < __heap_start - brk) {
        errno = ENOMEM;
        return (void *)-1;
    }
    char *previous = brk;
    brk += increment;
    return previous;
}
