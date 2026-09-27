# Tang-Phosphor

Tang-Phosphor is a hardware audio player and visualizer for the Sipeed Tang
Console 138K. The initial target is WAV and FLAC playback with FPGA-native
decoding and visualization. The GW5AST AE350 CPU is intentionally not used.

## Current milestone

The first bring-up core provides:

- Tang Console 138K clock and HDMI pinout
- 1280x720p60 video over the HDMI connector
- silent 48 kHz HDMI audio packets, ready for the test-tone milestone
- a distinctive animated test pattern
- the standard TangCore BL616 UART interface and OSD
- a CRC-protected USB-to-FPGA debug register channel
- a credit-based SD-to-FPGA test stream with negotiated 5 Mbps transport
- experimental core ID `0x50`

Audio decoding, codecs, DDR3, and the AE350 are not enabled yet. The current
stream sink verifies transport counters and CRC, then discards the bytes; it
will become the input FIFO for WAV playback.

The current register map is documented in
[`docs/debug-registers.md`](docs/debug-registers.md).

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
