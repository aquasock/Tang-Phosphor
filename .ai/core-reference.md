# Tang-Phosphor Standards Reference

This file records the external standards and primary technical references used
for implementation decisions. A reference entry does not expand the project's
supported profile. Project-specific limits remain implementation limits.

---

## HDMI Audio Transport

### HDMI 1.4/2.0 Transmitter Subsystem Product Guide (AMD PG235)

- Source: https://docs.amd.com/r/en-US/pg235-v-hdmi-tx-ss/Audio-Clock-Regeneration-Interface
- Authority: AMD primary documentation for its standards-based HDMI transmitter subsystem.
- Relevant rule: Audio Clock Regeneration uses 20-bit `CTS` and `N` values, and a transmitter consumes them only when both are stable.
- Tang-Phosphor use: Change the selected rate atomically, restart the measurement interval, and do not emit a new-rate ACR event until its matching `CTS` measurement is complete.

### HDMI Audio Pipeline (AMD UG1442)

- Source: https://docs.amd.com/r/en-US/ug1442-vck190-base-trd/HDMI-Audio-Pipeline
- Authority: AMD primary reference-design documentation.
- Relevant rule: The transmit-side ACR controller calculates `CTS` by counting transmit TMDS clock cycles for a defined audio-clock interval.
- Tang-Phosphor use: The HDMI packetizer measures pixel/TMDS-clock cycles across `N / 128` audio samples instead of relying on an unrelated fixed delay.

### Local HDMI packetizer provenance

- Source: `src/hdmi/audio_clock_regeneration_packet.sv`, `src/hdmi/audio_sample_packet.sv`, and `src/hdmi/packet_picker.sv`.
- Authority: Implementation reference derived from Sameer Puri's HDMI 1.4a transmitter; not a substitute for the HDMI specification.
- Relevant behavior: The existing ACR algorithm selects `N = 6272` for 44.1 kHz and `N = 6144` for 48 kHz, counts `N / 128` audio samples, and encodes the rate in IEC 60958 channel status.
- Tang-Phosphor use: Preserve that proven packet layout while making the bounded 44.1/48 kHz selection runtime-controlled and resetting partial measurements at a rate transition.

---

## IEC Consumer PCM Channel Status

### IEC 60958-3:2021

- Source: https://webstore.iec.ch/en/publication/71069
- Authority: Current IEC international standard for consumer applications of the IEC 60958 digital audio interface.
- Relevant scope: Consumer PCM channel-status representation used inside HDMI Audio Sample packets.
- Access note: The normative field tables are licensed material and are not reproduced in this repository. The local packetizer's existing 44.1 kHz code `0000` and 48 kHz code `0010` remain implementation mappings pending direct verification against a licensed copy if conformance questions arise.

---

## Audio Container Signatures

### RFC 9639: Free Lossless Audio Codec (FLAC)

- Source: https://www.rfc-editor.org/rfc/rfc9639.html
- Authority: IETF Standards Track specification for the FLAC format and streamable subset, published December 2024.
- Relevant rule: A native FLAC bitstream begins with the four-byte `fLaC` marker (`0x664c6143`), followed by the mandatory STREAMINFO metadata block.
- Tang-Phosphor use: Classify native FLAC after exactly four prefix bytes and replay those bytes to the decoder. The implemented RFC 9639 streamable-subset profile is bounded to signed 16-bit stereo at 44.1 or 48 kHz, a maximum 4,608-sample block, fixed predictors 0–4, LPC orders 1–12, Rice methods 0 and 1, escape residuals, wasted bits, all stereo channel assignments, and mandatory header CRC-8 and frame CRC-16 validation.

### Resource Interchange File Format (RIFF)

- Source: https://learn.microsoft.com/en-us/windows/win32/xaudio2/resource-interchange-file-format--riff-
- Authority: Microsoft primary documentation for the RIFF container used by waveform audio.
- Relevant rule: A RIFF chunk begins with the literal `RIFF` FOURCC, a four-byte size, and a file-type FOURCC; waveform audio uses the file type `WAVE`.
- Tang-Phosphor use: Require `RIFF` at byte zero and `WAVE` at byte eight, making 12 bytes the bounded WAV-classification prefix before byte-exact replay.

---

## GW5AST AE350 Hard Processor

### Gowin RiscV_AE350_SOC Hardware Design Manual 1.3.1E

- Source: https://www.gowinsemi.com/upload/database_doc/2725/document/6981101d547a4.pdf
- Authority: Current Gowin primary hardware-integration manual, released January 2026.
- Relevant rule: The hard A25 CPU exposes FPGA peripherals through extended APB/AHB interfaces, accepts 16 fabric interrupt inputs, and requires its core clock from the dedicated PLL path while AHB and APB remain synchronous and below 200 MHz.
- Tang-Phosphor use: Place the AE350 clock PLL at `PLL_R[0]`, keep the initial fabric bus at 75 MHz, and attach the USB host registers through the CPU-master fabric interface.

