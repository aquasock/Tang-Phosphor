# SPDX-License-Identifier: GPL-3.0-only
#
# Build rbhost and Rockbox codecs for the AE350 A25 (rv32imafdc, ilp32d).
#
# Rockbox sources are used unmodified from third_party/rockbox.  They are
# compiled with Rockbox's own standalone-codec configuration (the one its
# warble test program uses: SDLAPP, APPLICATION, __PCTOOL__, WARBLE), with
# config/ supplying the rbcodec configuration and platform headers that
# lib/rbcodec/test supplies for warble.  Optimization levels follow Rockbox's
# native targets: -Os by default, per-library levels from codecs.make, and
# -O2 for the DSP.
#
#   make                  host (qemu-riscv32 build) and codecs
#   make BUILD=<dir>      choose the output directory
#   make bench BENCH_INPUT=<file> BENCH_CODEC=<codec> [BENCH_NAME=<name>]
#                         rbhost as an AE350 program (software/ae350) with
#                         one codec and one input file embedded:
#                         $(BUILD)/bench/<name>.tpi for tools/ae350_run.py

ROOT      := $(abspath ../..)
.DEFAULT_GOAL := all
RB        := $(ROOT)/third_party/rockbox
RBC       := $(RB)/lib/rbcodec
BUILD     ?= $(ROOT)/build/rbhost
HERE      := $(abspath .)

CROSS     ?= riscv64-unknown-elf-
CC        := $(CROSS)gcc
AR        := $(CROSS)ar
OBJCOPY   := $(CROSS)objcopy

# Distinct from every Rockbox target so foreign codecs are rejected.
TARGET_ID := 0x5450

ARCHFLAGS := -march=rv32imafdc -mabi=ilp32d
DEFINES   := -DROCKBOX -DMEMORYSIZE=8 -DSDLAPP -DTARGET_ID=$(TARGET_ID) \
             -DTARGET_NAME=\"tangphosphor\" -DAPPLICATION -D__PCTOOL__ \
             -DWARBLE -D_FILE_H_
INCLUDES  := -I$(HERE)/config -I$(RB)/lib/fixedpoint -I$(RB)/apps \
             -I$(RB)/apps/gui -I$(RB)/firmware/kernel/include \
             -I$(RB)/firmware/export -I$(RB)/firmware/include \
             -I$(RB)/firmware/target/hosted -I$(RB)/firmware/target/hosted/sdl \
             -I$(RB)/lib/tlsf/src -I$(RBC) -I$(RBC)/codecs -I$(RBC)/dsp \
             -I$(RBC)/metadata
CFLAGS    := $(ARCHFLAGS) -Os -g -std=gnu11 -fno-delete-null-pointer-checks \
             -fno-strict-overflow -fno-common -ffunction-sections \
             -fdata-sections -Wno-pointer-sign -Wno-override-init \
             -Wimplicit-fallthrough=0 $(DEFINES) $(INCLUDES)
CODECFLAGS = $(CFLAGS) -fstrict-aliasing -I$(RBC)/codecs -I$(RBC)/codecs/lib \
             -DCODEC -mno-relax

# Preprocess a Rockbox SOURCES list with this configuration.
sources = $(addprefix $(dir $(1)),$(shell $(CC) $(CFLAGS) -imacros \
          rbcodecconfig.h -E -P -x c $(1) | grep -v '^\s*$$'))
obj = $(patsubst $(RB)/%.c,$(BUILD)/rb/%.o,$(patsubst $(RB)/%.S,$(BUILD)/rb/%.o,$(1)))

RBCODEC_SRC := $(call sources,$(RBC)/SOURCES) \
               $(addprefix $(RB)/firmware/common/,strmemccpy.c strlcpy.c \
                 unicode.c crc32.c) \
               $(RB)/firmware/buflib_mempool.c $(RB)/firmware/core_alloc.c \
               $(RB)/lib/fixedpoint/fixedpoint.c
CODECLIB_SRC := $(call sources,$(RBC)/codecs/lib/SOURCES)
RBCODEC_OBJ  := $(call obj,$(RBCODEC_SRC))
CODECLIB_OBJ := $(call obj,$(CODECLIB_SRC))

HOST_OBJ := $(BUILD)/host/crt0_qemu.o $(BUILD)/host/platform_qemu.o \
            $(BUILD)/host/rbhost.o $(BUILD)/host/codec_loader.o
AE350_OBJ := $(BUILD)/host/crt0_ae350.o $(BUILD)/host/platform_ae350.o \
             $(BUILD)/host/rbhost.o $(BUILD)/host/codec_loader.o

