## 1 COMMIT Unreleased 2026-09-27T09:42:17-07:00

#### Coming From:

Unreleased 40fe578

#### Purpose:

Establish a hardware-proven build baseline and exercise the complete project workflow with the first `.ai`-managed audit cycle.

#### Outcome:

The Verilator extended-protocol simulation and a clean Gowin EDA 1.9.11.03 build for `GW5AST-LV138PG484AC1/I0` revision B passed, with zero setup or hold violations, worst setup slack of `+1.620 ns`, worst hold slack of `+0.202 ns`, and loadable artifact SHA-256 `7e607ff253617b1e92a8d73ade922dcd795b13c8fe2f518597811bd2262b5828`. The artifact was uploaded as `cores/console138k/tang-phosphor-audit-20260927.bin`, and its `4402580`-byte SD readback matched CRC-32 `bfe0f8e2`. The user confirmed the animated HDMI pattern and OSD appeared normally, while agent probes confirmed core ID `0x50`, protocol version 1, capabilities `0x0000000f`, magic `0x54504830`, advancing clock and frame counters, zero transport errors, and successful scratch-register write/readback with restoration to zero. The audit identified a missing documented host client, a dormant undersized FDD transmit index, an incorrect hardcoded controller update clock, and limited automated coverage for later cycles; the required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Propose a bounded remediation cycle for the in-repository host client, FDD transmit-index width, frequency-derived controller update interval, and focused regression coverage before implementing those changes.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 2 COMMIT Unreleased 2026-09-27T10:05:29-07:00

#### Coming From:

Unreleased 56d8479

#### Purpose:

Replace the approximate silent HDMI audio source with a deterministic, resettable 48 kHz stereo hardware test and apply relevant verification practices from the Colibri reference project.

#### Outcome:

A parameterized fractional-rate source now produces an exact-average 48 kHz sample cadence with a 1 kHz left-channel and 2 kHz right-channel test tone, while the HDMI audio capture, buffering, clock-regeneration state, and channel identifiers no longer rely on the audio-specific declaration initializations flagged during the baseline audit. A new self-checking Verilator test verified 48 sample edges per millisecond, bounded 1,546/1,547-pixel-clock spacing, waveform content, absence of unknown output state, and deterministic restart; the existing transport regression also passed. Gowin EDA 1.9.11.03 built the `GW5AST-LV138PG484AC1/I0` revision B target with zero setup or hold violations, worst setup slack of `+1.679 ns`, worst hold slack of `+0.225 ns`, and artifact SHA-256 `7c243d02b76b18236caabedb11147d0d4b3182cb85fc3129c748b8752e920f1d`. The `4402580`-byte artifact was uploaded as `cores/console138k/tang-phosphor-audio-test-20260927.bin`, its SD readback matched CRC-32 `483b4908`, and the user confirmed that video, OSD, HDMI audio identification, and both distinct stereo tones passed on hardware. Post-test probes confirmed protocol version 1, capabilities `0x0000000f`, magic `0x54504830`, advancing clock and frame counters, and zero transport CRC or malformed-request errors; the required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Replace the temporary audio test tones with the intended core audio interface when its producer is defined, and separately propose the bounded transport and controller-timing remediation identified by the baseline audit.

#### Files Modified:

- build.tcl
- src/audio_test_source.sv
- src/hdmi/audio_clock_regeneration_packet.sv
- src/hdmi/audio_sample_packet.sv
- src/hdmi/packet_picker.sv
- src/phosphor_video.sv
- tang_phosphor_console138k.gprj
- tests/audio_test_source_tb.sv
- tests/run.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 3 COMMIT Unreleased 2026-09-27T10:17:42-07:00

#### Coming From:

Unreleased 8038b8c

#### Purpose:

Harden the proven bring-up baseline by correcting the dormant FDD response counter, deriving controller timing from the configured logic clock, expanding regression coverage, and documenting Tang-Control as the authoritative host client.

#### Outcome:

