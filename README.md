# Tang-Phosphor

Tang-Phosphor is a hardware audio player and visualizer for the Sipeed Tang
Console 138K. The initial target is WAV and FLAC playback with FPGA-native
decoding and visualization. The deployment core still leaves the GW5AST AE350
CPU unused; a separate proof-of-life image now exercises it ahead of the
full-speed USB-host integration.

## Current milestone

The first bring-up core provides:

- Tang Console 138K clock and HDMI pinout
- 1280x720p60 video over the HDMI connector
- deterministic native 44.1/48 kHz HDMI audio with distinct 1 kHz left and 2 kHz right test tones
- streamed 16-bit stereo 44.1/48 kHz PCM WAV parsing and playback with buffered backpressure
- streamed 16-bit stereo 44.1/48 kHz native FLAC decoding with CRC-gated frame admission
- content-based WAV/FLAC identification with bounded, byte-exact prefix replay
- sample-contiguous gapless playlist playback between same-rate WAV/FLAC tracks
- a native 720p album/playlist screen with per-track album, artist, title, and
  embedded JPEG cover metadata, a six-track window, exact elapsed/total time,
  and progress
- controller playback actions: Start pauses/resumes, Left/Right select the
  previous/next playlist track, and X shows or hides the native screen
- a distinctive animated test pattern
- the standard TangCore BL616 UART interface and OSD
- a CRC-protected USB-to-FPGA debug register channel
- a credit-based SD-to-FPGA test stream with negotiated 5 Mbps transport
- experimental core ID `0x50`

The test tones provide a startup diagnostic until the first audio stream begins.
Stream prefill, completion, cancellation, and errors are silent so the
diagnostic source cannot leak into file playback. Playlist tracks are gapless:
once a track's final sample is queued, Tang-Control appends the next track's
stream behind it, and the 16,384-sample PCM FIFO carries the tail while the
successor starts decoding. The successor's first sample follows the
predecessor's last sample on the next sample period, and its rate, length,
clocks, and display metadata switch at that exact boundary. A successor at a
different native rate switches the sample cadence, HDMI clock regeneration
packet, and IEC channel status together at the boundary, so only same-rate
transitions are sample-contiguous. MP3 and Ogg Vorbis are outside the
current playback scope; DDR3 and the AE350 are not enabled in the deployment
core.

The current register map is documented in
[`docs/debug-registers.md`](docs/debug-registers.md).
The bounded audio architecture is documented in
[`docs/audio-pipeline.md`](docs/audio-pipeline.md).

Tang-Control's `feature/usb-cdc-file-transfer` branch at `fbbddc6` supplies the
SD-card file loader for core ID `0x50`. Its Phosphor menu can open standalone
WAV/FLAC files or VLC-style M3U/M3U8 playlists whose entries remain separate
SD files; no TAR container is required. TangCore's OSD is intentionally limited
to choosing audio or returning to the main menu; playback controls live in the
native Phosphor screen and are suppressed while the OSD is open.

Tang-Control reads FLAC Vorbis comments and front-cover PICTURE blocks, plus
standard WAV `LIST/INFO` text. Per-track tags override VLC `#EXTINF`, playlist
name, and filename fallbacks. JPEG covers are decoded on the BL616 to the same
92x92 RGB332 representation used by MiSTer-Phosphor and are published through
an independent double buffer. Audio backpressure remains authoritative while
the shared UART is interleaved, and no partially uploaded image is exposed.
Text and artwork travel as CRC-validated 64-word block writes (transport
capability bit 4), so a cover appears within about a second of a track
starting instead of waiting for one register write per audio frame. For a
gapless successor, text and artwork are prepared early in the inactive banks
and published when the core reports that stream as audible.

`tools/generate_gapless_test.py <dir>` writes a deterministic six-track
playlist that splits one continuous tone at non-frame-aligned samples across
FLAC and WAV tracks with covers and large metadata padding. Any seam is audible
as a click, and debug registers `0x9c`/`0xa0` count the boundaries and any
silence inserted at them.

## Build

Gowin EDA 1.9.11.x with support for the GW5AST-138 is required. Builds target
device revision C (`GW5AST-138C`), the revision of the Tang Console 138K's
installed FPGA.

```sh
GOWIN_VARIANT_CPUS="0 2 8 10" scripts/build-variants.sh
```