# Codec support libraries: name, flags appended (Rockbox's -O level last, as
# in codecs.make and each library's .make fragment), flags prepended.
define codec_library
$(1)_SRC := $$(call sources,$(RBC)/codecs/$(1)/SOURCES)
$(1)_OBJ := $$(call obj,$$($(1)_SRC))
$$($(1)_OBJ): EXTRA := $(2)
$$($(1)_OBJ): PRE := $(3)
$(BUILD)/$(1).a: $$($(1)_OBJ)
	$$(AR) rcs $$@ $$^
endef

$(eval $(call codec_library,libffmpegFLAC,-O2))
$(eval $(call codec_library,libmad,-I$(RBC)/codecs/libmad -UDEBUG -DNDEBUG -DHAVE_LIMITS_H -DHAVE_ASSERT_H -O2))
$(eval $(call codec_library,libasf,-O2))
$(eval $(call codec_library,libtremor,-O2))
$(eval $(call codec_library,libopus,-O2,-DHAVE_CONFIG_H -I$(RBC)/codecs/libopus -I$(RBC)/codecs/libopus/celt -I$(RBC)/codecs/libopus/silk))
$(eval $(call codec_library,libfaad,-I$(RBC)/codecs/libfaad -O2))
$(eval $(call codec_library,libm4a,-O3))
$(eval $(call codec_library,libalac,-O1))
$(eval $(call codec_library,libwavpack,-O1))
$(eval $(call codec_library,libwma,-O2))
$(eval $(call codec_library,liba52,-O1))
$(eval $(call codec_library,libtta,-O2))
$(eval $(call codec_library,libpcm,-O1))

# Rockbox lib/tlsf, as built by lib/tlsf/libtlsf.make for non-simulator builds.
TLSF_OBJ := $(BUILD)/rb/lib/tlsf/src/tlsf.o
$(TLSF_OBJ): EXTRA := -fstrict-aliasing -DHAVE_CONFIG_H -DTLSF_STATISTIC=1
$(BUILD)/libtlsf.a: $(TLSF_OBJ)
	$(AR) rcs $@ $^

# Rockbox's lib/libsetjmp has no RISC-V port and warble uses the system
# setjmp, so Vorbis links newlib's RV32 setjmp.o, extracted alone so no other
# libc code enters a codec.
$(BUILD)/setjmp.o:
	@mkdir -p $(dir $@)
	cd $(dir $@) && $(AR) x $$($(CC) $(ARCHFLAGS) -print-file-name=libc.a) \
		lib_a-setjmp.o && mv lib_a-setjmp.o setjmp.o

# codec: support libraries (and objects) it links, in link order.
CODEC_DEPS_flac    := libffmpegFLAC.a
CODEC_DEPS_mpa     := libmad.a libasf.a
CODEC_DEPS_vorbis  := libtremor.a libtlsf.a setjmp.o
CODEC_DEPS_opus    := libopus.a libtlsf.a
CODEC_DEPS_aac     := libfaad.a libm4a.a
CODEC_DEPS_alac    := libalac.a libm4a.a
CODEC_DEPS_wavpack := libwavpack.a
CODEC_DEPS_wma     := libwma.a libasf.a
CODEC_DEPS_a52     := liba52.a
CODEC_DEPS_tta     := libtta.a
CODEC_DEPS_wav     := libpcm.a

CODEC_NAMES := $(patsubst CODEC_DEPS_%,%,$(filter CODEC_DEPS_%,$(.VARIABLES)))
CODECS := $(foreach name,$(CODEC_NAMES),$(BUILD)/codecs/$(name).codec)

all: $(BUILD)/rbhost-qemu $(CODECS)

$(BUILD)/rbhost-qemu: $(HOST_OBJ) $(BUILD)/librbcodec.a host/host.ld host/memory.ld
	$(CC) $(ARCHFLAGS) -nostartfiles -static -L$(HERE)/host -T host.ld \
		-Wl,--gc-sections -Wl,-Map,$@.map -o $@ $(HOST_OBJ) \
		$(BUILD)/librbcodec.a -lc -lm -lgcc

$(BUILD)/librbcodec.a: $(RBCODEC_OBJ)
	$(AR) rcs $@ $^

$(BUILD)/libcodec.a: $(CODECLIB_OBJ)
	$(AR) rcs $@ $^