The shared transmit index is now sized for the complete FDD sector response, allowing the state machine to emit the two-byte sector identifier and all 512 data bytes before terminating, and the 20 ms controller update interval now derives from the `FREQ` parameter rather than an assumed 50 MHz clock. The self-checking interface regression now validates the full 515-byte FDD payload, exactly 512 FIFO advances, frequency-derived controller timing at a non-default 40 MHz configuration, and joystick response framing in addition to the existing debug and stream protocol coverage; the exact-48-kHz audio regression also passed. Documentation now invokes `scripts/tangctl.py` exclusively from the sibling Tang-Control `feature/usb-cdc-file-transfer` branch at `a66796e`, with no Tang-Control client copied into this repository, and the README reflects the hardware-proven stereo test tones. Gowin EDA 1.9.11.03 built the `GW5AST-LV138PG484AC1/I0` revision B target with zero setup or hold violations, worst setup slack of `+1.084 ns`, worst hold slack of `+0.201 ns`, and artifact SHA-256 `6cc35506d52152e4805da693b9ac73830579c845ff9f67f6ecc3d1905db9b422`. The `4402580`-byte artifact was uploaded as `cores/console138k/tang-phosphor-hardening-20260927.bin`, its SD readback matched CRC-32 `c9a27f6f`, and the user confirmed video, OSD, stereo audio, and controller behavior all passed on hardware. Post-test probes confirmed core ID `0x50`, protocol version 1, capabilities `0x0000000f`, magic `0x54504830`, advancing clock and frame counters, and zero transport drops, timeouts, CRC errors, malformed packets, or unexpected responses; the required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Define the streamed PCM and WAV input contract, buffering, backpressure, clock-domain boundaries, and diagnostics before replacing the discard sink and temporary test tones with the first real playback path.

#### Files Modified:

- README.md
- docs/debug-registers.md
- src/iosys/iosys_bl616.v
- tests/iosys_debug_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 4 COMMIT Unreleased 2026-09-27T11:26:33-07:00

#### Coming From:

Unreleased cc41f87

#### Purpose:

Add the first FPGA-native streamed PCM WAV playback path while preserving the proven HDMI test tones as an idle and error diagnostic.

#### Outcome:

The core now parses RIFF/WAVE chunk structure, accepts signed 16-bit stereo 48 kHz PCM, propagates valid/ready backpressure into the existing credit-based BL616 stream, prefills a 2,048-sample block-RAM FIFO, recovers from counted underruns with silence, drains trailing bytes, and returns to the diagnostic tones after the final sample. The new self-checking regression covered odd-sized unknown chunks, PCM ordering, forced FIFO backpressure, underrun recovery, EOF, unsupported 44.1 kHz rejection for this bounded first milestone, premature transport end, and cancellation; all regressions passed. Gowin EDA 1.9.11.03 built the `GW5AST-LV138PG484AC1/I0` revision B target with zero setup or hold violations, worst setup slack of `+1.438 ns`, worst hold slack of `+0.209 ns`, and artifact SHA-256 `7499e67ceca3cf97e002e15aa27d9da1c454139667a07045482f3803e514255e`. The `4466068`-byte artifact was uploaded as `cores/console138k/tang-phosphor-wav48-20260927.bin`, and its SD readback matched CRC-32 `71792b23`. A deterministic six-second WAV generated by `tools/generate_wav_test.py` streamed all `1152044` bytes with CRC-32 `52207251`; diagnostics reported valid 48 kHz format, exactly `288000` samples played, zero underruns, and zero transport errors, while the user confirmed perfect left-only, right-only, then stereo playback followed by the tone fallback. The required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Implement and independently qualify native 44.1/48 kHz HDMI rate selection, then enable 44.1 kHz PCM WAV through the existing parser, FIFO, diagnostics, and playback boundary.

#### Files Modified:

- .gitignore
- README.md
- build.tcl
- docs/audio-pipeline.md
- docs/debug-registers.md
- src/audio/pcm_sample_fifo.sv
- src/audio/wav_decoder.sv
- src/audio/wav_stream_player.sv
- src/audio_test_source.sv
- src/debug/debug_regs.sv
- src/phosphor_video.sv
- src/stream/stream_debug_sink.sv
- src/tang_phosphor_top.sv
- tang_phosphor_console138k.gprj
- tests/audio_test_source_tb.sv
- tests/run.sh
- tests/wav_stream_player_tb.sv
- tools/generate_wav_test.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 5 COMMIT Unreleased 2026-09-27T11:50:47-07:00

