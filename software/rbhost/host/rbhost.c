/* SPDX-License-Identifier: GPL-2.0-or-later
 *
 * rbhost: runs Rockbox codecs on the AE350 A25 through Rockbox's codec API.
 *
 * The codec_api implementation follows Rockbox lib/rbcodec/test/warble.c
 * (GPL-2.0-or-later), whose write-to-file behavior it reproduces so the two
 * can be compared: DSP output is 16-bit stereo WAV, and -r writes the codec's
 * raw 32-bit samples without a header.  Codecs are static RV32 ELF images
 * linked at the codec buffer (codec.ld) instead of dlopen()ed shared objects.
 *
 * Usage: rbhost [-r] CODEC_DIR INPUT OUTPUT
 */
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#include "codecs.h"
#include "dsp_core.h"
#include "metadata.h"
#include "settings.h"
#include "platform.h"

#include "codec_loader.h"

/***************** EXPORTED *****************/

struct user_settings global_settings;

void panicf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(-1);
}

int find_first_set_bit(uint32_t value)
{
    if (value == 0)
        return 32;
    return __builtin_ctz(value);
}

/* unicode.c builds codepage-table paths with Rockbox's pathfuncs.c, whose
 * hosted filesystem headers need <dirent.h>; a plain join suffices here.
 * Returns the length of the full result, as Rockbox's path_append does. */
size_t path_append(char *buffer, const char *basepath, const char *component,
                   size_t bufsize)
{
    int length = snprintf(buffer, bufsize, "%s/%s", basepath, component);
    return length < 0 ? bufsize : (size_t)length;
}

off_t ffilesize(int fd)
{
    off_t current = lseek(fd, 0, SEEK_CUR);
    off_t size = lseek(fd, 0, SEEK_END);
    lseek(fd, current, SEEK_SET);
    return size;
}

/***************** INTERNAL *****************/

#define WAVE_HEADER_SIZE 0x2e
#define WAVE_FORMAT_PCM 1

static bool use_dsp = true;
static int input_fd = -1;
static int output_fd = -1;
static bool header_written;
static unsigned long num_output_samples;
static struct codec_api ci;

static struct {
    intptr_t freq;
    intptr_t stereo_mode;
    intptr_t depth;
    int channels;
} format;

static void set_le16(char *buf, uint16_t val)
{
    buf[0] = val;
    buf[1] = val >> 8;
}

static void set_le32(char *buf, uint32_t val)
{
    buf[0] = val;
    buf[1] = val >> 8;
    buf[2] = val >> 16;
    buf[3] = val >> 24;
}

static void write_all(const void *data, size_t size)
{
    const char *bytes = data;
    while (size > 0) {
        ssize_t written = write(output_fd, bytes, size);
        if (written <= 0)
            panicf("error: output write failed");
        bytes += written;
        size -= written;
    }
}

/* Same 0x2e-byte header as warble; sizes are fixed up by write_quit(). */
static void write_wav_header(void)
{
    const int channels = 2;
    const int sample_size = 16;
    const int freq = dsp_get_output_frequency(ci.dsp);
    const off_t total_size = 0x7fffff00 + WAVE_HEADER_SIZE;
    char header[WAVE_HEADER_SIZE] = {"RIFF____WAVEfmt \x12\0\0\0"
                                     "________________\0\0data____"};
    set_le32(header + 0x04, total_size - 8);
    set_le16(header + 0x14, WAVE_FORMAT_PCM);
    set_le16(header + 0x16, channels);
    set_le32(header + 0x18, freq);
    set_le32(header + 0x1c, freq * channels * sample_size / 8);
    set_le16(header + 0x20, channels * sample_size / 8);
    set_le16(header + 0x22, sample_size);
    set_le32(header + 0x2a, total_size - WAVE_HEADER_SIZE);
    write_all(header, sizeof(header));
    header_written = true;
}

static void write_quit(void)
{
    if (use_dsp) {
        if (!header_written)
            write_wav_header();
        off_t total_size = lseek(output_fd, 0, SEEK_CUR);
        if (total_size != (off_t)-1) {
            char buf[4];
            set_le32(buf, total_size - 8);
            lseek(output_fd, 4, SEEK_SET);
            write_all(buf, 4);
            set_le32(buf, total_size - WAVE_HEADER_SIZE);
            lseek(output_fd, 0x2a, SEEK_SET);
            write_all(buf, 4);
        }
    }
    close(output_fd);
}

