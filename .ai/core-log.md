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

## 7 COMMIT Unreleased 2026-09-27T13:15:55-07:00

#### Coming From:

Unreleased 6d106eb

#### Purpose:

Add a user-operated Tang-Control file loader for standalone WAV files and VLC-style M3U/M3U8 playlists without requiring a TAR archive.

#### Outcome:

Tang-Control branch `feature/usb-cdc-file-transfer` commit `e3aa4f9` now recognizes Phosphor core ID `0x50`, exposes it directly in the TangCore menu, filters the SD chooser to WAV/M3U/M3U8 inputs, and streams each selected track through a reusable background file-stream service with Previous, Next, and Stop controls. The bounded playlist parser resolves paths relative to the playlist, preserves duplicate entries and order, accepts VLC extended-M3U metadata, BOM and LF/CRLF input, limits playlists to 255 entries, rejects URLs, HLS, nested or non-WAV entries, and uses FPGA completion rather than `#EXTINF` duration to advance. Its deterministic regression used a byte-for-byte copy of the user's four-entry VLC fixture with SHA-256 `3d6d029b029d0d7253703e08aeaafba180cd3f719d9d48b64120d21959687297` and passed. The Console 138K BL616 firmware built successfully at `233408` bytes, was flashed only to application offset `0x40000`, and passed device SHA-256 verification against `cf0e9dfaa04ae6512e7cf184c1b477fcb599ca57fb41c1246f10a7e38e67018d`. The user confirmed that direct file and playlist selection both loaded and played correctly, then reported that opening the OSD paused playback except while the cursor moved; the cause was a continuously redrawn higher-priority menu cursor loop, and the deployed correction redraws only on selection changes and yields every 10 ms. The user confirmed continuous playback after the correction, while live diagnostics at 5 Mbps reported player state playing, a full `2048`-sample FIFO, native `44100` Hz output, zero underruns, and zero transport timeouts, CRC errors, malformed packets, or unexpected responses. Tang-Phosphor documentation now pins the proven Tang-Control revision, and the required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Insert the bounded content detector and byte-exact prefix replay stage ahead of the proven WAV decoder, then use that shared stream boundary for the first FLAC implementation while retaining the qualified Tang-Control loader and playlist behavior.

#### Files Modified:

- README.md
- docs/audio-pipeline.md
- docs/debug-registers.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 8 COMMIT Unreleased 2026-09-27T13:29:17-07:00

#### Coming From:

Unreleased b60e79c

#### Purpose:

Insert a bounded content detector with byte-exact prefix replay ahead of the proven WAV decoder while establishing the shared entry point for future FLAC decoding.

#### Outcome:

The audio front end now recognizes RIFF/WAVE from its 12-byte container prefix and native FLAC from its four-byte `fLaC` marker, replays every inspected byte under `valid/ready` backpressure, retains stream end until replay completes, and drains unknown, truncated, or recognized-but-unsupported content with explicit errors. MP3 and Ogg Vorbis format IDs are reserved without claiming detection or decode support, the debug ABI is now 1.3 with detected-format register `0x74`, and primary RIFF and IETF FLAC references were added to project memory. Self-checking regressions passed exact WAV and FLAC replay under forced stalls, short and unknown inputs, reset and cancellation, FLAC rejection, and unchanged 44.1/48 kHz WAV playback. The eight-core Gowin EDA 1.9.11.03 build for `GW5AST-LV138PG484AC1/I0` revision B had zero setup or hold violations, worst setup slack of `+1.670 ns`, worst hold slack of `+0.147 ns`, and artifact SHA-256 `c3f92701a3dcf9bce7c4dfb3203ae527c128940403bfb9abdd6a7fc1e1205efc`. The `4466068`-byte artifact was uploaded as `cores/console138k/tang-phosphor.bin`, and SD readback matched CRC-32 `4f966e46`. The user reported that the four-entry playlist ran perfectly; final diagnostics reported four completed sessions, WAV format ID `1`, player state complete, native `44100` Hz output, exactly `1322253` samples in the final track, zero underruns, no cancellations, and no transport CRC, malformed-request, or unexpected-response errors. The required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Design the bounded CD-quality FLAC subset against RFC 9639, then implement and independently verify STREAMINFO parsing, frame validation, subframe decoding, residual reconstruction, CRC handling, and delivery through the existing signed 16-bit stereo PCM boundary.