### LiteX Gowin AE350 wrapper and Tang hardware demonstration

- Sources: https://github.com/enjoy-digital/litex/blob/5940a34ca0b4ee0fd9344f717dc7859aed503d9f/litex/soc/cores/cpu/gowin_ae350/core.py and https://github.com/enjoy-digital/litex_wr_nic/blob/cd5fde38b6ef4fde5bdbbd37c2452ee853d1dac5/doc/tang_mega_138k_pro.md
- Authority: Reproducible open-source integration and physical GW5AST-138B test evidence; not a substitute for Gowin's manual.
- Relevant behavior: The wrapper directly instantiates `AE350_SOC`, maps the fixed `0x80000000` reset vector and extended fabric bus, and the Tang target demonstrates AE350 firmware and interrupts on hardware.
- Tang-Phosphor use: Reuse the BSD-2-Clause primitive wiring and dedicated-PLL approach while keeping White Rabbit gateware and firmware outside this project.

### AE350 core clock is `PLL_R[0]` `CLKOUT1`

- Sources: Tang-PSX `.ai/core-reference.md` record AE350-007 and core-log entry 26, commit `c3aaf811d059`, `gateware/ae350_pll.v` and `software/programs/clock/main.c` (https://github.com/aquasock/Tang-PSX).
- Authority: Hardware measurement on this board; no primary Gowin document naming `CLKOUT1` was found. Treat as a verified board fact, not a Gowin-documented limit.
- Relevant behavior: The A25 runs at the frequency of `PLL_R[0]` `CLKOUT1` regardless of which PLL output the netlist connects to `AE350_SOC` `CORE_CLK`. With 750 MHz on `CLKOUT0` wired to `CORE_CLK` and 75 MHz on `CLKOUT1`, a counted dependent-`addi` loop measured 74.85 MHz; changing only `CLKOUT1` to 50 MHz measured 49.85 MHz; generating 750 MHz on `CLKOUT1` and wiring it to `CORE_CLK` measured at least 725 MHz. Gowin timing analysis constrains the declared `CORE_CLK` net and does not detect the mismatch.
- Tang-Phosphor use: Generate the CPU clock on `CLKOUT1`, connect `CORE_CLK` to that output, and put the fabric bus clock on `CLKOUT0`. Do not accept a CPU frequency from the PLL configuration or timing report alone; confirm it on hardware with a counted-cycle measurement against wall time. `src/ae350/ae350_pll.v` at `292ae77` placed 750 MHz on `CLKOUT0` and 75 MHz on `CLKOUT1`, so the entry 18 smoke test ran the A25 at 75 MHz; entry 20 moved the CPU clock to `CLKOUT1`, and `tools/ae350_clock_probe.py` measured exactly 750.0000 MHz against the 50 MHz board oscillator.

---

## GW5AST Device Revision

### Tang Console 138K silicon revision

- Sources: Sipeed TangMega-138K-example repository, commit `06e7d8b118d345915ab6f257b7c22226f81575cd`, README and generated DDR3 IP; Tang-PSX `.ai/core-reference.md` record DEV-001 (https://github.com/aquasock/Tang-PSX).
- Authority: Sipeed board-vendor documentation plus a user photograph of the installed device, 2026-09-28.
- Relevant rule: The device revision is the fifth character of the package's second marking line. The installed device is marked `GW5AST-LV138PG484AC1/I0`, `2518CA0N`, `TS0E44.00`, so it is revision C. Sipeed's generated DDR3 IP targets revision C, and its README directs revision-B users to regenerate all Gowin IP.
- Tang-Phosphor use: Build for revision C (`set_device -name GW5AST-138C GW5AST-LV138PG484AC1/I0`) and generate all new Gowin IP for revision C. Tang-Phosphor artifacts through entry 18 were built for revision B; every build from entry 20 targets revision C. The committed `src/pll/` wrappers were generated for revision B but instantiate the same `PLL` primitive with the same parameter set as Gowin 1.9.11.03's revision-C generator output, and place-and-route accepted them for revision C.

---

## Gowin Synthesis

### Shift-register extraction breaks clock-domain synchronizers

- Sources: Gowin SUG550-2.0.1E GowinSynthesis User Guide, section 5.17 `syn_srlstyle` (installed with Gowin EDA 1.9.11.03 at `IDE/doc/EN/SUG550-2.0.1E_GowinSynthesis User Guide.pdf`); Tang-Phosphor core-log entry 20.
- Authority: Gowin primary tool documentation plus observed revision-C synthesis results.
- Relevant rule: GowinSynthesis infers shift registers by size and may implement them in SSRAM, BSRAM, or registers; `/* synthesis syn_srlstyle = "registers" */` on a register forces flip-flops.
- Observed behavior: For revision C, GowinSynthesis 1.9.11.03 folded the two-stage `joy_usb*_meta`/`controller_status_meta` synchronizers and the AE350 smoke reference-count synchronizer into SSRAM shift registers. The first stage then had no metastability protection, and because `get_regs` does not match SSRAM cells the SDC first-stage false path no longer applied, producing cross-clock setup and hold failures in every placement.
- Tang-Phosphor use: Mark every stage of every clock-domain synchronizer with `syn_srlstyle = "registers"`, and confirm after each build that no timing path ends at an SSRAM `DI` pin of a synchronizer.

---

## USB Full-Speed Host

### USB 2.0 Specification

- Source: https://www.usb.org/documents?category%5B0%5D=49&items_per_page=50&order=field_date_&search=usb+2.0&sort=desc
- Authority: USB Implementers Forum primary specification distribution.
- Relevant scope: USB full-speed uses a 12 Mb/s signaling rate and defines host transactions, control transfers, enumeration, endpoint behavior, and electrical requirements.
- Tang-Phosphor use: Treat 12 Mb/s as the signaling rate rather than application throughput and validate the host controller and firmware against the normative transaction and enumeration rules.

### Device Class Definition for HID 1.11

- Source: https://www.usb.org/document-library/device-class-definition-hid-111
- Authority: USB Implementers Forum primary HID class specification.
- Relevant scope: HID descriptors and reports are self-describing and require host parsing rather than assuming one fixed gamepad packet layout.
- Tang-Phosphor use: Start with a bounded controller profile, then add a generic HID report parser as a separate compatibility milestone.

### Gowin USB 1.1 SoftPHY

- Source: https://www.gowinsemi.com/en/support/ip_detail/83/
- Authority: Gowin primary IP documentation for supported FPGA devices.
- Relevant behavior: The SoftPHY supports 12 Mb/s full-speed and 1.5 Mb/s low-speed signaling, NRZI, bit stuffing, and an eight-bit UTMI interface; it does not provide a USB host controller or class stack.
- Tang-Phosphor use: Place the PHY between the FPGA pins and the selected UTMI host controller, with host scheduling and enumeration performed by RTL and AE350 firmware.

---

## Rockbox Codec Interface

### Rockbox rbcodec and codec API

- Sources: Rockbox `e45936397ee3677c910c9a0c6473184e9755040c` (`third_party/rockbox`), `lib/rbcodec/codecs/codecs.h`, `firmware/export/load_code.h`, `lib/rbcodec/test/warble.c`, and `lib/rbcodec/codecs/codecs.make`.
- Authority: Upstream Rockbox source, the only definition of its codec ABI.
- Relevant rule: A codec exports `struct codec_header` (`__header`): `lc_header` magic `CODEC_MAGIC` (`0x52434F44`), an `unsigned short` target ID, API version `CODEC_API_VERSION` (50), load and end addresses, `entry_point`, `run_proc`, a pointer to the codec's `ci`, and `sizeof(struct codec_api)`. The host must reject any mismatch. The `codec_api` layout depends on `NUM_CORES`, `DEBUG`/`SIMULATOR`, `ROCKBOX_HAS_LOGF`, `RB_PROFILE`, and `HAVE_RECORDING`, so host and codecs must be built with one configuration. Rockbox has no RISC-V target; codec binaries built for other targets cannot run on the A25.
- Tang-Phosphor use: Build codecs from source with warble's standalone configuration (`SDLAPP`, `APPLICATION`, `__PCTOOL__`, `WARBLE`) and target ID `0x5450`, link each as a static RV32 ELF at the 1 MiB codec buffer, and compare raw codec output with x86 warble built from the same revision. Rockbox native optimization levels (`-Os` base, per-library levels from `codecs.make`, `-O2` DSP) are kept.

### A25 cache model for performance estimates

- Sources: QEMU 10.2.1 `contrib/plugins/cache.c` (GPL-2.0), built by `tools/build-qemu-cache-model.sh`; Tang-PSX `.ai/core-reference.md` records AE350-004, AE350-009, and AE350-010.
- Authority: Simulation model parameterized by board measurements; not a cycle-accurate model of the A25 pipeline.
- Relevant behavior: The plugin models set-associative L1 instruction and data caches and a unified L2 with LRU replacement and counts misses per instruction; it does not model dirty write-backs, pipeline stalls, or miss overlap. The A25 caches are 32 KiB, 4-way, 32-byte lines; measured miss costs are about 570 core cycles to DDR3 through Tang-PSX's RAM path and about 240 for a hit in its 128 KiB fabric L2.
- Tang-Phosphor use: `tools/rbhost_profile.py` reports a CPU-load range bracketed by 1.0 cycle per instruction without write-backs and 1.5 cycles per instruction with a write-back for every data miss; any SDRAM figure is an estimate until measured on hardware.
