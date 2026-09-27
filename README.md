# Tang-Phosphor

Tang-Phosphor is a hardware audio player and visualizer for the Sipeed Tang
Console 138K. The initial target is WAV and FLAC playback with FPGA-native
decoding and visualization. The GW5AST AE350 CPU is intentionally not used.

## Current milestone

The first bring-up core provides:

- Tang Console 138K clock and HDMI pinout
- 1280x720p60 video over the HDMI connector
- deterministic native 44.1/48 kHz HDMI audio with distinct 1 kHz left and 2 kHz right test tones
- streamed 16-bit stereo 44.1/48 kHz PCM WAV parsing and playback with buffered backpressure
- a distinctive animated test pattern
- the standard TangCore BL616 UART interface and OSD
- a CRC-protected USB-to-FPGA debug register channel
- a credit-based SD-to-FPGA test stream with negotiated 5 Mbps transport
- experimental core ID `0x50`

The test tones remain the idle and error fallback, while a valid WAV stream
automatically takes over HDMI audio after its PCM FIFO has prefetched enough
samples to cover transport turnaround. The sample cadence, HDMI clock
regeneration packet, and IEC channel status switch together at the WAV's native
44.1 or 48 kHz rate. FLAC, MP3, Ogg Vorbis, DDR3, and the AE350 are not enabled
yet.

The current register map is documented in
[`docs/debug-registers.md`](docs/debug-registers.md).
The bounded audio architecture is documented in
[`docs/audio-pipeline.md`](docs/audio-pipeline.md).

Tang-Control's `feature/usb-cdc-file-transfer` branch at `e3aa4f9` supplies the
SD-card file loader for core ID `0x50`. Its Phosphor menu can open standalone
WAV files or VLC-style M3U/M3U8 playlists whose entries remain separate SD
files; no TAR container is required.

## Build

Gowin EDA 1.9.11.x with support for the GW5AST-138 is required.

```sh
scripts/build.sh
```

Set `GOWIN_SH` to the full path of `gw_sh` if it is not on `PATH`. The helper
also applies the Linux Qt/FreeType compatibility settings needed by some Gowin
EDA installations.

The TangCore-loadable image is generated at:

```text
impl/pnr/tang_phosphor_console138k.bin
```

Copy it to the SD card under `cores/console138k/` (or `cores/`) with a unique
name such as `tang-phosphor.bin`, then select it from TangCore's **Cores** menu.
The stock `monitor.bin` does not need to be replaced.

## Licensing and provenance

Tang-Phosphor is distributed under GPL-3.0. The initial board-support, BL616
interface, OSD, PLL, and HDMI integration are derived from nand2mario's
TangCore Monitor Core at commit `e4446093a754205f46e7000e6ef1bf37176bda19`.
See [THIRD_PARTY.md](THIRD_PARTY.md) for details.