#### Files Modified:

- README.md
- build.tcl
- docs/audio-pipeline.md
- docs/debug-registers.md
- src/audio/stream_format_detector.sv
- src/audio/wav_stream_player.sv
- src/debug/debug_regs.sv
- src/tang_phosphor_top.sv
- tang_phosphor_console138k.gprj
- tests/run.sh
- tests/stream_format_detector_tb.sv
- tests/wav_stream_player_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 9 COMMIT Unreleased 2026-09-27T14:36:48-07:00

#### Coming From:

Unreleased 3380012

#### Purpose:

Implement and hardware-qualify FPGA-native CD-quality FLAC playback through the existing content detector, PCM boundary, Tang-Control loader, and VLC-style playlist workflow.

#### Outcome:

The core now decodes the RFC 9639 streamable subset for signed 16-bit stereo 44.1/48 kHz FLAC, including STREAMINFO and metadata handling, constant, verbatim, fixed 0–4, and LPC 1–12 subframes, Rice4/Rice5 and escape residuals, wasted bits, all stereo channel assignments, header CRC-8, and frame CRC-16 admission through two 4,608-sample block-RAM banks. The shared player gained timing-isolation FIFOs, content-neutral diagnostics, debug ABI 1.4, FLAC capability bit 4, and a boundary policy that permanently silences startup tones after the first stream while retaining the last valid HDMI rate across independent playlist sessions. Real libFLAC vectors, rejection and corruption cases, backpressure, WAV/FLAC integration, native cadence, HDMI metadata, transport, and the new silent-boundary policy passed the complete regression. The final eight-core Gowin EDA 1.9.11.03 build for `GW5AST-LV138PG484AC1/I0` revision B had zero setup or hold violations, worst setup slack of `+0.722 ns`, worst hold slack of `+0.143 ns`, and artifact SHA-256 `ac2531e016cffeee570abf4c3ebbfdbaf1d03055a3f74388a21603005de37254`; its `4640660`-byte upload to `cores/console138k/tang-phosphor.bin` passed controller CRC-32 `f01ae6c8` and byte-identical SD readback. Tang-Control `feature/usb-cdc-file-transfer` commit `10c5761` adds direct and playlist FLAC selection; its `233441`-byte firmware with SHA-256 `6c9eaed0a9af6a9c42e39edcc68a0d974d38b1d55f3c0d334204eb733a198302` was application-only flashed at `0x40000` and passed device SHA verification. The user confirmed perfect direct FLAC playback, a four-entry WAV playlist, and a mixed WAV/FLAC playlist with no audible gap or diagnostic tone at completion; final probes reported exact `1322253`-sample completion at 44.1 kHz, zero underruns, and zero USB drops, timeouts, CRC errors, malformed packets, or unexpected responses. The current codec scope is intentionally limited to WAV and FLAC, and the required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Define a bounded PCM-driven visualization milestone that replaces the static bring-up animation with audio-responsive behavior while preserving the hardware-qualified WAV/FLAC decoder, playlist, timing, and HDMI boundaries.

#### Files Modified:

- README.md
- build.tcl
- docs/audio-pipeline.md
- docs/debug-registers.md
- src/audio/audio_output_policy.sv
- src/audio/flac_decoder.sv
- src/audio/flac_frame_ram.sv
- src/audio/flac_subframe_decoder.sv
- src/audio/wav_stream_player.sv
- src/debug/debug_regs.sv
- src/tang_phosphor_top.sv
- tang_phosphor_console138k.gprj
- tests/audio_output_policy_tb.sv
- tests/flac_decoder_tb.sv
- tests/run.sh
- tests/wav_stream_player_tb.sv
- tools/generate_flac_test_vectors.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 10 COMMIT Unreleased 2026-09-27T14:59:24-07:00