# Link each codec at the codec buffer; .elf keeps symbols for profiling.
.SECONDEXPANSION:
$(BUILD)/codecs/%.elf: $(BUILD)/rb/lib/rbcodec/codecs/%.o \
		$(BUILD)/rb/lib/rbcodec/codecs/codec_crt0.o \
		$$(addprefix $(BUILD)/,$$(CODEC_DEPS_$$*)) $(BUILD)/libcodec.a \
		host/codec.ld host/memory.ld
	@mkdir -p $(dir $@)
	$(CC) $(ARCHFLAGS) -nostdlib -static -L$(HERE)/host -T codec.ld \
		-Wl,--gc-sections -Wl,-Map,$(@:.elf=.map) -o $@ \
		$(BUILD)/rb/lib/rbcodec/codecs/codec_crt0.o $< \
		$(addprefix $(BUILD)/,$(CODEC_DEPS_$*)) $(BUILD)/libcodec.a -lgcc

$(BUILD)/codecs/%.codec: $(BUILD)/codecs/%.elf
	$(OBJCOPY) -S $< $@

.PRECIOUS: $(BUILD)/codecs/%.elf

# Optimization levels from Rockbox codecs.make and rbcodec.make.
$(CODECLIB_OBJ): EXTRA := -O1
$(filter $(BUILD)/rb/lib/rbcodec/dsp/%,$(RBCODEC_OBJ)): EXTRA := -O2

$(BUILD)/rb/lib/rbcodec/codecs/%.o: $(RB)/lib/rbcodec/codecs/%.c
	@mkdir -p $(dir $@)
	$(CC) -I$(dir $<) $(PRE) $(CODECFLAGS) $(EXTRA) -c $< -o $@