Set `GOWIN_SH` to the full path of `gw_sh` if it is not on `PATH`. The helper
also applies the Linux Qt/FreeType compatibility settings needed by some Gowin
EDA installations. The release-build helper runs Gowin placement options 0-3
in parallel, rejects any timing-failing result, and publishes the variant with
the strongest worst-case setup slack as the deployment artifact. Its comparison
is retained in `impl/variant-summary.tsv`, with the individual logs and reports
under `impl/variant-reports/`. `scripts/build.sh` remains available for a quick
single diagnostic build; `GOWIN_PLACE_OPTION` selects its placement option.

The TangCore-loadable image is generated at:

```text
impl/pnr/tang_phosphor_console138k.bin
```

Copy it to the SD card under `cores/console138k/` (or `cores/`) with a unique
name such as `tang-phosphor.bin`, then select it from TangCore's **Cores** menu.
The stock `monitor.bin` does not need to be replaced.

### AE350 proof of life

The opt-in smoke image instantiates the hardened AE350 directly, clocks its A25
core at 750 MHz with a 75 MHz fabric bus, fetches a six-instruction program at
the fixed `0x80000000` reset vector, and writes a status bit and then its
`mcycle` count through the extended AHB interface. The fabric pairs each count
with a count of the 50 MHz board oscillator so the core frequency can be
measured on hardware. It is isolated from the deployment build:

```sh
scripts/build-ae350-smoke.sh
```

The generated image and timing reports are written under `build/ae350-smoke/`.
Copy `tang_phosphor_ae350_smoke.bin` to `cores/console138k/` and select it from
TangCore's **Cores** menu. Its diagnostic tag is `0x0350`; the legacy TangCore
status command carries only the low byte, so it reports core `0x50`. With the
Tang-Control USB CDC client connected, the hardware result is checked with:

```sh
python3 ../Tang-Control/scripts/tangctl.py status
python3 ../Tang-Control/scripts/tangctl.py peek 0
python3 tools/ae350_clock_probe.py
```

`status` must report active core `80` (`0x50`), and `peek 0` must return
`0x00000001`. The latter value is produced only after the AE350 executes the
boot ROM and completes its CPU-to-fabric write; the deployment Phosphor core
instead returns its `0x54504830` magic at address zero. The clock probe freezes
count pairs with a debug write to `0x10`, reads them from `0x04` and `0x08`,
and must report 750 MHz. The A25 runs at the frequency of `PLL_R[0]` `CLKOUT1`
whatever the netlist connects to `CORE_CLK`, and timing analysis cannot detect
a mismatch, so repeat this measurement after any AE350 clock change. This
diagnostic image does not drive HDMI or either USB port. Power-cycle or select
the deployment core again after testing.

### Rockbox codecs on the AE350

`software/rbhost` runs Rockbox's codecs on the AE350's RV32 A25 through
Rockbox's own codec API (`codec_api` version 50). Rockbox is pinned as the
`third_party/rockbox` submodule and used unmodified. Its codecs, metadata
parsers, and DSP are compiled for `rv32imafdc`/`ilp32d` with the
standalone-codec configuration that Rockbox's `warble` test program uses; the
headers in `software/rbhost/config` take the place of warble's. Each codec is
a static RV32 ELF linked at a fixed 1 MiB codec buffer (target ID `0x5450`),
loaded by the host at run time as Rockbox native players load `.codec`
files. The current host runs under `qemu-riscv32`; a hardware host follows
once the AE350 has external memory.

```sh
git submodule update --init third_party/rockbox
make -C software/rbhost          # build/rbhost/rbhost-qemu and codecs/*.codec
make -C software/rbhost check    # FPGA FLAC regression vectors, bit-exact
qemu-riscv32 build/rbhost/rbhost-qemu build/rbhost/codecs in.flac out.wav
```

`tools/rbhost_profile.py` encodes an excerpt of any audio file in eleven
formats, requires the RV32 raw codec output to match x86 `warble` (built by
`tools/build-warble-reference.sh`) and lossless output to match the source,
and estimates AE350 CPU load with an A25 cache model built by
`tools/build-qemu-cache-model.sh`. The RISC-V toolchain is the Xuantie
`riscv64-unknown-elf` GCC used by the BL616 and Tang-PSX builds.

## Licensing and provenance

Tang-Phosphor is distributed under GPL-3.0. The initial board-support, BL616
interface, OSD, PLL, and HDMI integration are derived from nand2mario's
TangCore Monitor Core at commit `e4446093a754205f46e7000e6ef1bf37176bda19`.
The AE350 primitive wiring is based on BSD-2-Clause LiteX integration work.
See [THIRD_PARTY.md](THIRD_PARTY.md) for details.