#### Coming From:

Unreleased 7342765

#### Purpose:

Eliminate false Tang-Control upload failures when post-transfer SD verification of large audio files exceeds the generic command timeout.

#### Outcome:

Tang-Control `feature/usb-cdc-file-transfer` commit `cbbfcc8` now computes the post-upload CRC-command timeout from file size using a conservative one-MiB-per-second scan allowance plus fixed overhead while retaining a 30-second minimum. A deterministic Python regression verifies the timeout floor, scaling, and rounding, and the complete Tang-Control test runner passed. Re-uploading the previously affected `42,196,260`-byte `19 - Comfortably Numb.flac` file completed at 2.20 MiB/s and returned the full device SD reread result with matching CRC-32 `c81f5d90`, proving that the earlier reports were host patience failures rather than USB disconnects or interrupted writes. No FPGA or BL616 firmware change was required, Tang-Phosphor documentation now pins the corrected authoritative client, and the required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Run the uploaded 26-track `The Wall - Phosphor.m3u8` playlist to evaluate independent-session transitions with gap-sensitive source material, then proceed to the bounded PCM-driven waveform visualizer cycle after recording any playback findings.

#### Files Modified:

- README.md
- docs/debug-registers.md

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 11 COMMIT Unreleased 2026-09-27T19:34:27-07:00

#### Coming From:

Unreleased bccaf0f

#### Purpose:

Implement and hardware-qualify a MiSTer-Phosphor-inspired native album and playlist interface with per-track metadata, cover artwork, progress, and controller playback actions.

#### Outcome:

The FPGA now renders a native 720p album screen with a six-row playlist window, three-line album/artist/track metadata panel, exact sample-derived elapsed and total time, progress, pause state, a corrected left-to-right font path, ASCII apostrophe and grave-accent glyphs, and double-buffered text and 92x92 RGB332 artwork memories exposed through register ABI 1.6. Start pauses and resumes without consuming PCM or counting an underrun, Left/Right change playlist tracks, and X toggles the native screen while TangCore's OSD remains limited to file selection. Tang-Control `feature/usb-cdc-file-transfer` commit `983fa27` adds bounded FLAC Vorbis-comment/PICTURE and WAV `LIST/INFO` parsing, per-track precedence over playlist fallbacks, baseline-JPEG conversion through SDK TJpgDec, atomic UI uploads, FatFs reentrancy, shared-UART request/response serialization, and coordinated software/FPGA pause handling; its `249536`-byte firmware with SHA-256 `1b32ba6f5a8a70e9344649e88ab1b50a7bf6be5413204fc5b8baa646aa92e316` was application-only flashed at `0x40000` and passed device SHA verification. The release build helper ran Gowin placement options 0-3 concurrently and all four completed with zero setup or hold violations; option 3 was selected with pixel Fmax `74.489 MHz`, worst setup slack `+0.043 ns`, worst hold slack `+0.144 ns`, and artifact SHA-256 `c76ec099b26a0894e1c9c4f4490c36ed516b9bb3ca6584d72b7e5040c61c2249`. The `4796618`-byte artifact was uploaded as `cores/console138k/tang-phosphor.bin` and matched controller CRC-32 `78bf0cba`. The user confirmed correct orientation, metadata and artwork, track navigation, and stable pause/resume; live diagnostics proved the same FLAC session remained active while paused, resumed from its parked offset, retained a full 2,048-sample FIFO, and accumulated zero underruns, timeouts, CRC errors, malformed packets, or unexpected responses. All FPGA and Tang-Control regressions passed, and the required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Define and implement a bounded PCM-driven visualizer that integrates with the qualified album screen while preserving the proven WAV/FLAC playback, metadata, controller, timing, and HDMI boundaries.

#### Files Modified:

- README.md
- THIRD_PARTY.md
- build.tcl
- docs/audio-pipeline.md
- docs/debug-registers.md
- scripts/build-variants.sh
- src/audio/flac_decoder.sv
- src/audio/flac_subframe_decoder.sv
- src/audio/wav_stream_player.sv
- src/debug/debug_regs.sv
- src/phosphor_video.sv
- src/tang_phosphor_top.sv
- src/ui/phosphor_album_ui.sv
- src/ui/phosphor_time_digits.sv
- src/ui/phosphor_ui_control.sv
- tang_phosphor_console138k.gprj
- tests/phosphor_album_ui_tb.sv
- tests/phosphor_time_digits_tb.sv
- tests/phosphor_ui_control_tb.sv
- tests/run.sh
- tests/wav_stream_player_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 12 COMMIT Unreleased 2026-09-27T20:20:12-07:00

#### Coming From:

Unreleased 533a3f3

#### Purpose:

Record the Tang-Control FPGA UART receive-path update made after entry 11 and verify that the Console 138K BL616 is running exactly that firmware.

#### Outcome:

Tang-Control `feature/usb-cdc-file-transfer` commit `816aa93` raises `uart1_rx_task` to priority 5 above every SD-card task so USB CDC uploads no longer starve the 32-byte FPGA UART receive FIFO, clears the FIFO and resynchronizes the parser on overflow instead of reading misaligned frames, and adds receive health counters exposed by `status` and a new `rxstats` console and `tangctl.py` subcommand, while `26a6ff7` only documents those counters; the commit notes that some overflows remain under load and that an interrupt-driven receive path is still needed. A clean rebuild of `26a6ff7` with the cached Bouffalo SDK and T-Head toolchain reproduced the previously built `251856`-byte application image with SHA-256 `65f130067683137395b91e243f668cb9efcc8f73549ae8a6c1d68812a143f8c6`, and the complete Tang-Control test runner passed. With the BL616 in user-entered BOOT mode, `BLFlashCommand` read back `0x3D7D0` bytes from application offset `0x40000`, and the readback was byte-identical to that image, proving that the device runs Tang-Control HEAD and superseding the `983fa27` firmware recorded in entry 11. Before the readback, the running firmware answered `rxstats` over `/dev/ttyACM0` with active core `0x50`, `4570` FPGA requests and responses, zero timeouts, CRC errors, malformed packets, unexpected responses, FIFO overflows, or resync bytes, a FIFO high-water mark of `25`, and a maximum receive poll gap of `4435113` µs that far exceeds the `2.2` ms upload worst case claimed by `816aa93` and remains unexplained. Tang-Phosphor documentation now pins the authoritative client at `26a6ff7`, and the required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Characterize the `4435113` µs maximum FPGA UART receive poll gap by resetting `rxstats` and sampling it across idle, core load, upload, and playback phases, then resume the proposed timing-recovery cycle ahead of the bounded PCM-driven waveform visualizer.

#### Files Modified:

- README.md
- docs/debug-registers.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: N/A

---

## 13 COMMIT Unreleased 2026-09-27T20:23:21-07:00

#### Coming From:

Unreleased 2779790

#### Purpose:

Identify the source of the multi-second FPGA UART receive poll gap left unexplained in entry 12.

#### Outcome:

After the user returned the BL616 from BOOT mode to TangCore, `status` at `19167` ms uptime, with active core `0`, `core_running` false, and no upload or playback, already reported a `4038974` µs maximum receive poll gap with zero FIFO overflows. Tang-Control `fpga/programmer.cpp` streams the JTAG core bitstream inside `taskENTER_CRITICAL()`, which blocks the scheduler and therefore `uart1_rx_task` for the entire core load, and `fpga_rx_max_gap_us` accumulates from task start without excluding that interval. After `tangctl.py rxstats --reset`, five consecutive idle samples reported a maximum gap of `1008`–`1009` µs, consistent with the task's 1 ms poll delay. The `4435113` µs value in entry 12 and the `4038974` µs boot value are therefore attributed to scheduler-blocking FPGA core programming, during which the FPGA is being reconfigured and cannot transmit, rather than to upload starvation or data loss; this resolves the question recorded in entry 12, although the attribution was inferred from the code path and the idle baseline rather than timed directly around a core load. Upload and playback phases were not sampled in this cycle, no FPGA or firmware change was made, and the required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Before each characterization run, reset `rxstats` after the core finishes loading so upload and playback gaps are measured independently of JTAG programming, and consider a Tang-Control change that resets or excludes the receive-gap measurement across core programming; then resume the proposed timing-recovery cycle ahead of the bounded PCM-driven waveform visualizer.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 14 COMMIT Unreleased 2026-09-27T20:56:59-07:00

