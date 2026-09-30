/* SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Stands in for the autoconf.h that Rockbox's tools/configure generates.
 * Rockbox has no RISC-V architecture, so ARCH is arch_none and every codec
 * takes its portable C path.
 */
#ifndef __BUILD_AUTOCONF_H
#define __BUILD_AUTOCONF_H

#define arch_none 0
#define ARCH_NONE 0
#define arch_arm64 1
#define ARCH_ARM64 1
#define arch_m68k 2
#define ARCH_M68K 2
#define arch_arm 3
#define ARCH_ARM 3
#define arch_mips 4
#define ARCH_MIPS 4
#define arch_x86 5
#define ARCH_X86 5
#define arch_amd64 6
#define ARCH_AMD64 6

#define ARM_PROFILE_CLASSIC     0
#define ARM_PROFILE_MICRO       1
#define ARM_PROFILE_APPLICATION 2

#define ARCH arch_none
#define ROCKBOX_LITTLE_ENDIAN 1
#define GCCNUM 1002

#undef ROCKBOX_HAS_LOGF
#undef LOGF_SERIAL
#undef DO_BOOTCHART

#define ROCKBOX_DIR "/.rockbox"

#endif /* __BUILD_AUTOCONF_H */
