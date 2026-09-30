# SPDX-License-Identifier: GPL-3.0-only
#
# AE350 boot ROM and test programs for the AE350 + DDR3 image.
#
#   make                  boot ROM hex and all programs
#   make BUILD=<dir>      choose the output directory
#
# Outputs: $(BUILD)/boot/ae350_boot.hex (8 KiB ROM image, one little-endian
# word per line, for src/ae350/ae350_boot_rom.sv) and
# $(BUILD)/programs/<name>.tpi (images for tools/ae350_run.py).

ROOT      := $(abspath ../..)
BUILD     ?= $(ROOT)/build/ae350
HERE      := $(abspath .)

CROSS     ?= riscv64-unknown-elf-
CC        := $(CROSS)gcc
OBJCOPY   := $(CROSS)objcopy

ARCHFLAGS := -march=rv32imafdc -mabi=ilp32d
CFLAGS    := $(ARCHFLAGS) -O2 -g -std=gnu11 -ffreestanding -fno-builtin \
             -ffunction-sections -fdata-sections -Wall -Wextra -Werror \
             -I$(HERE)/include

ROM_BYTES := 8192
PROGRAMS  := $(notdir $(wildcard programs/*))

all: $(BUILD)/boot/ae350_boot.hex \
     $(foreach p,$(PROGRAMS),$(BUILD)/programs/$(p).tpi)

$(BUILD)/boot/ae350_boot.elf: boot/start.S boot/boot.c boot/boot.ld include/ae350.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -Os -nostdlib -nostartfiles -T boot/boot.ld \
		-Wl,--no-relax -Wl,--gc-sections -Wl,-Map,$(@:.elf=.map) -o $@ \
		boot/start.S boot/boot.c -lgcc

# The ROM image is padded to the full ROM so every word is defined.
$(BUILD)/boot/ae350_boot.hex: $(BUILD)/boot/ae350_boot.elf
	$(OBJCOPY) -O binary -j .text -j .rodata -j .data $< $(@:.hex=.bin)
	test $$(stat -c %s $(@:.hex=.bin)) -le $(ROM_BYTES)
	truncate -s $(ROM_BYTES) $(@:.hex=.bin)
	od -An -v -tx4 -w4 $(@:.hex=.bin) | tr -d ' ' > $@

$(BUILD)/programs/%.elf: programs/%/main.c lib/crt0.S lib/program.ld include/ae350.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -nostdlib -nostartfiles -T lib/program.ld \
		-Wl,--gc-sections -Wl,-Map,$(@:.elf=.map) -o $@ \
		lib/crt0.S $(wildcard programs/$*/*.c) -lgcc

$(BUILD)/programs/%.tpi: $(BUILD)/programs/%.elf
	$(OBJCOPY) -O binary $< $(@:.tpi=.bin)
	python3 $(ROOT)/tools/ae350_run.py pack $(@:.tpi=.bin) -o $@

.PRECIOUS: $(BUILD)/programs/%.elf

clean:
	rm -rf $(BUILD)

.PHONY: all clean