#### Coming From:

Unreleased e88bc3d

#### Purpose:

Recover pixel-clock timing margin without functional change by pipelining the independent critical-path families that limited entry 11 to `+0.043` ns worst setup slack.

#### Outcome:

Entry 11's four placement reports showed that the whole design shares the 74.25 MHz pixel clock and that each option moved the worst path between seven families within `+0.6` ns, so every family was pipelined in one build. The album UI now registers region classification, per-zone text coordinates, slot length, scroll, and a precomputed selected-row offset before its colour and glyph stages, and registers artwork coordinates and the 92-byte row address ahead of the artwork BSRAM with the artwork merge moved later in the existing delay line, preserving total raster latency. The debug register read multiplexer is registered, since the transport latches the address six UART bytes before sampling read data; `phosphor_ui_control` applies writes one cycle after decoding them into registered strobes; the BL616 stream receive buffer is now a synchronous-read block RAM with registered writes, a read index that returns to zero whenever the buffer is inactive, and frame bounds resolved when the length byte arrives; the per-second elapsed-time terminal count is registered; and the FLAC subframe decoder separates its wasted-bits shift from the sample range check and registers its high-fanout reset. All regressions passed, with `tests/phosphor_ui_control_tb.sv` explicitly allowing the one-cycle write latency. Uncommitted cycle-exact equivalence harnesses against the `e88bc3d` sources matched the album UI over `85409944` scanned cycles including artwork and 80 frames of scrolling, and matched every stream, debug, and UART-transmit output of `iosys_bl616` under credit-conforming randomized traffic with backpressure, mid-drain cancellation, CRC and framing errors, and extended requests; both harnesses detected deliberate one-cycle mutations. A credit-violating DATA frame received while the prior buffer drains overwrites undelivered bytes in both the old and new designs, but the corrupted values differ, which is acceptable because Tang-Control waits for each acknowledgement before sending more data. The eight-core Gowin EDA 1.9.11.03 build for `GW5AST-LV138PG484AC1/I0` revision B passed timing in all four placement options with worst setup slack `+0.005`, `+0.504`, `+1.658`, and `+0.835` ns; default option 2 was selected with pixel Fmax `84.676 MHz`, worst hold slack `+0.143` ns, the third-party TMDS encoder as its worst path, and none of the seven original families in its worst paths, while the marginal options are now limited by the FLAC decoder's main control state machine. The `4749002`-byte artifact with SHA-256 `0d1796d4e6ea9fa77f2f7180fcf522b999ae3c18798c0c696eea71ce86bf7be4` was uploaded as `cores/console138k/tang-phosphor.bin`, and its SD readback was byte-identical with CRC-32 `55aac516`. The user reported that the album screen, direct WAV and FLAC playback, mixed playlist navigation, pause and resume, and the X screen toggle all passed; post-test probes reported capabilities `0x0000000f`, magic `0x54504830`, unchanged ABI 1.6, a successful scratch write/readback restored to zero, an active 44.1 kHz FLAC session with a full `2048`-sample FIFO and zero underruns, and zero FPGA-side CRC or bad-request counts with `12682` Tang-Control requests matched by responses and no timeouts, CRC errors, malformed packets, or unexpected responses. The required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Define the bounded PCM-driven waveform visualizer for the album screen against the recovered timing margin, and pipeline the FLAC decoder's main control state machine if a later build selects a placement option where that family limits slack.