/***************** CODEC API *****************/

#define CODEC_MALLOC_SIZE (8 * 1024 * 1024)

static void *ci_codec_get_buffer(size_t *size)
{
    static char buffer[CODEC_MALLOC_SIZE] MEM_ALIGN_ATTR;
    *size = sizeof(buffer);
    return buffer;
}

static void ci_pcmbuf_insert(const void *ch1, const void *ch2, int count)
{
    num_output_samples += count;

    if (use_dsp) {
        struct dsp_buffer src;
        src.remcount = count;
        src.pin[0] = ch1;
        src.pin[1] = ch2;
        src.proc_mask = 0;
        while (1) {
            static int16_t buf[2 * 4096];
            struct dsp_buffer dst;

            dst.remcount = 0;
            dst.p16out = buf;
            dst.bufcount = ARRAYLEN(buf) / 2;

            dsp_process(ci.dsp, &src, &dst, true);

            if (dst.remcount > 0) {
                if (!header_written)
                    write_wav_header();
                write_all(buf, 4 * dst.remcount);
            } else if (src.remcount <= 0) {
                break;
            }
        }
    } else {
        /* Raw codec samples as 32-bit interleaved, as warble -r writes. */
        static int32_t buf[2 * 4096];
        int total = count * format.channels;
        int done = 0;
        while (done < total) {
            int chunk = MIN(total - done, (int)ARRAYLEN(buf));
            int i;
            for (i = 0; i < chunk; i++) {
                int index = done + i;
                if (format.depth > 16) {
                    if (format.stereo_mode == STEREO_NONINTERLEAVED)
                        buf[i] = ((const int32_t *)(index & 1 ? ch2 : ch1))[index / 2];
                    else
                        buf[i] = ((const int32_t *)ch1)[index];
                } else {
                    if (format.stereo_mode == STEREO_NONINTERLEAVED)
                        buf[i] = ((const int16_t *)(index & 1 ? ch2 : ch1))[index / 2];
                    else
                        buf[i] = ((const int16_t *)ch1)[index];
                }
            }
            write_all(buf, chunk * sizeof(*buf));
            done += chunk;
        }
    }
}

static void ci_set_elapsed(unsigned long value)
{
    (void)value;
}

/* request_buffer data stays valid until the next buffer call, as in warble. */
static char *input_buffer;
static size_t input_buffer_size;

static size_t ci_read_filebuf(void *ptr, size_t size)
{
    ssize_t actual = read(input_fd, ptr, size);
    if (actual < 0)
        actual = 0;
    ci.curpos += actual;
    return actual;
}

static void *ci_request_buffer(size_t *realsize, size_t reqsize)
{
    if (!rbcodec_format_is_atomic(ci.id3->codectype))
        reqsize = MIN(reqsize, 32 * 1024);
    if (reqsize > input_buffer_size) {
        free(input_buffer);
        input_buffer = malloc(reqsize);
        if (!input_buffer)
            panicf("error: request_buffer of %lu bytes failed",
                   (unsigned long)reqsize);
        input_buffer_size = reqsize;
    }
    ssize_t actual = read(input_fd, input_buffer, reqsize);
    if (actual < 0)
        actual = 0;
    *realsize = actual;
    lseek(input_fd, -actual, SEEK_CUR);
    return input_buffer;
}

static void ci_advance_buffer(size_t amount)
{
    lseek(input_fd, amount, SEEK_CUR);
    ci.curpos += amount;
    ci.id3->offset = ci.curpos;
}

static bool ci_seek_buffer(size_t newpos)
{
    off_t actual = lseek(input_fd, newpos, SEEK_SET);
    if (actual >= 0)
        ci.curpos = actual;
    return actual != -1;
}

static void ci_seek_complete(void)
{
}

static void ci_set_offset(size_t value)
{
    ci.id3->offset = value;
}