#### Coming From:

Unreleased 813230d

#### Purpose:

Add hardware-qualified native 44.1/48 kHz HDMI rate selection and enable 44.1 kHz PCM WAV playback through the existing streamed audio path.

#### Outcome:

The WAV parser now accepts the bounded 16-bit stereo 44.1/48 kHz profile, while a runtime fractional timebase switches the sample cadence during FIFO prefill and drives matching HDMI Audio Clock Regeneration and IEC 60958 channel-status metadata. Rate changes are adopted only at a 32-pixel HDMI packet boundary, discard partial audio-packet state, and restart ACR measurement so old- and new-rate values cannot mix. Self-checking regressions verified exact 44.1/48 kHz cadence, deterministic fallback tones, packet-boundary switching, ACR pairs `N=6272/CTS=82500` and `N=6144/CTS=74250`, both channel-status codes, 44.1/48 kHz WAV completion, and rejection outside the supported WAV rates; all regressions passed. Gowin EDA 1.9.11.03 built the `GW5AST-LV138PG484AC1/I0` revision B target with the agreed eight-core constraint, zero setup or hold violations, worst setup slack of `+1.826 ns`, worst hold slack of `+0.246 ns`, and artifact SHA-256 `0eaeaeeb40cfbe5bfa529e566397d450509028b89cba062ab7efaa80f8eda482`. The `4466068`-byte artifact was uploaded as `cores/console138k/tang-phosphor-native-rate-20260927.bin`, and its SD readback matched CRC-32 `3456d4e2`. A deterministic six-second 44.1 kHz WAV streamed all `1058444` bytes with CRC-32 `016f404b`; diagnostics reported an active HDMI rate of `44100`, exactly `264600` samples played, zero underruns, and zero transport errors, while the user confirmed the correct left-only, right-only, then stereo sequence followed by the fallback tones. Primary HDMI ACR and IEC consumer-audio references were added to `.ai/core-reference.md`, and the required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Design and verify content-based stream identification with a bounded prefix replay buffer, then use that shared front end to introduce the first FLAC decode stage without changing the proven native-rate PCM and HDMI boundary.

#### Files Modified:

- README.md
- docs/audio-pipeline.md
- docs/debug-registers.md
- src/audio/wav_decoder.sv
- src/audio_test_source.sv
- src/debug/debug_regs.sv
- src/hdmi/audio_clock_regeneration_packet.sv
- src/hdmi/audio_sample_packet.sv
- src/hdmi/hdmi.sv
- src/hdmi/packet_picker.sv
- src/phosphor_video.sv
- src/tang_phosphor_top.sv
- tests/audio_test_source_tb.sv
- tests/hdmi_audio_rate_tb.sv
- tests/run.sh
- tests/wav_stream_player_tb.sv
- tools/generate_wav_test.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 6 COMMIT Unreleased 2026-09-27T12:14:29-07:00

#### Coming From:

Unreleased 35962e0

#### Purpose:

Establish a real-world WAV compatibility baseline with a user-supplied file before inserting content-based stream identification into the proven playback path.

#### Outcome:

The unchanged `file_example_WAV_5MG.wav` input was identified as signed 16-bit stereo PCM at 44.1 kHz with a duration of 29.98 seconds and SHA-256 `d9f83427225bd4b0e2d9045bb1a5f4809d85f5f40a6fe62972b9f19fb2391b7a`. Tang-Control uploaded all `5289194` bytes to `music/file_example_WAV_5MG.wav`, verified its SD readback with CRC-32 `31339bc5`, and streamed the same byte count and CRC through the existing hardware core. Post-stream diagnostics reported player state complete, detected and active HDMI rates of `44100`, exactly `1322253` samples played, zero FIFO underruns, no cancellation, and zero BL616 transport errors. The user reported that the entire file sounded perfect, establishing the external-file baseline for the next regression, and the required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Implement and verify a bounded content-based stream detector with byte-exact prefix replay, then repeat this external WAV test to prove the new front end preserves playback behavior before beginning FLAC decoding.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: PASS

---