#### Files Modified:

- src/audio/flac_decoder.sv
- src/audio/flac_subframe_decoder.sv
- src/audio/wav_stream_player.sv
- src/debug/debug_regs.sv
- src/iosys/iosys_bl616.v
- src/ui/phosphor_album_ui.sv
- src/ui/phosphor_ui_control.sv
- tests/phosphor_ui_control_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 15 COMMIT Unreleased 2026-09-27T21:18:52-07:00

#### Coming From:

Unreleased fc482f8

#### Purpose:

Make album artwork appear shortly after a track starts by replacing thousands of single-register UI writes with validated block writes on the shared FPGA link.

#### Outcome:

Cover art previously appeared about 30 seconds into playback, and sooner after a pause, because Tang-Control holds the shared link until each 1 KiB stream frame is acknowledged. The FPGA ignores received bytes while transmitting, and the stream acknowledgement is unsolicited. Only one register write therefore fit between frames, which arrived every `9.8` ms at the measured `104` kB/s FLAC rate, so the `2116`-word artwork and roughly `160` text and control writes took about 22 seconds; pausing stopped the stream and freed the link. `iosys_bl616` now accepts frame type `0x12` opcode `0x04`, carrying 1 to 64 words, buffers them in a block RAM, and replays them back-to-back on the debug bus only after the CRC, version, opcode, count, length, and word alignment validate. It answers with an ordinary `0x10` response and advertises transport capability bit 4, so capabilities are now `0x0000001f`. Tang-Control `feature/usb-cdc-file-transfer` commit `3636da1` adds `fpga_debug_write_block()` under the unchanged link discipline and sends the 72-word text snapshot and the artwork as 64-word blocks when that bit is present, falling back to single-register writes otherwise. The frame encoders moved into `utils/fpga_ext_frame.h`, and a new host test checks them against independently computed CRC-16 vectors; the protocol document describes the frame. All FPGA regressions passed, and `tests/iosys_debug_tb.sv` now covers 3- and 64-word replay on consecutive cycles, rejection of bad CRC, zero or 65 words, a header/length mismatch, a misaligned address, and a wrong opcode with no bus writes and correct counters, and a block write serviced while a stream buffer is held by backpressure. An uncommitted equivalence harness against `fc482f8` showed `iosys_bl616` cycle-identical for all non-block traffic. The eight-core Gowin EDA 1.9.11.03 build for `GW5AST-LV138PG484AC1/I0` revision B passed timing in all four placement options with worst setup slack `+0.012`, `+0.110`, `+0.574`, and `+1.266` ns. Option 3 was selected with pixel Fmax `81.956 MHz` and worst hold slack `+0.153` ns; its `4841472`-byte artifact with SHA-256 `dee67024b2fe6d9effff5c1d3b58f894280d0e1abb2345efac9150bc1dd0079f` was uploaded as `cores/console138k/tang-phosphor.bin` with a byte-identical SD readback, CRC-32 `a4b5e761`. The `252608`-byte Tang-Control firmware with SHA-256 `f0630083b04de3c5ab90b57d6bc682acba4d306d041be500858f60de0cb046f5` was application-only flashed at `0x40000` and passed the flash tool's on-device SHA verification. The user reported that everything passed and that artwork appears almost instantly. Post-test probes reported capabilities `0x0000001f`, a scratch write/readback restored to zero, an active 44.1 kHz FLAC session with a full `2048`-sample FIFO and zero underruns, zero FPGA-side CRC or bad-request counts, and `387` Tang-Control requests matched by responses with no timeouts, CRC errors, malformed packets, unexpected responses, or FIFO overflows. The required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Continue playlist UI refinement as the user directs. Then define the bounded PCM-driven waveform visualizer for the album screen, and pipeline the FLAC decoder's main control state machine if slack in a later build's default placement falls below the recovered margin.

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
