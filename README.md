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
- streamed 16-bit stereo 44.1/48 kHz native FLAC decoding with CRC-gated frame admission
- content-based WAV/FLAC identification with bounded, byte-exact prefix replay
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
Stream prefill, playlist boundaries, completion, cancellation, and errors are
silent so the diagnostic source cannot leak into file playback. The last valid
sample rate is retained between tracks; the sample cadence, HDMI clock
regeneration packet, and IEC channel status switch together only when the next
source has valid native-rate metadata. MP3 and Ogg Vorbis are outside the
current project scope; DDR3 and the AE350 are not enabled.

The current register map is documented in
[`docs/debug-registers.md`](docs/debug-registers.md).
The bounded audio architecture is documented in
[`docs/audio-pipeline.md`](docs/audio-pipeline.md).

Tang-Control's `feature/usb-cdc-file-transfer` branch at `3636da1` supplies the
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
starting instead of waiting for one register write per audio frame.

## Build

Gowin EDA 1.9.11.x with support for the GW5AST-138 is required.

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

## Licensing and provenance

Tang-Phosphor is distributed under GPL-3.0. The initial board-support, BL616
interface, OSD, PLL, and HDMI integration are derived from nand2mario's
TangCore Monitor Core at commit `e4446093a754205f46e7000e6ef1bf37176bda19`.
See [THIRD_PARTY.md](THIRD_PARTY.md) for details.