static void ci_configure(int setting, intptr_t value)
{
    if (use_dsp) {
        dsp_configure(ci.dsp, setting, value);
    } else {
        if (setting == DSP_SET_FREQUENCY)
            format.freq = value;
        else if (setting == DSP_SET_SAMPLE_DEPTH)
            format.depth = value;
        else if (setting == DSP_SET_STEREO_MODE) {
            format.stereo_mode = value;
            format.channels = (value == STEREO_MONO) ? 1 : 2;
        }
    }
}

static long ci_get_command(intptr_t *param)
{
    *param = 0;
    return CODEC_ACTION_NULL;
}

static bool ci_should_loop(void)
{
    return false;
}

static void ci_strip_filesize(off_t size)
{
    ci.filesize = size;
}

static unsigned ci_sleep(unsigned ticks)
{
    (void)ticks;
    return 0;
}

static void stub_void_void(void)
{
}

/* Codecs share the host's caches; after loading, fence.i makes the copied
 * instructions visible to instruction fetch. */
static void commit_discard_idcache(void)
{
    __asm__ volatile("fence rw, rw\n\tfence.i" ::: "memory");
}

#ifdef HAVE_RECORDING
static void stub_enc_unsupported(const char *func)
{
    panicf("error: rbhost does not support encoding (%s)", func);
}

static int ci_enc_pcmbuf_read(void *buf, int count)
{
    (void)buf; (void)count;
    stub_enc_unsupported(__func__);
    return 0;
}

static int ci_enc_pcmbuf_advance(int count)
{
    (void)count;
    stub_enc_unsupported(__func__);
    return 0;
}

static struct enc_chunk_data *ci_enc_encbuf_get_buffer(size_t need)
{
    (void)need;
    stub_enc_unsupported(__func__);
    return NULL;
}

static void ci_enc_encbuf_finish_buffer(void)
{
    stub_enc_unsupported(__func__);
}

static ssize_t ci_enc_stream_read(void *buf, size_t count)
{
    (void)buf; (void)count;
    stub_enc_unsupported(__func__);
    return -1;
}

static off_t ci_enc_stream_lseek(off_t offset, int whence)
{
    (void)offset; (void)whence;
    stub_enc_unsupported(__func__);
    return -1;
}

static ssize_t ci_enc_stream_write(const void *buf, size_t count)
{
    (void)buf; (void)count;
    stub_enc_unsupported(__func__);
    return -1;
}

static int ci_round_value_to_list32(unsigned long value,
                                    const unsigned long list[],
                                    int count, bool signd)
{
    (void)value; (void)list; (void)count; (void)signd;
    stub_enc_unsupported(__func__);
    return 0;
}
#endif /* HAVE_RECORDING */

static struct codec_api ci = {
    0,                   /* filesize */
    0,                   /* curpos */
    NULL,                /* id3 */
    -1,                  /* audio_hid */
    NULL,                /* struct dsp_config *dsp */
    ci_codec_get_buffer,
    ci_pcmbuf_insert,
    ci_set_elapsed,
    ci_read_filebuf,
    ci_request_buffer,
    ci_advance_buffer,
    ci_seek_buffer,
    ci_seek_complete,
    ci_set_offset,
    ci_configure,
    ci_get_command,
    ci_should_loop,
    ci_strip_filesize,
    ci_sleep,
    stub_void_void,         /* yield */

    stub_void_void,         /* commit_dcache */
    stub_void_void,         /* commit_discard_dcache */
    commit_discard_idcache,

    /* strings and memory */
    strcpy,
    strlen,
    strcmp,
    strcat,
    memset,
    memcpy,
    memmove,
    memcmp,
    memchr,
#if defined(DEBUG) || defined(SIMULATOR)
#error "rbhost does not provide the debug-build codec API"
#endif
#ifdef ROCKBOX_HAS_LOGF
    NULL,
#endif

    qsort,

#ifdef HAVE_RECORDING
    ci_enc_pcmbuf_read,
    ci_enc_pcmbuf_advance,
    ci_enc_encbuf_get_buffer,
    ci_enc_encbuf_finish_buffer,
    ci_enc_stream_read,
    ci_enc_stream_lseek,
    ci_enc_stream_write,
    ci_round_value_to_list32,
#endif /* HAVE_RECORDING */

    panicf,
};

