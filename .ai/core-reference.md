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

---

## Dock PMOD Sockets

### Tang Console dock PMOD socket pins and numbering

- Sources: TangCore commit `f69c6ff`, `monitor/src/boards/console.cst` (PMOD1_IO0-7 as DualShock pins, PMOD0_IO0-7 as LEDs) and `nestang/src/boards/console60k_snescontroller.cst` (one SNES controller per socket on IO0/2/4 and IO1/3/5); litex-boards commit `e4307929c38a`, `litex_boards/platforms/sipeed_tang_console.py` (`_dock_connectors` pmod0, pmod1); Tang-PSX `.ai/core-reference.md` record BRD-004 (https://github.com/aquasock/Tang-PSX).
- Authority: Board-vendor and upstream-core constraint files, plus hardware verification on this dock on 2026-10-02. Treat as a verified board fact, not a Digilent-documented limit.
- Relevant rule: PMOD1, the socket beside the HDMI port, carries PMOD1_IO0-IO7 on FPGA pins W19 W20 F19 F20 E22 D22 E21 D21, and PMOD0 carries PMOD0_IO0-IO7 on V18 V19 G21 G22 F18 E18 C22 B22, all LVCMOS33. Sipeed's IO numbering interleaves the rows, so IO0, IO2, IO4 and IO6 are Digilent pins 1-4 and IO1, IO3, IO5 and IO7 are pins 7-10; a LiteX connector index is Sipeed's IO number, not the linear pin order.
- Tang-Phosphor use: `src/boards/console138k_pmod.cst` binds both sockets, not any module, so every personality and every future PMOD experiment reuses one constraint file and a change of module never invalidates a placement; `src/boards/console138k_oled.cst` remains the panel-only bring-up file. An unselected socket must have every pin released.
- Derived rule, verified on hardware 2026-10-02: because the two rows are interleaved, turning a module over swaps adjacent IO numbers, so flipped seating in Sipeed numbering is exactly IO index XOR 1. Orientation is therefore one rotate of the lane vector and needs no remap table and no second constraint file.

### Tang Mega NEO Dock schematics describe a different accessory

- Sources: `Documents/Tang_Mega_NEO_Dock-138K_31004_Schematics.pdf` and `..._31005_Schematics.pdf`, which name `PMOD0_IOx` and `PMOD1_IOx` on balls shared with SDRAM1 and the camera port.
- Authority: Schematic text extraction, compared against the board actually being driven.
- Relevant rule: those sheets do not describe this dock. Their PMOD0_IO0-IO7 net is carried on P19 R19 T21 U21 P16 R17 R18 T18 and their PMOD1_IO0-IO7 net on Y21 Y22 AB21 AB22 AA20 AA21 AA19 AB20, neither of which matches the balls the OLED panel actually ran on. The many NEO Dock `PMODx_IOx` labels coexist with SDRAM1 and CAM0 signals on one connector, which is a shared-header arrangement this dock does not have.
- Tang-Phosphor use: Do not take pin assignments from those sheets. Use the hardware-verified socket balls above, and treat the discrepancy as unexplained rather than resolved: the sheets may belong to a different dock revision or to a related accessory.

### PMOD configuration file (tang.ini)

- Sources: Project decision recorded with the user on 2026-10-02, following the MiSTer.ini convention; Tang-PSX PmodVGA dual-socket evidence in record BRD-005.
- Authority: Project convention, not an external standard.
- Relevant rule: `/tang.ini` at the SD-card root is the contract between what is physically seated and what the gateware drives, because PMOD modules carry no identification pins and presence cannot be detected. Keys are flat under one `[tang]` section: `pmod0 = <module>`, `pmod0_flip = yes|no`, and the same for `pmod1`.
- Tang-Phosphor use: A missing file, or a socket with no entry, leaves that socket released, so the absent file is the safe state and no PMOD output appears until the user configures one. Unknown module names, a `vga_j1` without its `vga_j2` partner, and `flip = yes` for a module that is not flip-safe are all refused rather than guessed. The core reports which personalities it supports so the registry lives beside the RTL that implements it, while the parser belongs to Tang-Control, which owns the SD card and the transport. `pmod_mirror_top`'s personality and orientation parameters are the register seam this file will drive.

---

## Integer Scaling

### One frame store, one mapper per backend

- Sources: Project decision and hardware verification, 2026-10-02; the aspect arithmetic in this record.
- Authority: Project convention, derived from the three target aspect ratios and confirmed on hardware.
- Relevant rule: A single native resolution cannot fill 96x64 (3:2), 800x600 (4:3) and 1280x720 (16:9) without interpolation, because filling a screen at an equal integer factor in both axes forces the native aspect to equal that screen's aspect, and the three differ. The only resolutions that divide all three exactly are 32x8 and smaller by a factor of two. Rendering at the panel's own 96x64 is therefore the compromise: the panel, the smallest and least forgiving display, is filled exactly, and each larger screen gets the largest integer factor that fits with symmetric bars. The best single alternative aspect, the geometric mean sqrt(4/3 x 16/9) = 1.5396, raises the worst-case coverage only from 84.4 percent to 86.6 percent, and the best integer realisation of it is a grid too coarse to render a menu.
- Tang-Phosphor use: Render at 96x64 and scale by 1 for the panel, 8 for 800x600 (768x512 centred) and 11 for 1280x720 (1056x704 centred at (112, 8)).

### Digilent PmodVGA pinout and sync polarity

- Sources: Digilent PmodVGA Reference Manual, https://digilent.com/reference/pmod/pmodvga/reference-manual (pin table) and rev C.0 schematic 500-345; Tang-PSX `.ai/core-reference.md` record BRD-005 and `gateware/vga_output.py`; hardware verification on this bench 2026-10-02.
- Authority: Vendor primary documentation plus a hardware test on this dock.
- Relevant rule: The module is a dual PMOD. J1 carries red R0-R3 on pins 1-4 and blue B0-B3 on pins 7-10; J2 carries green G0-G3 on pins 1-4, horizontal sync on pin 7, vertical sync on pin 8, and pins 9-10 are not connected. Two SN74ALVC245 buffers drive per-colour resistor ladders in which bit 3 is the most significant step, so the top four bits of each 8-bit channel are the correct mapping, and every module pin is a buffered input, so a wrong placement or orientation only loses the picture.
- Sync polarity: the polarity belongs to the raster, not to the module. CEA-861 VIC 4, which is 1280x720 at 60 Hz and the mode the transmitter produces, uses positive sync; the 640x480 convention Tang-PSX used is negative. A monitor that follows CEA locks on the positive form.
- Tang-Phosphor use: `src/pmod/pmod_vga.sv` presents one half of the module per socket with a parameter selecting J1 or J2, so which socket carries which half is a declaration and upside-down seating is the socket layer's existing `flipped` bit. `src/video/ui_vga_backend.sv` takes the raster and colour from the HDMI transmitter rather than generating its own timing, which is Tang-PSX's arrangement and the reason the VGA needed no second clock. A true 800x600 mode was rejected because 40 MHz cannot be derived from the 74.25 MHz pixel clock by a clock enable.

### The pixel latency is not one number

- Sources: `tests/ui_hdmi_scan_tb.sv`, which failed on the single-constant version of this rule, 2026-10-02.
- Authority: Hardware measurement through simulation of the real composition; a project implementation rule, not an external standard.
- Relevant rule: The registered stages between an output coordinate and its pixel differ per axis. Horizontally the coordinate changes every clock, so the scan mapper's registered mapping is one output pixel behind and the frame store's registered read adds another, requiring two pixels of correction. Vertically the coordinate changes once per line, so the mapper's register is already aligned with the line it belongs to and the store returns that same line's pixel, requiring no correction. A shared constant shifts the whole image by one source row.
- Tang-Phosphor use: `src/video/ui_hdmi_scan.sv` carries `X_LATENCY` and `Y_LATENCY` separately, and the bar decision is taken combinationally from the coordinate the transmitter presents rather than from a delayed mapper output, because the colour presented must belong to that coordinate. A paced backend such as the OLED engine, which holds a coordinate for a whole 16-bit transfer, needs no correction on either axis.

### Digilent Pmod OLEDrgb pinout and orientation

- Sources: Digilent Pmod OLEDrgb Reference Manual, https://digilent.com/reference/pmod/pmodoledrgb/reference-manual (J1 pin table and the 32-step initialisation list); SSD1331 controller datasheet; a local copy of the reference manual printed by the user at `Documents/Pmod OLEDrgb Reference Manual - Digilent Reference.pdf`.
- Authority: Vendor primary documentation for the module and its controller.
- Relevant rule: J1 carries pin 1 CS#, pin 2 MOSI, pin 3 not connected, pin 4 SCK, pins 5 and 11 GND, pins 6 and 12 VCC3V3, pin 7 D/C#, pin 8 RES#, pin 9 VCCEN and pin 10 PMODEN; the SSD1331 speaks write-only SPI in mode 3 and every module signal is an input driven by the host, so VCCEN low removes the panel rails and PMODEN high connects the logic ground.
- Orientation rule: the module seats with its ICs facing up, away from the dock, which is the same seating the verified PmodVGA placement uses in Tang-PSX record BRD-005. Because both headers share the mechanical PMOD layout, turning a module over swaps pins 1-4 with pins 7-10 while power and ground stay on their own pins; that consequence is inferred from the mechanical layout for this module, not measured here.
- Tang-Phosphor use: Bring the module up as its own single-purpose core that owns no player logic, hold chip select low across each whole sequence, map RGB565 colour as `0xF800` red, `0x07E0` green and `0x001F` blue, and judge the result from the panel itself, since that core deliberately exposes no debug transport.

### Debug transport core ids

- Sources: Tang-Control `usb/usb_cdc_console.cpp` (the `require_ext_core` gate and its message) and `core/tangpsx.cpp` (`CORE_ID = 0x51`); hardware confirmation on this bench 2026-10-02.
- Authority: The host firmware, which is the only definition of the gate.
- Relevant rule: The extended debug protocol behind `caps`, `peek`, `poke` and `baud` is refused unless the active core reports id `0x50`. Id `0x51` is Tang-PSX's. Any new core that wants the debug bus must either report `0x50` or the firmware must be changed and reflashed.
- Tang-Phosphor use: The PMOD socket bring-up core reports `0x50` deliberately, so the existing host tools work unchanged. A dedicated id belongs with the `/tang.ini` parser, because that parser lives in the same firmware and the same rebuild can carry both changes.

### Socket configuration over the debug bus

- Sources: `src/debug/ui_debug_regs.sv` and the hardware test recorded in core-log entry 50.
- Authority: Project interface definition.
- Relevant rule: Register `0x10` is the socket control register. Bit 0 holds the renderer, bits 4-7 are the PMOD0 personality, bits 8-11 the PMOD1 personality, bit 12 is PMOD0 seated upside down and bit 13 is PMOD1. Personality numbering is 0 none, 1 oledrgb, 2 vga J1 and 3 vga J2. Register `0x14` is scratch. Reads: `0x00` magic `0x54504830`, `0x04` build date, `0x08` uptime, `0x0c` render frames, `0x18` source bank, `0x20`/`0x24` panel frames and checksum, `0x28`/`0x2c` HDMI, `0x30`/`0x34` VGA. The control read's bits 18:16 carry the renderer's frame selector: the demo reported which of eight test patterns it was drawing, and a menu frame writer reports which published frame it is on, which slice 1 fixes at zero because it draws exactly one. The field keeps its position and width in both the bring-up and the player maps so the host decoding does not move.
- Tang-Phosphor use: This is the seam `/tang.ini` writes through. Power-on defaults select the panel on PMOD0 and nothing on PMOD1, which is the safe state, and the host is the only party that validates a declaration because it is the only party that knows what the user wrote.

### Socket control and stream routing in the merged player map

- Sources: `src/debug/debug_regs.sv`, `src/tang_phosphor_top.sv` and `tests/debug_regs_tb.sv` at register ABI 1.8; hardware test recorded in core-log entry 71.
- Authority: Project interface definition.
- Relevant rule: The previous record's `0x10` is the bring-up core's map only. In the merged player map the socket control word is `0x00c0`, with the same bit layout (hold `[0]`, PMOD0 personality `[7:4]`, PMOD1 `[11:8]`, flips `[12]` and `[13]`, frame selector read at `[18:16]`) plus personality `4` for the rotary encoder, and it powers up with both sockets released. Stream routing (`cpu_mode`, bit 0: clear feeds the BL616 stream to the FPGA player, set feeds the AE350 loader) is its own word at `0x00a8`, readable, and register ABI `0x04` reads `0x00010008` from that change on. Before ABI 1.8 `cpu_mode` was also bit 0 of `0x00c0`, so a host selecting the CPU for a track released both sockets and held the renderer, and a socket declaration with bit 0 clear deselected the CPU.
- Tang-Phosphor use: A host must select the CPU at `0x00a8` and declare sockets at `0x00c0`, and should refuse a core whose ABI is older than 1.8, since that core ignores `0x00a8` and plays the file's bytes raw. The standard OLEDrgb-plus-encoder declaration is `0x2410`.

### Mirror check verdicts

- Sources: `tools/ui_mirror_check.py`, `src/ui/ui_checksum.sv`; core-log entries 50 and 51.
- Authority: Project interface and tooling, grounded in two real false alarms recorded in entry 51.
- Relevant rule: Three verdicts are required, not one. MIRROR compares each measured stream against a model computed on the host; a frozen frame passes it legitimately, because screens showing the same frozen frame are mirrored. LIVENESS requires the frame counters to advance and is the only thing that catches a stopped renderer. HELD reports that the renderer is frozen on purpose, so a frozen signature is expected and liveness is not required.
- Tang-Phosphor use: The tool sets the renderer hold before reading so it compares whole settled frames, and restores the hold state it found, because leaving a renderer frozen is precisely how the first false alarm happened. Held-ness is established by observing whether frames are being produced, never by trusting the control register's hold bit: that register once wrote hold at bit 0 and read it back at bit 3, and a tool that assumed the layout read a frame-selector bit as held. A signature is only meaningful beside the frame counters it belongs to.

### PmodVGA on a CRT

- Sources: Hardware observation on the Dell E773c, the same monitor Tang-PSX record BRD-005 verified its VGA path on, 2026-10-02.
- Authority: Bench observation.
- Relevant rule: A CRT accepts the transmitter's 1280x720 raster directly and its height, width and position controls provide the overscan or underscaling to frame the picture, so no second video mode is needed for the VGA port. The bars remain part of the emitted signal regardless of how the tube is adjusted, so a check compares the signal, not what the user sees.
- Tang-Phosphor use: This retires the 800x600 branch, and with it the 40 MHz pixel clock, the asynchronous FIFO, the duplicated store and the clock-domain crossing that would have given back the single-clock coherence the rest of the design depends on. Underscanning deliberately is how raster edges and bars get inspected by eye.

### Fmax attribution on this core

- Sources: Gowin place-and-route reports for the PMOD bring-up core, 2026-10-02; core-log entry 52.
- Authority: Measured on this netlist, not inferred.
- Relevant rule: The critical path is `rgb` through the HDMI transmitter's TMDS encoder -- the `q_m` XOR/XNOR network, the population counts and the running-disparity accumulator -- at seventeen logic levels. The `q_m` stage is eight serial XORs by construction, so that depth is inherent to TMDS encoding. Across placement options the reported Fmax spans eleven MHz: option 0 fails at 65.724 MHz while 2, 3 and 4 reach 77.543, 76.412 and 77.500. The design therefore sits near the edge and the placement option decides which side it lands on.
- Tang-Phosphor use: `build-pmod.tcl` pins option 2 with the measurements recorded beside it and must be re-measured when the netlist changes materially. Do not pipeline the disparity accumulator to buy margin: it is a feedback loop in third-party code and an error there breaks HDMI output rather than costing frequency. If margin ever genuinely bites, stage the encoder deliberately and validate against the mirror check.

### The panel stream is the independent one

- Sources: `tools/ui_mirror_check.py`, `src/oled/oled_panel.sv`; core-log entry 52 hardware result.
- Authority: Bench measurement.
- Relevant rule: The PmodVGA observes the transmitter's raster and cannot disagree with it, so a checksum there would be evidence of nothing. The panel has its own mapper, its own rate and its own physical path. Because it emits the store at 1:1 with no bars, in the order the renderer writes, its expected fold equals the source's, and on hardware both read 0xd6991800 while the transmitter's scaled stream reads its own value. Source and panel signatures agreeing is the strongest available evidence that the store reaches the display, since they are folded off physically independent paths.

### The frame store has one owner

- Sources: `src/ui/ui_frame_bank.sv`; core-log entries 52 and 53.
- Authority: Project structure, adopted after the risk below was found in review.
- Relevant rule: `ui_frame_bank` owns the write bus and instantiates the store copies, so no caller can feed one copy differently from another and one source of truth is a property of the structure rather than a convention of the top level. Each output has its own read port, and each backend must read the bank it latched at its own frame boundary, never the live shared value: the swap controller flips the shared bank when the last registered output crosses a frame, which need not be this one.
- Tang-Phosphor use: A latch that exists but is not wired to its read port is worse than no latch, because the comment then documents protection the circuit does not have. That is exactly what happened to the transmitter's bank latch between entries 48 and 53, and because the third-party transmitter cannot be elaborated by this project's simulator, only the mirror check could confirm the correction. Moving structure around is worth it for the review it forces.

### Digilent Pmod ENC pinout, and the second meaning of `flipped`

- Sources: `Documents/Pmod ENC Reference Manual - Digilent Reference.pdf`; hardware measurement on this bench 2026-10-02.
- Authority: Vendor primary documentation plus hardware verification.
- Relevant rule: J1 carries pin 1 A and pin 2 B, the quadrature pair, pin 3 BTN and pin 4 SWT, with the usual power and ground on 5, 11 and 6, 12. A and B are pulled high by the module and go low as the shaft turns. BTN reads low in its native, released state and SWT reads low when off. All four pins are inputs to the host, so the socket drives nothing and the module is orientation-safe.
- Verified contract: one detent is exactly four quadrature counts, measured twice, five clicks giving +20 and four clicks giving +16. A consumer divides by four and may treat any other delta as a broken module rather than a condition to handle. The count is incremental and resets to centred when the core reloads, so a consumer must treat a reset as position unknown rather than assuming the knob is where it was. Nothing latches or queues, so a press shorter than the polling interval will be missed, deliberately, because the alternative is an event layer this control does not warrant.
- `flipped`, second meaning: the bit was introduced for an upside-down module, where it swaps the socket's two rows. A 1x6 module such as the Pmod ENC occupies one row of a 2x6 socket rather than spanning both, so seating it in the other row presents exactly the same electrical situation and the same bit corrects it. Two physical causes, one declaration.

### The menu renderer writes the store, it does not shade a raster

- Sources: `src/ui/phosphor_album_ui.sv`, `src/ui/ui_menu_renderer.sv`, `src/ui/ui_frame_bank.sv`, `src/ui/phosphor_ui_control.sv`; core-log entries 47, 60 and 62.
- Authority: Project structure, settled before the menu work was written so the shape was decided while changing it was still cheap.
- Relevant rule: copy `ui_pattern_demo`, not `phosphor_album_ui`. The album UI is a pixel-rate overlay evaluator: the raster hands it `(x, y, rgb_in)` and it returns `rgb_out`, looking glyphs and artwork up by address while the beam passes, laid out on a 16x20 cell grid. A menu at 96x64 needs the opposite shape, a frame writer that fills the back bank, raises `render_done` and waits for `render_enable`. It is a new module against that contract that shares only the state inputs; it is not a port of 865 lines, and treating it as one would carry a cell geometry that cannot fit and a per-pixel evaluation the frame store makes pointless.
- Geometry: a 6x8 cell tiles 96x64 exactly, 16 columns by 8 rows with nothing over. 16x20 cells cannot fit at this size, so the layout is redesigned rather than shrunk.
- Text: characters come from the host. `phosphor_ui_control` owns `text_memory`, a 256x32 block RAM the transport writes and which is double-buffered, so the character path and Tang-Control's protocol stay as they are. The host owns text; the FPGA owns glyphs.
- Slice order, one cycle each: the contract first, a renderer that fills the store in order and honours the handshake while drawing a fixed frame derived from cell indices, which proves the 16x8 cell addressing before any glyph exists; then the 6x8 font and the text grid, with a test that renders known strings and checks the pixels; then content and layout from the state inputs already wired; then re-verification of both configurations, because panel and VGA need different seatings and different socket declarations and the encoder becomes the menu's control.
- Slice 1, implemented: `src/ui/ui_menu_renderer.sv` replaces `ui_pattern_demo` in `pmod_mirror_core`; the demo is retained in the tree as the reference implementer of the contract but is no longer instantiated, and `tools/ui_mirror_check.py` now models the cell frame rather than the eight patterns. A frame writer that sampled `render_enable` on the cycle `render_done` is raised would start the next frame into the bank it just filled, because the swap has not yet lowered `render_enable`; the demo hid behind its dwell and the menu does not, so the renderer waits for the swap to acknowledge the pulse and complete before it begins a frame.
