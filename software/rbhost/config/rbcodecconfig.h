/* SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Tang-Phosphor rbcodec configuration for the AE350 A25 (RV32).  Replaces
 * lib/rbcodec/test/rbcodecconfig.h from Rockbox; derived from
 * lib/rbcodec/rbcodecconfig-example.h.  The DSP output rate may follow the
 * source at 44.1 or 48 kHz, the two rates the HDMI audio path carries
 * natively.
 */
#ifndef RBCODECCONFIG_H_INCLUDED
#define RBCODECCONFIG_H_INCLUDED

#define HAVE_PITCHCONTROL
#define HAVE_SW_TONE_CONTROLS
#define HAVE_ALBUMART
#define NUM_CORES 1
#define DSP_OUT_MIN_HZ     44100
#define DSP_OUT_DEFAULT_HZ 44100
#define DSP_OUT_MAX_HZ     48000

#ifndef __ASSEMBLER__

/* {,u}int{8,16,32,64}_t, {,U}INT{8,16,32,64}_{MIN,MAX}, intptr_t, uintptr_t */
#include <inttypes.h>

/* bool, true, false */
#include <stdbool.h>

/* NULL, offsetof, size_t */
#include <stddef.h>

/* ssize_t, off_t, SEEK_SET, SEEK_CUR, SEEK_END */
#include <unistd.h>

/* {UCHAR,USHRT,UINT,ULONG,SCHAR,SHRT,INT,LONG}_{MIN,MAX} */
#include <limits.h>
#define MAX_PATH 260

#include "system.h"
#include "rbcodecplatform.h"

#endif

#endif