/* Make the next main() start as the first one did, for a player that decodes
 * one track after another (platform_ae350.c); called before every main(). */
void rbhost_reset(void)
{
    static struct codec_api initial;
    static bool saved;
    if (!saved) {
        initial = ci;
        saved = true;
    } else {
        ci = initial;
    }
    input_fd = -1;
    output_fd = -1;
    header_written = false;
    num_output_samples = 0;
}

static int decode_file(const char *codec_dir, const char *input_fn)
{
    /* Once, as Rockbox does at boot: the DSP keeps its stages, and the
     * timestretch buffers are allocated when it is first enabled.  Each
     * track resets the DSP below. */
    static bool dsp_ready;
    if (!dsp_ready) {
        dsp_init();
        memset(&global_settings, 0, sizeof(global_settings));
        global_settings.timestretch_enabled = true;
        dsp_timestretch_enable(true);
        dsp_ready = true;
    }

    input_fd = open(input_fn, O_RDONLY);
    if (input_fd < 0) {
        fprintf(stderr, "error: cannot open %s\n", input_fn);
        return 1;
    }

    static struct mp3entry id3;
    memset(&id3, 0, sizeof(id3));
    if (!get_metadata(&id3, input_fd, input_fn)) {
        fprintf(stderr, "error: metadata parsing failed\n");
        return 1;
    }
    fprintf(stderr, "Codec: %s\nFrequency: %lu Hz\nSong length: %lu ms\n",
            audio_formats[id3.codectype].label, id3.frequency, id3.length);

    ci.filesize = ffilesize(input_fd);
    ci.id3 = &id3;
    if (use_dsp) {
        /* The HDMI path carries 44.1 and 48 kHz natively; match the source
         * when it is one of those and resample everything else to 44.1. */
        unsigned long out_hz = id3.frequency == 48000 ? 48000 : 44100;
        ci.dsp = dsp_get_config(CODEC_IDX_AUDIO);
        dsp_configure(ci.dsp, DSP_SET_OUT_FREQUENCY, out_hz);
        dsp_configure(ci.dsp, DSP_RESET, 0);
        dsp_dither_enable(false);
    }

    char path[MAX_PATH];
    snprintf(path, sizeof(path), "%s/%s.codec", codec_dir,
             audio_formats[id3.codectype].codec_root_fn);
    struct codec_header *c_hdr = codec_load(path);
    if (!c_hdr)
        return 1;
    if (c_hdr->lc_hdr.magic != CODEC_MAGIC) {
        fprintf(stderr, "error: %s invalid: incorrect magic\n", path);
        return 1;
    }
    if (c_hdr->lc_hdr.target_id != TARGET_ID) {
        fprintf(stderr, "error: %s invalid: incorrect target id\n", path);
        return 1;
    }
    if (c_hdr->lc_hdr.api_version != CODEC_API_VERSION ||
            c_hdr->api_size != sizeof(struct codec_api)) {
        fprintf(stderr, "error: %s invalid: incorrect API version\n", path);
        return 1;
    }

    *c_hdr->api = &ci;
    if (c_hdr->entry_point(CODEC_LOAD) != CODEC_OK) {
        fprintf(stderr, "error: codec returned error from codec_main\n");
        return 1;
    }
    int status = 0;
    if (c_hdr->run_proc() != CODEC_OK) {
        fprintf(stderr, "error: codec error\n");
        status = 1;
    }
    c_hdr->entry_point(CODEC_UNLOAD);
    close(input_fd);
    fprintf(stderr, "Samples: %lu\n", num_output_samples);
    return status;
}

int main(int argc, char **argv)
{
    int first = 1;
    if (argc > 1 && !strcmp(argv[1], "-r")) {
        use_dsp = false;
        first = 2;
    }
    if (argc != first + 3) {
        fprintf(stderr, "usage: rbhost [-r] CODEC_DIR INPUT OUTPUT\n");
        return 2;
    }

    output_fd = open(argv[first + 2], O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (output_fd < 0) {
        fprintf(stderr, "error: cannot create %s\n", argv[first + 2]);
        return 1;
    }
    int status = decode_file(argv[first], argv[first + 1]);
    write_quit();
    return status;
}