# The Rockbox submodule carries local patches recorded in
# third_party/patches/ (see THIRD_PARTY.md).  They must be applied before any
# Rockbox source is compiled, because `git submodule update` reverts them.
# The stamp below depends on the patch files and on the patched source itself,
# so a re-checked-out submodule re-applies the patches on the next build.
ROCKBOX_PATCHES := $(wildcard $(ROOT)/third_party/patches/*.patch)
$(BUILD)/.rockbox-patched: $(ROCKBOX_PATCHES) $(RB)/lib/rbcodec/codecs/libwma/wmadeci.c
	@mkdir -p $(BUILD)
	@$(ROOT)/scripts/apply-rockbox-patches.sh
	@touch $@

$(BUILD)/rb/%.o: $(RB)/%.c | $(BUILD)/.rockbox-patched
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(EXTRA) -c $< -o $@

$(BUILD)/host/%.o: host/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -O2 -Wall -Ihost -I$(ROOT)/software/ae350/include -c $< -o $@

$(BUILD)/host/%.o: host/%.S
	@mkdir -p $(dir $@)
	$(CC) $(ARCHFLAGS) -c $< -o $@

# Hardware benchmark image.  The codec and the input are embedded with
# .incbin; the input keeps its file name, since rbhost probes the format
# from the extension.
BENCH_NAME ?= bench
# BENCH_PLAY=1 plays the decoded WAV through the FPGA player afterwards.
BENCH_PLAY ?= 0
# BENCH_STREAM=1 receives the input through the stream loader instead of
# embedding it; the codec is still embedded.
BENCH_STREAM ?= 0
# BENCH_UNIVERSAL=1 embeds every codec instead of BENCH_CODEC, so one image
# decodes any streamed input.  Implied by bench-universal.
BENCH_UNIVERSAL ?= 0
BENCH_DIR  := $(BUILD)/bench
BENCH_ELF  := $(BENCH_DIR)/$(BENCH_NAME).elf

bench: $(BENCH_DIR)/$(BENCH_NAME).tpi

# Universal resident player: every codec, streamed input, play output.
bench-universal: BENCH_UNIVERSAL := 1
bench-universal: BENCH_STREAM := 1
bench-universal: BENCH_PLAY := 1
bench-universal: $(BENCH_DIR)/$(BENCH_NAME).tpi

$(BENCH_DIR)/$(BENCH_NAME).S: $(CODECS) $(BENCH_INPUT) FORCE
	@test -n "$(BENCH_INPUT)" || { echo "set BENCH_INPUT" >&2; exit 1; }
	@if [ "$(BENCH_UNIVERSAL)" = "0" ]; then \
		test -n "$(BENCH_CODEC)" || { echo "set BENCH_CODEC" >&2; exit 1; }; \
	fi
	@mkdir -p $(dir $@)
	@{ \
		printf '%s\n' '	.section .rodata.bench_files, "a"' '	.balign 8'; \
		if [ "$(BENCH_UNIVERSAL)" = "1" ]; then \
			for n in $(CODEC_NAMES); do \
				printf 'codec_data_%s: .incbin "$(BUILD)/codecs/%s.codec"\ncodec_end_%s:\n\t.balign 8\n' $$n $$n $$n; \
			done; \
		else \
			printf 'codec_data: .incbin "$(BUILD)/codecs/$(BENCH_CODEC).codec"\ncodec_end:\n\t.balign 8\n'; \
		fi; \
		printf '%s\n' 'input_data: .incbin "$(abspath $(BENCH_INPUT))"' 'input_end:' '	.balign 4' '	.globl bench_files' 'bench_files:'; \
		if [ "$(BENCH_UNIVERSAL)" = "1" ]; then \
			for n in $(CODEC_NAMES); do \
				printf '\t.word codec_name_%s, codec_data_%s, codec_end_%s - codec_data_%s\n' $$n $$n $$n $$n; \
			done; \
		else \
			printf '\t.word codec_name, codec_data, codec_end - codec_data\n'; \
		fi; \
		printf '%s\n' '	.word bench_input_name, input_data, input_end - input_data' '	.word 0, 0, 0'; \
		if [ "$(BENCH_UNIVERSAL)" = "1" ]; then \
			for n in $(CODEC_NAMES); do \
				printf 'codec_name_%s: .asciz "codecs/%s.codec"\n' $$n $$n; \
			done; \
		else \
			printf 'codec_name: .asciz "codecs/$(BENCH_CODEC).codec"\n'; \
		fi; \
		printf '%s\n' '	.globl bench_input_name' 'bench_input_name: .asciz "$(notdir $(BENCH_INPUT))"' '	.balign 4' '	.globl bench_play' 'bench_play: .word $(BENCH_PLAY)' '	.globl bench_stream' 'bench_stream: .word $(BENCH_STREAM)'; \
	} > $@

$(BENCH_ELF): $(AE350_OBJ) $(BENCH_DIR)/$(BENCH_NAME).S $(BUILD)/librbcodec.a \
		host/host.ld host/memory.ld
	$(CC) $(ARCHFLAGS) -nostartfiles -static -L$(HERE)/host -T host.ld \
		-Wl,--gc-sections -Wl,-Map,$(@:.elf=.map) -o $@ $(AE350_OBJ) \
		$(BENCH_DIR)/$(BENCH_NAME).S $(BUILD)/librbcodec.a -lc -lm -lgcc

$(BENCH_DIR)/$(BENCH_NAME).tpi: $(BENCH_ELF)
	$(OBJCOPY) -O binary $< $(@:.tpi=.bin)
	python3 $(ROOT)/tools/ae350_run.py pack $(@:.tpi=.bin) -o $@

# The same program under qemu-riscv32 (host/bench_qemu.c), for reference
# results.
bench: $(BENCH_DIR)/$(BENCH_NAME)-qemu.elf

$(BENCH_DIR)/$(BENCH_NAME)-qemu.elf: $(AE350_OBJ) $(BUILD)/host/bench_qemu.o \
		$(BUILD)/host/bench_qemu_start.o $(BENCH_DIR)/$(BENCH_NAME).S \
		$(BUILD)/librbcodec.a host/host.ld host/memory.ld
	$(CC) $(ARCHFLAGS) -nostartfiles -static -L$(HERE)/host -T host.ld \
		-Wl,-e,_start_qemu -Wl,--gc-sections -o $@ \
		$(BUILD)/host/bench_qemu_start.o $(BUILD)/host/bench_qemu.o $(AE350_OBJ) \
		$(BENCH_DIR)/$(BENCH_NAME).S $(BUILD)/librbcodec.a -lc -lm -lgcc

FORCE:

# Decode the FPGA FLAC decoder's regression vectors (tools/
# generate_flac_test_vectors.py) and require the same PCM it must produce.
# profile96 is omitted: the host resamples 96 kHz to 44.1 kHz by design.
QEMU ?= qemu-riscv32
CHECK_VECTORS := constant44 fixed48 lpc44 gapless_a44 gapless_b44
check: all
	rm -rf $(BUILD)/check && mkdir -p $(BUILD)/check
	python3 $(ROOT)/tools/generate_flac_test_vectors.py $(BUILD)/check
	@for vector in $(CHECK_VECTORS); do \
		$(QEMU) $(BUILD)/rbhost-qemu $(BUILD)/codecs \
			$(BUILD)/check/$$vector.flac $(BUILD)/check/$$vector.out.wav \
			2>/dev/null || exit 1; \
		tail -c +47 $(BUILD)/check/$$vector.out.wav | \
			cmp -s - $(BUILD)/check/$$vector.raw || \
			{ echo "FAIL $$vector"; exit 1; }; \
		echo "PASS $$vector"; \
	done

clean:
	rm -rf $(BUILD)

.PHONY: all bench check clean FORCE
