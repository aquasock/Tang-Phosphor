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

## 16 COMMIT Unreleased 2026-09-27T21:52:59-07:00

#### Coming From:

Unreleased 8e7d46b

#### Purpose:

Investigate and implement BL616 Tang-Control firmware updates that do not require BOOT mode.

#### Outcome:

A read-only 4 MiB BL616 flash readback identified a GigaDevice JEDEC `c86016` part. The vendor loader occupies `0x000000`-`0x01bfff`, TangCore sits at `0x040000` and was byte-identical to the Tang-Control `3636da1` image deployed in entry 15, completing the readback that entry could not perform, and a vendor data record sits at `0x200000`. The loader is opaque and no software entry into ROM ISP exists, so the chosen approach is an in-place self-update. Tang-Control `feature/usb-cdc-file-transfer` commit `fa5f912` adds a `tangctl firmware` command and a `fwupdate` console command. They check the BL616 boot header, which has a CRC-32 at `0xfc` and a body length at `0x84` after a 4 KiB header region. The image is uploaded to SD, staged at `0x100000` with SHA-256 verification, and then written over `0x040000` sector by sector from a TCM- and ROM-only routine with interrupts masked, followed by a reset. The linked ELF's call graph was checked so that no instruction fetch reaches application flash during the commit. `status` reports the running image's offset, size, and SHA-256. The first bootstrap build refused to update because the XIP image offset is `0x41000`, not the header address, and was corrected with one additional BOOT-mode flash. Two BOOT-free updates then installed a temporary test image and restored the committed image, and each was proven by `app_sha256` after reconnecting. Both showed that the vendor loader starts the Sipeed USB debugger, `0403:6010`, after a software reset and starts TangCore only after power-on, so an update ends with one USB replug; the user accepted that. The final `260448`-byte firmware with SHA-256 `04c59dc7383ce74a07e4684fa593eaf702f6abc18b7c6a40806d49dc41147096` was installed through the finished flow without BOOT mode, and the client verified the matching `app_sha256` after the replug. A temporary `git checkout` of `usb/usb_cdc_console.cpp` discarded uncommitted console edits mid-cycle; they were reapplied, and the rebuild was byte-identical to the image then running. New host tests cover SHA-256 against FIPS 180-4 vectors and boot-header validation in both C++ and Python, and all Tang-Control tests passed. No FPGA change was made, Tang-Phosphor documentation now pins `fa5f912`, and the required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Use `tangctl.py firmware` with one USB replug for future Tang-Control updates, keeping BOOT mode as the recovery path. Continue playlist UI refinement as the user directs, then the bounded PCM-driven waveform visualizer.

#### Files Modified:

- README.md
- docs/debug-registers.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 17 COMMIT Unreleased 2026-09-27T22:35:56-07:00

#### Coming From:

Unreleased 8edeb56

#### Purpose:

Eliminate the silent gap between playlist tracks by appending each successor stream behind the playing tail of its predecessor.

#### Outcome:

The gap came from a serial handover. The player drained its whole FIFO before reporting `COMPLETE`, Tang-Control polled for that state every 10 ms, and the next `START` cleared the FIFO and decoders. The next track then sent every metadata byte, including embedded PICTURE and PADDING blocks, and needed a full CRC-validated FLAC frame and a 512-sample prefill before any audio played. The player now reports state `7` (draining) once the transport has ended a session and its final sample is queued. A `START` in that state appends: only the ingress, detector, and decoders restart, while the PCM FIFO, now enlarged from 2,048 to 16,384 samples, keeps playing the tail. The successor's stream ID, sample total, duration, and native rate become audible, and the played-sample, elapsed, and underrun counts restart, exactly when the predecessor's end-of-stream sample is presented. If the successor has not reached prefill by then, the player emits silence counted in a boundary-gap register instead of as underruns. The HDMI rate now follows the audible session rather than the decoder. Register ABI 1.7 adds core capability bit 7 and registers `0x9c` (boundaries crossed), `0xa0` (inserted silent sample periods), and `0xa4` (audible stream ID). The first critical path ran from the FIFO pop through the append decision into every player register enable. It was removed by leaving the pop out of the append decision; a `START` on the same edge as the final sample instead crosses the boundary at once and prefills the successor. A latent `wav_decoder` race was also fixed: a transport end arriving while the final decoded sample waited on a full FIFO had been reported as premature-end error 4. Tang-Control `feature/usb-cdc-file-transfer` commit `26e975b` starts the next entry on the draining state when bit 7 is present. It sends native FLAC as `fLaC`, STREAMINFO marked last, and the unchanged frames through a host-tested `flac_stream_prefix.h`. It prepares each track's text and artwork in the inactive banks and publishes them when `0xa4` reports that session. All ten FPGA regressions passed. New player cases verified sample-exact WAV-to-WAV and mid-frame-split FLAC-to-FLAC seams from the new `gapless_a44`/`gapless_b44` vectors, a late successor's counted silence, a deferred cross-rate switch, a same-edge append, and cancellation with a queued successor; all Tang-Control host tests passed. The eight-core Gowin EDA 1.9.11.03 build for `GW5AST-LV138PG484AC1/I0` revision B met timing in options 1-3; option 0 failed by `-0.038` ns in transport-buffer paths and was rejected. Option 3 was selected with worst setup slack `+1.595` ns, worst hold slack `+0.153` ns, pixel Fmax `84.226 MHz`, and 94 of 340 BSRAMs. Its `4860106`-byte artifact with SHA-256 `07cda3ac3a293b84ca63be6968ad8e7c1c7f37196b76e3dfd5e775925eeca811` was uploaded as `cores/console138k/tang-phosphor.bin` with a matching SD readback, CRC-32 `6ebad8a5`. The `261184`-byte BL616 firmware with SHA-256 `8c26d2bafdc763c1f85476ccb1083b02cea8fb5b6f297e98eb1d9a820bd99bf5` was installed with `tangctl.py firmware` and one USB replug, and `status` reported the matching `app_sha256`. The deterministic `tools/generate_gapless_test.py` splits one continuous tone at non-frame-aligned samples across five FLAC tracks and one WAV, each FLAC carrying a cover and 256 KiB of padding; it regenerated byte-identically and was uploaded to `music/gapless/`. The user reported that gapless playback worked perfectly. Post-test probes after the six-track test playlist reported state complete on 44.1 kHz FLAC with exactly `176437` samples in the final track. They also showed 5 boundaries crossed, 0 inserted silent sample periods, audible stream 6, zero underruns, ABI 1.7, core capabilities `0x000000ff`, a scratch write/readback restored to zero, and `416` Tang-Control requests matched by responses with no timeouts, CRC errors, malformed packets, unexpected responses, or receive-FIFO overflows. The required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Continue playlist UI refinement as the user directs, noting that Left/Right pressed in the roughly half-second before a gapless boundary currently act relative to the already-queued track, then define the bounded PCM-driven waveform visualizer for the album screen.

#### Files Modified:

- README.md
- docs/audio-pipeline.md
- docs/debug-registers.md
- src/audio/wav_decoder.sv
- src/audio/wav_stream_player.sv
- src/debug/debug_regs.sv
- src/tang_phosphor_top.sv
- tests/wav_stream_player_tb.sv
- tools/generate_flac_test_vectors.py
- tools/generate_gapless_test.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 18 COMMIT Unreleased 2026-09-27T23:54:55-07:00

#### Coming From:

Unreleased e62989b

#### Purpose:

Prove that the GW5AST AE350 hard processor can boot and access Tang-Phosphor fabric logic before integrating a full-speed USB host.

#### Outcome:

An isolated `build-ae350-smoke.tcl` flow now directly instantiates the hardened `AE350_SOC`, uses its required dedicated PLL for a 750 MHz A25 core and 75 MHz fabric bus, serves a four-instruction reset ROM at `0x80000000`, and exposes a CPU-written status bit through the existing TangCore UART debug transport without changing the deployment core. The Gowin EDA 1.9.11.03 Education build for `GW5AST-LV138PG484AC1/I0` revision B used the single available AE350, 1,664 logic elements, 724 registers, and 1,077 CLSs, and passed timing with 80.100 MHz fabric Fmax, `+0.849` ns worst setup slack, and `+0.275` ns worst hold slack. All ten existing FPGA regressions passed. The `4330802`-byte artifact with SHA-256 `13ff822c3f2fde6387f1e146ca4bc2c05c8c83c4b23af81bdfef28e46b26919d` was copied to `cores/console138k/tang-phosphor-ae350-smoke.bin` with matching size and CRC-32 `44d7005f` on SD readback. The user loaded it and reported `active_core: 80`, the expected low byte of diagnostic tag `0x0350` because the legacy identification response transmits only `CORE_ID[7:0]`, and `peek 0` returned `0x00000001`; that value proves the AE350 fetched and executed the reset program and completed its extended-AHB write into fabric, whereas the deployment core returns magic `0x54504830` at address zero. The primitive wiring is derived from pinned BSD-2-Clause LiteX sources, the Gowin, USB 2.0, and HID primary references are recorded, no White Rabbit source was copied, and the required `.ai` core-syntax audit passed without changing `.ai/core.md` or settled history.

#### Next Steps:

Use the hardware-proven AE350 clock, reset, reset-vector, and fabric-bus foundation to integrate one 12 Mb/s USB full-speed host controller and PHY with bounded AE350 enumeration and gamepad firmware while preserving the existing BL616-connected USB port and deployment-core behavior.

#### Files Modified:

- README.md
- THIRD_PARTY.md
- build-ae350-smoke.tcl
- scripts/build-ae350-smoke.sh
- src/ae350/ae350_pll.v
- src/ae350/ae350_smoke_top.sv
- src/ae350/ae350_soc_smoke.sv
- src/boards/console138k_ae350_smoke.cst
- src/boards/console138k_ae350_smoke.sdc
- third_party/litex/LICENSE-BSD-2-Clause

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 19 COMMIT Unreleased 2026-09-30T12:42:44-07:00

#### Coming From:

Unreleased 292ae77

#### Purpose:

Record the user's direction to target device revision C and correct the AE350 core-clock claim in entry 18 using hardware evidence from the Tang-PSX project.

#### Outcome:

A review of the sibling Tang-PSX repository, which shares this board and grew its AE350 work from Tang-Phosphor's smoke test, found two facts that affect this project. First, a user photograph recorded in Tang-PSX identifies the installed device as revision C from its `2518CA0N` package marking, Sipeed's DDR3 IP is generated for revision C, and every Tang-PSX image built for revision C ran on this board; at the user's explicit direction `.ai/core.md` now names device revision C, and all future builds target it. Second, Tang-PSX commit `c3aaf811d059` showed on hardware that the A25 takes its core clock from `PLL_R[0]` `CLKOUT1` rather than from whichever output the netlist wires to `CORE_CLK`, measuring 74.85 MHz with the configuration Tang-Phosphor still uses and at least 725 MHz after moving 750 MHz to `CLKOUT1`. Tang-Phosphor's `src/ae350/ae350_pll.v` at `292ae77` places 750 MHz on `CLKOUT0` and 75 MHz on `CLKOUT1`, so the entry 18 smoke test ran the A25 at 75 MHz rather than the recorded 750 MHz; its boot, reset-vector, and fabric-write results remain valid, and only the core-frequency claim is superseded. The Gowin timing report cannot detect this fault because it constrains the declared net. `.ai/core-reference.md` gained a board-measured AE350 core-clock record that requires the CPU clock on `CLKOUT1` and a counted-cycle hardware check of the CPU frequency after any AE350 clock change, plus a device-revision record. `build.tcl`, `build-ae350-smoke.tcl`, `tang_phosphor_console138k.gprj`, and `src/ae350/ae350_pll.v` still carry revision B and the old PLL wiring because no build was run in this cycle. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that the only `.ai/core.md` change is the user-requested revision line, validated this entry as number 19 of 100 with exactly six sections, and confirmed that no settled history was rewritten; it also noted, without editing, that the Current Log Conformance section of `.ai/core-syntax.md` still describes the active log as empty.

#### Next Steps:

Hold for the user's statement of the project goal before planning further work. Any following AE350 hardware cycle must first retarget the build files to revision C, move the CPU clock to `CLKOUT1`, and confirm the CPU frequency on hardware with a counted-cycle measurement, and it must requalify the deployment core on a revision-C build.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 20 COMMIT Unreleased 2026-09-30T13:18:26-07:00

#### Coming From:

Unreleased 72219c7

#### Purpose:

Retarget every build to device revision C, move the AE350 CPU clock to `PLL_R[0]` `CLKOUT1`, measure the CPU frequency on hardware, and requalify the deployment core on a revision-C build.

#### Outcome:

`build.tcl`, `build-ae350-smoke.tcl`, and `tang_phosphor_console138k.gprj` now target `GW5AST-138C`; the `src/pll/` wrappers were left as generated for revision B because they instantiate the same `PLL` primitive with the same parameter set as Gowin's revision-C generator output, and place-and-route accepted them. `src/ae350/ae350_pll.v` now generates the 750 MHz CPU clock on `CLKOUT1` and the 75 MHz bus clock on `CLKOUT0`. The smoke ROM grew to six instructions that report start and then repeatedly store `mcycle` to the fabric, where each value is paired with a Gray-coded count of the independent 50 MHz board oscillator; a debug write to `0x10` freezes a pair for reading at `0x04` and `0x08`, and the new `tools/ae350_clock_probe.py` derives the frequency from consecutive pairs through Tang-Control. The first revision-C builds exposed a latent defect: GowinSynthesis folded the two-stage controller synchronizers in `src/tang_phosphor_top.sv`, and the new smoke reference synchronizer, into SSRAM shift registers, which removed metastability protection and escaped the `get_regs` first-stage false paths, so all four deployment placements failed with 24 hold violations and worst setup slack between `-0.032` and `-0.801` ns. Marking every synchronizer stage `syn_srlstyle = "registers"` cleared them, and all ten FPGA regressions passed. All four eight-core deployment placements then met timing; option 1 was selected with worst setup slack `+1.151` ns, worst hold slack `+0.143` ns, pixel Fmax `81.185` MHz, and 94 of 340 BSRAMs, and its `4812490`-byte artifact with SHA-256 `ee22e3a738a4d437fe1066853901418f6286696603b96f75d558a8f7c3dc97eb` was uploaded as `cores/console138k/tang-phosphor.bin` with a matching SD readback, CRC-32 `e685308e`. The revision-C smoke image met timing with bus Fmax `80.124` MHz, worst setup slack `+0.853` ns, and worst hold slack `+0.275` ns; its `4330802`-byte artifact with SHA-256 `9835991f5a1728a2981a0f4b688577eb439fd07ac6d1e1aed867e02336115fce` was uploaded as `cores/console138k/tang-phosphor-ae350-smoke.bin` with a matching SD readback, CRC-32 `3c302d67`. On hardware the probe measured exactly `750.0000` MHz over six two-second intervals with host wall-clock agreement between `749.61` and `750.30` MHz, and the uncached ROM loop completed about 2.34 million fabric writes per second, confirming the correction recorded in entry 19. The user reported that everything in the deployment core worked, covering the album screen, direct WAV and FLAC playback, mixed and gapless playlists, controller playback actions, and both USB controller ports. Post-test probes of a session loaded about 53 seconds earlier reported magic `0x54504830`, ABI 1.7, capabilities `0x000000ff`, a scratch write/readback restored to zero, an active 44.1 kHz FLAC stream with a full `16384`-sample FIFO and zero underruns, zero FPGA-side CRC or malformed-request counts, and `126` Tang-Control requests matched by responses with no timeouts, CRC errors, malformed packets, unexpected responses, or receive-FIFO overflows. The running BL616 firmware has app SHA-256 `2efb7242cc83d2d50b7d2401e7458f115541ec3d093741d732157e26483f6b7e`, the Tang-Control `fbbddc6` image installed by Tang-PSX, so the documentation now pins `fbbddc6` as the proven client. `.ai/core-reference.md` records the measured core clock, the revision-C build rule, and the synchronizer rule. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 20 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Begin step 2 of the approved Rockbox plan: pin Rockbox as a submodule, build `lib/rbcodec` for `rv32imafdc`/`ilp32` with a project configuration header, run a bare-metal warble-style codec host under `qemu-riscv32` starting with FLAC so its output can be compared bit for bit with host warble and the proven FPGA FLAC decoder, and add an A25 cache model to estimate real-time performance for DDR3, the Tang SDRAM module, and fabric L2 options before choosing the memory for step 3.

#### Files Modified:

- README.md
- build-ae350-smoke.tcl
- build.tcl
- docs/debug-registers.md
- src/ae350/ae350_pll.v
- src/ae350/ae350_smoke_top.sv
- src/ae350/ae350_soc_smoke.sv
- src/boards/console138k_ae350_smoke.sdc
- src/tang_phosphor_top.sv
- tang_phosphor_console138k.gprj
- tools/ae350_clock_probe.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 21 COMMIT Unreleased 2026-09-30T13:59:38-07:00

#### Coming From:

Unreleased 83c6f1b

#### Purpose:

Build Rockbox's codecs for the AE350 A25 and run them through Rockbox's codec API under `qemu-riscv32`, starting with FLAC, to prove bit-exact decoding and estimate CPU load for each external-memory option before choosing the memory for step 3.

#### Outcome:

Rockbox is pinned as the shallow submodule `third_party/rockbox` at `e45936397ee3677c910c9a0c6473184e9755040c` and used unmodified. `software/rbhost` compiles `lib/rbcodec` (codecs, metadata, DSP), the codec support libraries, `lib/fixedpoint`, `lib/tlsf`, and a few firmware helpers for `rv32imafdc`/`ilp32d`, the only RV32 hard-float multilib in the Xuantie toolchain, using the standalone configuration of Rockbox's `warble` test program with project `rbcodecconfig.h`, `rbcodecplatform.h`, `autoconf.h`, `file.h`, and an `endian.h` shim in `software/rbhost/config`. Rockbox has no RISC-V target, so its prebuilt `.codec` files cannot run on the A25; each codec is instead built from source as a static RV32 ELF linked at a 1 MiB codec buffer at `0x41000000` with target ID `0x5450`, and the host's ELF loader validates magic, target ID, API version 50, and `codec_api` size before calling it, as Rockbox native players load one codec at a time. Codecs link only their libraries, Rockbox's `codeclib`, and libgcc, plus newlib's lone `setjmp.o` for Vorbis; their maps contain no other libc code, and the largest image, AAC, is 464,800 bytes. The host `rbhost.c` follows `warble.c`, keeps the DSP output at the source rate for 44.1 and 48 kHz, and runs under `qemu-riscv32` through a Linux system-call layer in `platform_qemu.c`. `make -C software/rbhost check` decodes the FPGA FLAC regression vectors and reproduced the reference PCM exactly for all five 44.1/48 kHz vectors, and a complete 274.3-second 44.1 kHz track decoded to 12,096,013 samples identical to libFLAC's output. `tools/build-qemu-cache-model.sh` builds a plugin-enabled QEMU 10.2.1 from its signature-verified tarball, `tools/build-warble-reference.sh` builds x86 warble from the same Rockbox revision, and `tools/rbhost_profile.py` encodes a 60-second excerpt of a source file with FFmpeg and checks eleven formats: FLAC, ALAC, WavPack, TTA, MP3 at 320 kbps and VBR quality 2, MP2 at 256 kbps, Vorbis quality 6, AAC at 256 kbps, WMA at 192 kbps, and AC-3 at 448 kbps. On an excerpt of the user's track with SHA-256 `479572337e15cec184560d6152de058090387b80586ba821edd5d4ec4efc1f40`, every format's RV32 raw codec output was bit-identical to x86 warble and every lossless format's 16-bit output matched the source. The A25 cache model found 14.0 to 26.1 million instructions per audio second and almost no instruction misses, so data misses from streaming buffers dominate. Estimated A25 load at 750 MHz, bracketed between 1.0 cycle per instruction without write-backs and 1.5 with a write-back per data miss, was highest for WMA at 14.0 to 26.8 percent on DDR3, 11.0 to 20.8 percent on the Tang SDRAM module with an unmeasured 425-cycle miss estimate, and 8.8 to 16.5 percent with a 128 KiB fabric L2 in front of DDR3; AAC followed at 12.8 to 23.8 percent on DDR3, Vorbis and MP3 stayed below 14.5 percent, and FLAC used 4.4 to 8.0 percent. Every memory option therefore leaves the A25 at least 73 percent idle for these codecs, and the fabric L2 changes the estimate more than DDR3 versus SDRAM. Opus was deferred at the user's direction: its RV32 output passed libopus's `opus_compare` conformance test on a 10-second excerpt with a 98.6 percent quality metric but was not bit-identical to x86 warble, which matches upstream libopus, and the cause was not isolated after optimization level, `char` signedness, uninitialized memory, floating-point contraction, and `OPUS_FAST_INT64` were excluded; both builds also report a codec error at the end of that stream. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 21 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Present the step 3 memory decision to the user: DDR3 is hardware-proven on this board through Tang-PSX, while the SDRAM module needs a new burst controller, and the estimates show that either leaves ample headroom. Then implement the chosen external memory, a low-latency SystemVerilog AE350 RAM bridge, and a program loader in a separate build, set `mstatus.FS` before running `ilp32d` code, and measure the real miss cost against the model. Revisit Opus bit-exactness when Opus is scheduled.

#### Files Modified:

- .gitmodules
- README.md
- THIRD_PARTY.md
- software/rbhost/Makefile
- software/rbhost/config/autoconf.h
- software/rbhost/config/endian.h
- software/rbhost/config/file.h
- software/rbhost/config/rbcodecconfig.h
- software/rbhost/config/rbcodecplatform.h
- software/rbhost/host/codec.ld
- software/rbhost/host/codec_loader.c
- software/rbhost/host/codec_loader.h
- software/rbhost/host/crt0_qemu.S
- software/rbhost/host/host.ld
- software/rbhost/host/memory.ld
- software/rbhost/host/platform_qemu.c
- software/rbhost/host/rbhost.c
- third_party/rockbox
- tools/build-qemu-cache-model.sh
- tools/build-warble-reference.sh
- tools/rbhost_profile.py

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 22 COMMIT Unreleased 2026-09-30T14:55:11-07:00

#### Coming From:

Unreleased 26bba68

#### Purpose:

Implement step 3 of the approved Rockbox-codec plan, the user's choice of the on-board DDR3 over the SDRAM module, as a separate AE350 build with a low-latency SystemVerilog RAM bridge and a program loader, and measure real miss cost and codec load on hardware.

#### Outcome:

The cycle was paused at the user's request while the first hardware failure was being diagnosed. `build-ae350-ddr3.tcl`, run by `scripts/build-ae350-ddr3.sh` over four placements in parallel, builds a separate image with top `src/ae350/ae350_ddr3_top.sv`: Gowin's x32 DDR3 controller and 400 MHz PLL with Tang-PSX's proven configuration (`src/ddr3`, generated locally by `scripts/gen-ddr3-ip.sh` for revision C, whose `.ipc` matched the committed reference), the Sipeed pin map in `src/boards/console138k_ae350_ddr3.cst`, and Tang-Control on the 50 MHz board clock with `CORE_ID` `0x0353`. Every AE350 bus is clocked by the controller's 100 MHz user clock, so a miss crosses no clock domain; the 750 MHz core clock still comes from `PLL_R[0]` `CLKOUT1`. `src/ae350/ae350_soc.sv` brings out the ROM, EXTS, and RAM AHB ports; `ae350_boot_rom.sv` holds the 8 KiB boot ROM built from `software/ae350/boot`, which enables both caches and `mstatus.FS`, receives `TPI1` images (Tang-PSX's format, `tools/ae350_run.py pack`) from a Tang-Control stream through `ae350_stream_loader.sv` (a port of Tang-PSX's stream loader) and `async_fifo.sv`, checks their CRC-32, runs them, and publishes state; `ae350_exts_regs.sv` holds the loader, result, byte-writable log-ring, and bridge-counter registers at `0xe8000000`, which Tang-Control reads through the handshake in `debug_read_cdc.sv`. `ae350_ram_bridge.sv` maps DDR3 at `0x40000000`, answers other RAM-port addresses with an AHB ERROR, reads one 256-bit native word per 32-byte line, serves burst continuations from a line buffer, and merges write beats into one masked native write. The first 100 MHz builds failed timing because the AE350 macro's AHB outputs arrive after about 4 ns of routing, so the bridge was redesigned to capture every transfer and decide one cycle later from registers, predicting only SEQ continuations (whose data is always lane `p_beat + 1`) so line bursts keep zero wait states; with the register block's read split over two cycles, precomputed byte enables, and `syn_maxfan` on its address, all four placements met timing and placement 1 (100 MHz user clock Fmax 114.2 MHz, SHA-256 `4c23999188270b47c62371e78960a621f0ab6ce56828f4b991fc17223c6ba6b1`) was uploaded as `cores/console138k/tang-phosphor-ae350-ddr3.bin` with verified SD readback. `tests/ae350_ram_bridge_tb.sv` (randomized pipelined AHB master with bursts, BUSY, narrow and out-of-range transfers against a stalling, variable-latency controller model; twelve seeds; three of four injected faults caught, the fourth being logically redundant) and `tests/ae350_loader_tb.sv` (stream sessions with partial words, cancels and back-to-back starts across unrelated clocks, plus register and debug reads) pass and are in `tests/run.sh`. `software/ae350/programs/ddr3check` and `memlat` (ported from Tang-PSX) and eleven codec images from `tools/rbhost_bench.py prepare` were uploaded to `ae350/` on the SD card; each codec image is rbhost with its codec and a 10-second excerpt of the step 2 source track embedded (`make -C software/rbhost bench`, `host/platform_ae350.c`), and `host/bench_qemu.c` runs the same program under QEMU, whose output matched `rbhost-qemu` byte for byte, to give reference CRCs. The cache model now runs `rbhost-qemu` on the same file so it covers `main()` only, like the hardware measurement, and estimates 2.5 to 3.9 percent (AC-3) up to 14.6 to 28.0 percent (WMA) at 750 MHz on DDR3 for these excerpts. `software/rbhost/host/host.ld` had a pre-existing error, `. = HEAP_END` inside `.heap` being section-relative so `__heap_end` was `0x84100000`; it now reserves `HEAP_END - HEAP_BASE` and `make -C software/rbhost check` still passes. On hardware the image calibrated DDR3 in 27.3 ms and the boot ROM ran and loaded `ddr3check` over the stream; walking address bits over 1 GiB, byte and halfword lanes, and 65,536 write-then-read pairs passed, but the CPU stopped early in the 64 MiB pattern pass, which is the first check to evict dirty lines by replacement, with every bridge counter frozen, no trap recorded, and eight ERROR responses of unknown origin. A 16-entry transfer trace, first-ERROR address, and bridge state word were added (debug `0x0b8`-`0x0c0` and `0x300`-`0x37c`, `tools/ae350_run.py trace`); both testbenches pass with it, and the rebuilt placement 0 met timing (Fmax 105.1 MHz, SHA-256 `0d7e817463fb698762b7990972983125d09d474edec5139bc95d62f787e36174`) but has not been uploaded. `memlat` and the codec benchmarks have not run. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 22 of 100 with exactly six sections, and confirmed that no settled history was rewritten; the changes are local and uncommitted at the user's direction.

#### Next Steps:

With the Tang at the TangCore main menu, upload `build/ae350-ddr3/place0/tang_phosphor_ae350_ddr3.bin` as `cores/console138k/tang-phosphor-ae350-ddr3.bin` (the images in `ae350/` remain valid), have the user load it, run `tools/ae350_run.py run ddr3check.tpi`, and read `tools/ae350_run.py trace`: if the bridge is stuck with HREADY low its flags identify the waiting condition, and the trace shows the eviction and fill sequence and the ERROR addresses; if the bus is idle, route the AE350 debug JTAG to header pins for the user's Pico2 debugger to halt the core and read its PC. After `ddr3check` passes, run `memlat` to measure the miss cost against Tang-PSX's 570 cycles and `tools/rbhost_bench.py run` to compare codec load and output CRCs with QEMU and the model, then record the results and commit.

#### Files Modified:

- build-ae350-ddr3.tcl
- scripts/build-ae350-ddr3.sh
- scripts/gen-ddr3-ip.sh
- software/ae350/Makefile
- software/ae350/boot/boot.c
- software/ae350/boot/boot.ld
- software/ae350/boot/start.S
- software/ae350/include/ae350.h
- software/ae350/lib/crt0.S
- software/ae350/lib/program.ld
- software/ae350/programs/ddr3check/main.c
- software/ae350/programs/memlat/main.c
- software/rbhost/Makefile
- software/rbhost/host/bench_qemu.c
- software/rbhost/host/bench_qemu_start.S
- software/rbhost/host/crt0_ae350.S
- software/rbhost/host/host.ld
- software/rbhost/host/platform_ae350.c
- src/ae350/ae350_boot_rom.sv
- src/ae350/ae350_ddr3_top.sv
- src/ae350/ae350_exts_regs.sv
- src/ae350/ae350_ram_bridge.sv
- src/ae350/ae350_soc.sv
- src/ae350/ae350_stream_loader.sv
- src/ae350/async_fifo.sv
- src/ae350/debug_read_cdc.sv
- src/boards/console138k_ae350_ddr3.cst
- src/boards/console138k_ae350_ddr3.sdc
- src/ddr3/ddr3_ip.tcl
- src/ddr3/ddr3_memory_interface.ipc
- src/ddr3/gowin_pll.mod
- tests/ae350_loader_tb.sv
- tests/ae350_ram_bridge_tb.sv
- tests/run.sh
- tools/ae350_run.py
- tools/gowin_timing_summary.py
- tools/rbhost_bench.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 23 COMMIT Unreleased 2026-09-30T16:23:21-07:00

#### Coming From:

Unreleased 26bba68

#### Purpose:

Complete the paused step-3 AE350+DDR3 cycle by diagnosing the loader hang, correcting the run harness, and recording the codec and memory benchmark results.

#### Outcome:

The paused cycle was resumed and finished. The loader hang was diagnosed as a CPU-side wedge rather than a RAM-bridge fault: while wedged the loader stays in run, the bridge is idle with HTRANS IDLE and nothing pending, and the CPU issues no bus traffic and does not trap. The wedge is deterministic per binary but layout- and timing-dependent, a Heisenbug demonstrated by `dstep`, the instrumented `ddr3check`, passing the full early-check and 64 MiB pattern suite while the original `ddr3check` hangs at the pattern start; it also hits `vorbis-q6` inside `get_metadata` before its banner, and every wedging run records four to eight bridge ERROR responses from one or two out-of-range line accesses through address zero, while an uncached out-of-range load traps as a load access fault. `tools/ae350_run.py` now detects completion with the completed-runs counter instead of polling the transient returned state, which always timed out and false-failed, and `tools/rbhost_bench.py` restarts before each codec and survives a wedged image. Running `tools/rbhost_bench.py run` against the deployed build from the resumed cycle wrote `build/rbbench/results.json`: ten of eleven codecs decode bit-identically to QEMU with loads in or near the cache model's DDR3 range, `vorbis-q6` is blocked by the wedge, `memlat`'s measurements were captured (L16K 3.1, L64K 357.1 tenths of a cycle) but its report hangs on the same wedge, and `rdinstret` reads five to fourteen percent above QEMU despite identical output, consistent with speculative-instruction counting. The user authorized committing with the wedge documented as likely transient. The core-syntax audit passed: `.ai/core.md` was unchanged and the entry conforms to the template.

#### Next Steps:

Investigate the wedge, first by making the RAM bridge return a fixed known value instead of stale data on an AHB ERROR so the silent hang becomes a visible trap that confirms the mechanism, then locate and fix the out-of-range address-zero access; re-run `vorbis-q6` and `memlat` afterward, and defer a fresh hardware acceptance test until then since the user suspects the wedge is transient.

#### Files Modified:

- tools/ae350_run.py
- tools/rbhost_bench.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 24 COMMIT Unreleased 2026-09-30T17:16:43-07:00

#### Coming From:

Unreleased 8e016af

#### Purpose:

Merge the AE350 + DDR3 subsystem into the FPGA player so a single bitstream carries both the RISC-V CPU and the HDMI/audio/UI path.

#### Outcome:

Extracted the AE350 and DDR3 logic of `ae350_ddr3_top` into a shared `ae350_subsystem` module (a 50 MHz `clk` plus a transport-domain `tclk`), instantiated it from both the standalone image and `tang_phosphor_top`, and added the DDR3 pins and the single `iosys_bl616` transport to the player top. The transport feeds the FPGA player by default; a `cpu_mode` register (player debug `0x00c0`, bit 0) routes the stream to the AE350 program loader and gates the AE350 debug view into a 1 KiB window at `0x4000-0x43ff`. The merged image builds cleanly with Gowin EDA 1.9.11.03 at placement option 4 with `ui_clk` 103.3 MHz, `clk_pixel` 76.5 MHz, `clk50` 238.7 MHz, and `clk400` 2016.1 MHz and zero setup and zero hold violations, producing `tang_phosphor_merged.bin` SHA-256 `f6531a67e12936cdd5dc8471826037974a232eed0238ad224a4ab5e7b531d4a2`; placement options 0-3 route marginally and 5-7 produce no bitstream, so `build-merged.sh` defaults to option 4. All FPGA player Verilator tests pass, and the standalone AE350 image still builds after the refactor. `tools/ae350_run.py` gained `--base` and `--cpu` so the merged image can be driven on hardware. The required core-syntax audit passed with `.ai/core.md` unchanged.

#### Next Steps:

Deploy the merged bitstream to the Tang and verify on hardware that FPGA WAV/FLAC playback is unchanged and that the AE350 boots `ddr3check` with `tools/ae350_run.py run --base 0x4000 --cpu`, then proceed to the RAM-bridge wedge fix and the CPU-to-PCM handoff.

#### Files Modified:

- build-ae350-ddr3.tcl
- build-merged.tcl
- scripts/build-merged.sh
- src/ae350/ae350_ddr3_top.sv
- src/ae350/ae350_subsystem.sv
- src/boards/console138k_ae350_ddr3.cst
- src/boards/console138k_ae350_ddr3.sdc
- src/boards/console138k_merged.cst
- src/boards/console138k_merged.sdc
- src/tang_phosphor_top.sv
- tools/ae350_run.py

#### Status:

- Build: PASS
- Deployment: NOT RUN
- User Test: NOT RUN

---

## 25 COMMIT Unreleased 2026-09-30T17:51:42-07:00

#### Coming From:

Unreleased b045b76

#### Purpose:

Fix the merged image's broken stream path so the FPGA player and the AE350 program loader both receive Tang-Control streams on hardware.

#### Outcome:

Two forward-referenced `wire x = ...` declarations were silently dropped by GowinSynthesis, leaving `player_stream_start/end/cancel/valid` and `por_sync_tclk` without drivers and therefore tied low: the player never saw a stream start or data, and the AE350 stream loader was held in permanent reset by `srst`. Both were fixed by declaring the nets before first use and driving them with `assign`, and the `EX1998` no-driver and `EX3638` redeclaration warnings are gone. On hardware the player now streams a 1,058,444-byte WAV to completion with matching CRC-32 `016f404b` and plays 264,600 samples at 44.1 kHz, and the AE350 receives a streamed image (sessions 1, bytes 1408) so `ddr3check` runs through `address ok`, `lanes ok`, and `interleave ok` before its known pattern-test wedge, while the FLAC codec bench returns cleanly with result `0x600d0000`, exit 0, and 441,000 decoded samples. The fix re-enabled logic that the buggy build had swept as dead, so every placement seed now misses timing marginally (worst about `-1 ns` on the AE350 `exts_regs` read path and the player `pcm_sample_fifo` level path); timing closure is deferred to the next cycle. The required core-syntax audit passed with `.ai/core.md` unchanged.

#### Next Steps:

Close timing on the merged image by floorplanning the AE350 fabric interface near the AE350 macro and the player's HDMI/audio path near the TMDS pads, or by pipelining the marginal `ae350_exts_regs` and `pcm_sample_fifo` paths, then re-verify on hardware.

#### Files Modified:

- src/ae350/ae350_subsystem.sv
- src/tang_phosphor_top.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 26 COMMIT Unreleased 2026-09-30T21:22:33-07:00

#### Coming From:

Unreleased 8756ffa

#### Purpose:

Close timing on the merged player + AE350 + DDR3 image by pipelining the marginal paths and constraining placement, then requalify it on hardware.

#### Outcome:

The cycle was stopped by the user before timing closed, and the work is committed as a checkpoint without deployment so the next cycle can pursue audible MP3 playback first. Entry 24's passing merged build had been missing the logic that entry 25 restored, so the complete merged design had never met timing; the hardware fixes are concentrated where the fixed AE350 macro (R0C160), the DDR3 pins (left edge), and the HDMI pads (bottom right) stretch placement across a die that is only 14 percent used. The RTL changes are cycle-equivalent unless noted: `calib_time`/`uptime` synchronizers marked `syn_srlstyle = "registers"` (GowinSynthesis had folded them into SSRAM and merged their address counter with a UART tick counter), registered debug read multiplexers and read address in `ae350_subsystem` and the top level, `ae350_exts_regs` capturing the address phase on its local `hready` with a `syn_keep` `accept` term, a two-stage write commit and a three-stage read (two and three wait states), a locally registered debug address with `debug_read_cdc` at `TARGET_LATENCY` 3, registered full/empty flags in `pcm_sample_fifo`, registered `data_cnt` comparisons in `iosys_bl616`, a registered `wready` in `async_fifo`, `syn_maxfan` on the player reset, and a registered, replicated decoder reset in `wav_stream_player` that masks every decoder and detector output the player consumes and holds `stream_ready` low for its extra cycle. The RAM bridge was split from the DDR3 controller by the new `src/ae350/ae350_ram_link.sv`, which carries line commands and read lines through source, transit, and landing registers only, with a four-entry command FIFO and credit return beside the controller; bridge state bits 13 and 14 now report link ready and link idle. `tests/ae350_loader_tb.sv` had aborted in Verilator 5.032's `VlForkSync::join` and, once running, raced the design at the clock edge, so its fork and its AHB and stream drivers were rewritten to work on falling edges; `tests/ae350_ram_bridge_tb.sv` now covers bridge and link at link depths 0, 1, and 3 and checks credit return. All fourteen regression runs pass, mutations of the register read select, the write decode, the link credits, and the write-data handshake were caught, and the loader bench does not detect a missing `hready` gate on address capture or a short `TARGET_LATENCY` because its master never pipelines and holds addresses stable. One primitive group in `src/boards/console138k_merged.cst` keeps the register-block handshake beside the macro; larger groups made Gowin's constraint reader exhaust memory, which, with the link's chained registers folded into SSRAM, was the cause of the round-6 and round-7 out-of-memory failures, and several later probe readings were contaminated by an orphaned probe process, so only their parse successes are reliable. `build-merged.tcl` enables `-replicate_resources 1`, and both parallel build scripts refuse more than four placement options after five concurrent builds exhausted the 15 GB host and crashed it. In the final round, placement 3 had `ui_clk` worst slack `-0.375` ns on one AE350 RAM-port `hready` endpoint and `clk_pixel` total negative slack `-1.048` ns over 11 endpoints led by the transport receiver-select path at `-0.882` ns; its bitstream, SHA-256 `b93879275b1f8e378dbd67d0748bad9f0d1dba1e427fa2e3d319370e04a72d89`, was not deployed. At the user's direction Vorbis and Opus are on hold. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 26 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Take the fastest route to an audible MP3 from the AE350, as the user directed: add a CPU PCM output port that carries decoded samples from `ui_clk` into the player's PCM path through an async FIFO, adapt the Rockbox host so the existing embedded-input MP3 benchmark image writes its decoded output to that port, and test it on hardware with the user's agreement on which bitstream to use given the open timing margins. Afterwards, resume timing closure, starting with a separate, slower clock for the CPU island behind the async DDR3 link and registered receiver-select and debug-address paths in the transport and player.

#### Files Modified:

- build-ae350-ddr3.tcl
- build-merged.tcl
- scripts/build-ae350-ddr3.sh
- scripts/build-merged.sh
- src/ae350/ae350_exts_regs.sv
- src/ae350/ae350_ram_bridge.sv
- src/ae350/ae350_ram_link.sv
- src/ae350/ae350_subsystem.sv
- src/ae350/async_fifo.sv
- src/audio/pcm_sample_fifo.sv
- src/audio/wav_stream_player.sv
- src/boards/console138k_merged.cst
- src/iosys/iosys_bl616.v
- src/tang_phosphor_top.sv
- tests/ae350_loader_tb.sv
- tests/ae350_ram_bridge_tb.sv
- tests/run.sh
- tools/ae350_run.py

#### Status:

- Build: FAIL
- Deployment: NOT RUN
- User Test: NOT RUN

---

## 27 COMMIT Unreleased 2026-09-30T21:46:37-07:00

#### Coming From:

Unreleased 760ee06

#### Purpose:

Prove audible MP3 playback by decoding an MP3 with Rockbox on the AE350 and playing the result through the hardware-proven FPGA player and HDMI audio path.

#### Outcome:

The user heard `09 - Underground BGM.mp3` (5,065,620 bytes, SHA-256 `9103e0e9d7aa44228f0e9125407674b836fe9483172e1ae0755723a8f60f814b`, 320 kbps 44.1 kHz stereo with an embedded PNG cover) play from the Tang and reported that it sounded perfect. The new `src/ae350/ae350_play_stream.sv` carries entries the CPU writes to `ae350_exts_regs` registers `0x090` (four bytes), `0x094` (start, end, or cancel; read bit 0 reports room), and `0x098` (one byte) through a 512-entry `async_fifo` from `ui_clk` into the transport clock and unpacks them into the player's start, end, cancel, and byte stream; writes to those registers hold the bus while the FIFO is full, so software needs no polling, and in `cpu_mode` the top level feeds the player from this stream instead of the BL616 transport. `software/rbhost` gained `BENCH_PLAY=1`, which plays the decoded WAV through the port after the benchmark decode and publishes its results first, and the README documents the procedure. The new `tests/ae350_play_stream_tb.sv` (40 randomized sessions across unrelated clocks with player backpressure) and play-register checks in `tests/ae350_loader_tb.sv` (entry encoding and a write held while the FIFO is full) pass with the rest of the regression suite, and a `qemu-riscv32` decode of the same file produced an 18,791,658-byte WAV with CRC-32 `ec1f366e`. At the user's direction a single Gowin EDA 1.9.11.03 build at placement option 3 was deployed with timing still open: zero hold violations with worst hold slack `+0.140` ns, but setup failed on 95 endpoints, with `ui_clk` at 93.1 MHz Fmax (worst `-0.746` ns on the new play-write stall term in the register block's commit enable) and `clk_pixel` at 68.8 MHz Fmax (worst `-1.075` ns on the player debug-register read multiplexer). The `5145802`-byte bitstream with SHA-256 `aa06786e32c911e05f19cdf83c496345449161825fb4f780badb94ddd9e58b3b` was uploaded as `cores/console138k/tang-phosphor-merged.bin` and the `5278644`-byte `mp3play.tpi` as `ae350/mp3play.tpi`, both with matching SD readback. After the user loaded the core, `tools/ae350_run.py --base 0x4000 --cpu run mp3play.tpi` streamed the image in 15.5 s at 333 KiB/s, and the AE350 decoded all 4,697,903 samples in 9.67 s, 7,243,148,969 cycles or about 9.1 percent of the 750 MHz core, producing output bit-identical to QEMU (18,791,658 bytes, CRC-32 `ec1f366e`), then played it in real time and returned `0x600d0000` 133.4 s after the stream began. The RAM bridge recorded 12 AHB ERROR responses during the run, the out-of-range access signature associated with the CPU wedge from entry 23, although the program completed. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 27 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Close timing on the merged image before relying on it further, starting with the play-write stall term in `ae350_exts_regs` and the player debug read multiplexer, then the CPU island's clock and the remaining AE350 RAM-port handshake. Then make playback practical, streaming files from the SD card to the AE350 and decoding while playing, extend it to the other working formats, and investigate the AHB ERROR responses behind the CPU wedge.

#### Files Modified:

- README.md
- build-ae350-ddr3.tcl
- build-merged.tcl
- software/ae350/include/ae350.h
- software/rbhost/Makefile
- software/rbhost/host/platform_ae350.c
- src/ae350/ae350_ddr3_top.sv
- src/ae350/ae350_exts_regs.sv
- src/ae350/ae350_play_stream.sv
- src/ae350/ae350_subsystem.sv
- src/tang_phosphor_top.sv
- tests/ae350_loader_tb.sv
- tests/ae350_play_stream_tb.sv
- tests/run.sh

#### Status:

- Build: FAIL
- Deployment: PASS
- User Test: PASS

---

## 28 COMMIT Unreleased 2026-09-30T22:14:08-07:00

#### Coming From:

Unreleased e6a7881

#### Purpose:

Close the merged image's remaining setup-timing failures with small RTL fixes before resorting to a separate AE350 bus clock.

#### Outcome:

Timing did not close, and at the user's direction the work is committed for an agent handoff without deployment. Three stage-1 fixes removed the paths they targeted: `ae350_exts_regs` now commits ordinary register writes on `committing` alone and gates only the bus release and FIFO push of a play-stream write on `play_ready` (the MP3 cycle's stall term had sat in every register's write enable), `iosys_bl616` registers `rx_data`/`rx_valid` after the 2/5 Mbaud receiver select, and `debug_regs` decodes reads from a registered `read_address`; a follow-up split that read decode into three registered stages (word index and range check, two 32-way halves, final select), which adds four cycles of read latency against roughly 890 cycles of transport slack and which a scratch old-versus-new Verilator comparison over 528 addresses matched except for the free-running uptime counter sampled a cycle apart. `debug_regs` still has no committed testbench; the regression suite passes, and a mutation removing the play-write stall is caught by `tests/ae350_loader_tb.sv`. Four Gowin EDA 1.9.11.03 builds at placement options 1 to 4, each run under a 13.5 GB cgroup memory cap with zero hold violations, still failed setup: option 2 came closest, with `ui_clk` at 96.9 MHz Fmax (worst `-0.320` ns on the AE350 RAM port's `DDR_HWRITE`-to-bridge-`hready` enable and `-0.048` ns on `w_play` to the register block's `hready`) and `clk_pixel` at 74.18 MHz (one endpoint at `-0.012` ns in the third-party TMDS encoder), producing undeployed bitstream SHA-256 `d3f16d957e414ac44685372587210fd6985bc4da13624819d149457407b350f7`; options 3 and 4 missed `clk_pixel` by up to `-1.094` ns inside the FLAC decoder's bit accumulator, reconstructed-sample, and state logic, and option 1 passed `ui_clk` at 112.8 MHz but missed `clk_pixel` by `-94` ns total, all in the FLAC decoder. Across about a dozen builds since entry 26 the AE350 RAM-port handshake has failed by 0.3 to 1.8 ns in nearly every placement, so further pipelining or placement constraints are unlikely to close it. For a handoff, merged builds use `systemd-run --user --scope -p MemoryMax=13.5G -p MemorySwapMax=4G env MERGED_PLACE_OPTIONS="1 2 3 4" scripts/build-merged.sh`, never more than four placement options at once, and only the single `ae350_exts_handshake` primitive group in `src/boards/console138k_merged.cst` is known to keep Gowin's constraint reader within memory. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 28 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Propose to the user the two structural fixes still needed for comfortable timing: clock the AE350 buses from their own slower clock (for example 75 MHz from the unused `PLL_R[0]` output in `src/ae350/ae350_pll.v`) with async FIFOs in place of the transit registers in `src/ae350/ae350_ram_link.sv`, which removes the single-cycle RAM-port handshake from the 100 MHz controller clock, and pipeline the FLAC decoder's bit reader and main state machine so `clk_pixel` closes independently of placement. After a build passes both clocks with zero hold violations, requalify the merged image on hardware with FPGA WAV/FLAC playback, the `mp3play.tpi` MP3 path from entry 27, and Tang-Control register reads that exercise the new `debug_regs` decode.

#### Files Modified:

- src/ae350/ae350_exts_regs.sv
- src/debug/debug_regs.sv
- src/iosys/iosys_bl616.v

#### Status:

- Build: FAIL
- Deployment: NOT RUN
- User Test: NOT RUN

---

## 29 COMMIT Unreleased 2026-10-01T12:38:39-07:00

#### Coming From:

Unreleased 30409eb

#### Purpose:

Establish the single-cable FT2232 build-flash-control loop and fix the flash-format defect that made the merged image appear unbootable.

#### Outcome:

The merged image's single-cable silence was root-caused to a flash-format defect, not timing, power, or contention: openFPGALoader shifts a raw `.bin` into SRAM but cannot START the FPGA, leaving the board unconfigured and the UART silent, while the `.fs` flash stream starts it. The deployment core answered `peek 0` as `.fs` and was silent as `.bin`, isolating the format as the sole cause. `scripts/build-merged.sh` now keeps `tang_phosphor_merged.fs` beside `.bin`, `scripts/flash-otg.sh` rejects `.bin` with a pointer to the `.fs`, and a shared direct-UART transport `tools/fpga_uart.py` (byte-compatible with Tang-Control's `fpga_debug`/`fpga_stream`) plus `tools/ae350_run.py --direct`, `scripts/mp3_single_cable.py`, and `scripts/uart_probe.py` complete the one-wire toolset. Verified over one FT2232 cable: flash the merged `.fs`, `peek 0` returns `0x54504830`, stream `mp3play.tpi`, and the AE350 decodes the MP3 to `result 0x600d0000` (44100 Hz, 4697903 samples), with the user confirming playback. The sibling Tang-Control firmware gained an interrupt-driven FPGA RX and a TX mutex in commit `9d221a8` that removed the tangcore menu's gamepad stutter. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 29 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Close the merged image's open setup timing from entry 28 so single-cable control extends to reliable video and audio; the deployment core already closes timing and demonstrates the complete loop.

#### Files Modified:

- scripts/build-merged.sh
- scripts/flash-otg.sh
- scripts/mp3_single_cable.py
- scripts/uart_probe.py
- tools/ae350_run.py
- tools/fpga_uart.py

#### Status:

- Build: N/A
- Deployment: PASS
- User Test: PASS

---

## 30 COMMIT Unreleased 2026-10-01T12:38:40-07:00

#### Coming From:

Unreleased 532e19d

#### Purpose:

Add the user-facing guide, a command-line interface for the direct-UART transport, and a Pico 2 CMSIS-DAP flash script.

#### Outcome:

`README.md` was rewritten as a user-facing guide covering the two repositories, the one-wire versus two-wire modes, the command references, and the common gotchas including the `.bin`-versus-`.fs` defect. `tools/fpga_uart.py` gained a `peek`/`poke`/`dump` command-line interface, and `scripts/flash-pico.sh` flashes over a Raspberry Pi Pico 2 running CMSIS-DAP at 2 MHz with overridable VID/PID. The Pico probe was verified against the GW5AST-138C (IDCODE `0x1081b`) and requires a 2 MHz-or-lower JTAG clock; its 64-byte bulk endpoint makes it far slower than the FT2232. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 30 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Pursue the open-source toolchain adoption: mathieufro's `gw5ast-open-toolchain` forks hold the 138C harness and shapes but not the built chipdb or `.dat` corpus, so either request that he publish the built chipdb or re-run the fuzzing campaign against the Gowin Standard tool.

#### Files Modified:

- README.md
- scripts/flash-pico.sh
- tools/fpga_uart.py

#### Status:

- Build: N/A
- Deployment: PASS
- User Test: PASS

---

## 31 COMMIT Unreleased 2026-10-01T14:10:48-07:00

#### Coming From:

Unreleased 94c0ca2

#### Purpose:

Close the merged image's open setup-timing failures by moving the AE350 buses onto the AE350 PLL's 75 MHz output through a dual-clock RAM link, and pipeline the FLAC decoder so clk_pixel stops depending on placement.

#### Outcome:

The AE350 bus, RAM bridge, register block, boot ROM, and the loader/play-stream/CDC consumers now run on the AE350 PLL's 75 MHz CLKOUT0 instead of the 100 MHz DDR3 user clock, giving the macro's AHB output-to-input round trip enough of the 13.3 ns period for the bridge and register handshakes that missed at 100 MHz; ui_clk and bus_clk now meet timing on every placement tested. ae350_ram_link is now a dual-clock link (bridge at 75 MHz, controller at 100 MHz) built from two reset-capable Gray-pointer FIFOs (async_fifo_rst) with a registered command source, so commands and read responses cross the die without combinational paths and both FIFOs clear on CPU restart; the bridge exposes rsp_ready to pop the response FIFO and the transport's restart-request decode is registered. The bus-clock constraint was added to both SDCs and the fabric time constant moved from 100 MHz to 75 MHz. On the FLAC side the subframe decoder's post-emit advance is split into STATE_ADVANCE/STATE_ADVANCE2, the main decoder's subframe bit-valid no longer re-decodes the main state, the coded-number check is split into STATE_NUMBER_APPLY, and the frame-position validity check is pre-registered in STATE_FRAME_CRC_START; all fourteen Verilator regressions pass, including the bit-exact flac_decoder_tb and wav_stream_player_tb. The merged image now closes timing at placement options 2 and 4 (clk_pixel Fmax 77.7/76.4 MHz, ui_clk 123.8/138.1 MHz, bus_clk 96.2/91.3 MHz), while options 1 and 3 remain marginally open on clk_pixel (place1 -0.887 ns in the subframe decoder's predictor_order-to-bit_field path, place3 -0.089 ns in the iosys_bl616 transport's recv_state-to-stream_response_credit path), so clk_pixel does not yet close independently of placement.

#### Next Steps:

Pipeline the subframe decoder's predictor_order-to-bit_field path and the iosys_bl616 transport path that still miss on options 1 and 3, then rebuild all four placements; once all close with zero hold violations, requalify on hardware with FPGA WAV/FLAC playback, the mp3play.tpi MP3 path, and Tang-Control debug_regs reads.

#### Files Modified:

- build-ae350-ddr3.tcl
- build-merged.tcl
- software/ae350/include/ae350.h
- src/ae350/ae350_exts_regs.sv
- src/ae350/ae350_ram_bridge.sv
- src/ae350/ae350_ram_link.sv
- src/ae350/ae350_subsystem.sv
- src/ae350/async_fifo_rst.sv
- src/audio/flac_decoder.sv
- src/audio/flac_subframe_decoder.sv
- src/boards/console138k_ae350_ddr3.sdc
- src/boards/console138k_merged.sdc
- tests/ae350_ram_bridge_tb.sv
- tests/run.sh
- tools/ae350_run.py

#### Status:

- Build: FAIL
- Deployment: NOT RUN
- User Test: NOT RUN

---

## 32 COMMIT Unreleased 2026-10-01T15:09:58-07:00

#### Coming From:

Unreleased 87f4c5d

#### Purpose:

Close out the merged-image timing issue: attempt to make clk_pixel close independently of placement, re-verify every placement seed on the committed netlist, and record the accepted deployable state.

#### Outcome:

Floorplanning was attempted and found not viable through Gowin's scripted primitive-group constraints: a hierarchy wildcard ("video/*") also matches the ELVDS_OBUF hard macro and errors CT1005, whole-block wildcards ("audio_player/*", "tangcore_io/*") exhaust the constraint reader and are killed, and even a 74-register group drove placement to 11 GB and 11 minutes against a 3.1 GB / 2-minute normal build, so the floorplan experiment was reverted with no source change kept. Re-verification of the committed netlist shows the merged image closes timing at placement option 2 (clk_pixel Fmax 77.7 MHz, ui_clk 123.8 MHz, bus_clk 96.2 MHz) and that ui_clk and bus_clk meet on every seed, while the remaining seeds still miss on placement-dependent paths: options 1 and 3 on clk_pixel (subframe and transport) and option 4 on a ui_clk path through the ram_link forward FIFO read side (cmd_en), the only domain where the two structural fixes from entry 31 leave a marginal path. The user closed the issue at this point, accepting placement option 2 as the deployable build. All fourteen Verilator regressions still pass.

#### Next Steps:

If the remaining placement sensitivity is pursued later: register the ram_link forward FIFO's cmd_en/b_issue logic so the block-RAM read output does not feed it combinationally, and/or floorplan the player's clk_pixel blocks with the interactive FloorPlanner rather than scripted GRP_LOC. Before a hardware cycle, requalify the option-2 build with FPGA WAV/FLAC playback, the mp3play.tpi MP3 path, and Tang-Control debug_regs reads.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: NOT RUN
- User Test: NOT RUN

---

## 33 COMMIT Unreleased 2026-10-01T15:17:31-07:00

#### Coming From:

Unreleased bb2d6a8

#### Purpose:

Requalify the timing-passing merged core (placement option 2) on hardware over the one-wire FT2232 path.

#### Outcome:

Flashed build/merged/place2/tang_phosphor_merged.fs with scripts/flash-otg.sh. peek 0 returned the player magic 0x54504830, ABI 0x010007 (1.7), build date 0x20260927, and capabilities 0x000000ff. scripts/mp3_single_cable.py streamed build/rbhost/bench/mp3play.tpi; the AE350 decoded the MP3 and the user confirmed HDMI audio playback, and reading the AE350 return register (0x402c with cpu_mode set) returned 0x600d0000 (44100 Hz) with loader state 0x01 (returned, one completed run). cpu_mode was cleared afterward, leaving the player in its default transport mode. All fourteen Verilator regressions remain passing.

#### Next Steps:

None for this cycle. The placement-sensitivity items from entry 32 (registering the ram_link forward-FIFO cmd_en read path, and GUI floorplanning of the clk_pixel blocks) remain optional follow-ups.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 34 COMMIT Unreleased 2026-10-01T16:03:42-07:00

#### Coming From:

Unreleased 930ec4a

#### Purpose:

Remove the FPGA-native WAV and FLAC decoders so all decode moves to the AE350, and re-measure the merged-image timing without them.

#### Outcome:

The FPGA player's WAV/FLAC decode path was removed: wav_stream_player is now a port-compatible silence stub (HDMI falls back to the diagnostic tones), the six decoder/detector/FIFO files were dropped from build-merged.tcl, and their three testbenches were dropped from tests/run.sh (the remaining eleven regressions pass). This freed about 6,000 LUTs and 69 BSRAMs (logic 14% to 10%, BSRAM 50% to 30%). Merged timing improved from one passing placement seed to three: options 1, 3, and 4 now meet timing (clk_pixel Fmax 74.6/84.1/75.3 MHz, ui_clk closing everywhere), and option 2 remains marginally open at -0.289 ns on the album-UI text path. A separate experiment pipelining that text path was correct but reshuffled placement and exposed the transport (iosys_bl616) and HDMI TMDS paths across more seeds, so it was reverted. This commits the decoder removal as the starting point for the SD-playback cycle; the raw-PCM sink that ae350_play_stream will feed replaces the stub next.

#### Next Steps:

Build the raw-PCM audio sink (fed by ae350_play_stream) in place of the stub, then implement SD-card playback: BL616 streams an SD file to the AE350, Rockbox decodes it, and the AE350 feeds the player. The album-UI text, transport, and TMDS clk_pixel paths remain marginally open and need their own pipelining for placement-independent closure.

#### Files Modified:

- build-merged.tcl
- src/audio/wav_stream_player.sv
- tests/run.sh

#### Status:

- Build: FAIL
- Deployment: NOT RUN
- User Test: NOT RUN

---

## 35 COMMIT Unreleased 2026-10-01T16:49:34-07:00

#### Coming From:

Unreleased 9fccc89

#### Purpose:

Replace the decoder-removal stub with a real raw-PCM audio sink and stream raw PCM (not WAV) from the AE350, re-enabling playback with the FPGA-native decoders gone.

#### Outcome:

src/audio/pcm_sink.sv replaces wav_stream_player as the FPGA player's audio block: it assembles the AE350 play stream's four bytes into one interleaved 16-bit stereo sample, buffers them in pcm_sample_fifo, and clocks them out on sample_tick. The sample rate now crosses with the stream: the AE350 writes it to exts register 0x09c, ae350_exts_regs carries it in the play START entry, ae350_play_stream exposes it as a rate output, and the top level feeds it to the sink, which reports it to audio_output_policy so 44.1/48 kHz both work. software/rbhost/host/platform_ae350.c play_output() now writes the rate and skips the 0x2e-byte WAV header, streaming only PCM. A new tests/pcm_sink_tb.sv checks rate capture, byte assembly, and output; all twelve regressions pass. On hardware, mp3play.tpi played the full 4,697,903-sample MP3 and a 10-second FLAC excerpt played 441,000 samples, both at 44.1 kHz with zero underruns and confirmed audible.

#### Next Steps:

Stream files from the SD card to the AE350 so nothing is baked into a .tpi: BL616 reads an SD file and feeds the AE350 (Rockbox) decode-while-playing path, replacing the embedded-input benchmark harness. Also delete the now-orphaned FPGA decoder sources and their testbenches.

#### Files Modified:

- build-merged.tcl
- software/ae350/include/ae350.h
- software/rbhost/host/platform_ae350.c
- src/ae350/ae350_exts_regs.sv
- src/ae350/ae350_play_stream.sv
- src/ae350/ae350_subsystem.sv
- src/audio/pcm_sink.sv
- src/tang_phosphor_top.sv
- tests/pcm_sink_tb.sv
- tests/run.sh

#### Status:

- Build: FAIL
- Deployment: PASS
- User Test: PASS

---

## 36 COMMIT Unreleased 2026-10-01T17:13:31-07:00

#### Coming From:

Unreleased 31441d4

#### Purpose:

Add a resident AE350 player that receives an audio file through the stream loader, so files no longer have to be baked into a .tpi.

#### Outcome:

A BENCH_STREAM=1 bench build now embeds only the codec and receives the input at runtime: platform_ae350.c gained receive_stream_file(), which reads START/DATA/END entries through the existing stream-loader registers into a 256 MiB DDR3 buffer at 0x60000000 and registers it with the file API under the fixed name "input.mp3"; ae350_main() calls it when bench_stream is set and passes that name to rbhost. scripts/play_stream.py streams the resident player .tpi, then the raw audio file, then polls for completion. On hardware the resident mpa player (213 KB) received a 241,414-byte MP3 ("ID3" first bytes), decoded it, and played all 441,000 samples at 44.1 kHz with zero underruns and confirmed audible, finishing in 15 s. This is the AE350 half of SD playback; the BL616/Tang-Control half is the remaining work.

#### Next Steps:

Implement the SD flow in the Tang-Control firmware: stream a resident player .tpi from the SD card into the AE350, then stream an SD audio file to it in cpu_mode, replacing the one-wire scripts/play_stream.py path.

#### Files Modified:

- scripts/play_stream.py
- software/rbhost/Makefile
- software/rbhost/host/platform_ae350.c

#### Status:

- Build: FAIL
- Deployment: PASS
- User Test: PASS

---

## 37 COMMIT Unreleased 2026-10-01T18:26:47-07:00

#### Coming From:

Unreleased 8ccd1cd

#### Purpose:

Implement the SD flow in the Tang-Control firmware: stream a resident player .tpi and an SD audio file to the AE350 over USB CDC, replacing the one-wire play_stream.py path.

#### Outcome:

Added the Tang-Control play and core commands (Tang-Control commit 08ac97a): play sets cpu_mode and restarts the AE350 loader, waits for the loader WAIT state at 0x4020, streams ae350/mplayer.tpi and then the audio file through fpga_file_stream, and leaves cpu_mode set so the resident player's play_output() PCM reaches the pcm_sink; core programs the FPGA over JTAG from an SD image. Two defects surfaced and were fixed. First, the controller-stability UART rework (9d221a8) had left fpga_stream_send and transaction_locked on taskENTER_CRITICAL while the menu moved to fpga_tx_lock, so menu traffic could interleave with a stream and the audio transfer aborted at about 837 KB with transport timeouts; migrating both writers to fpga_tx_lock and serializing get_core_id behind fpga_link_acquire fixed it, and underground.mp3 (5,065,620 bytes) now streams with zero cancels. Second, run_play originally cleared cpu_mode immediately after streaming, cutting the AE350 play path and leaving the player blocked on a full play FIFO; leaving cpu_mode set lets playback start unaided. On hardware the full track decoded as MP3 44.1 kHz into 4,697,903 samples and played audibly with zero underruns (firmware app_sha256 daedf8df, 264,905-byte image). No FPGA build ran this cycle; the merged place2 clk_pixel timing margin remains failing.

#### Next Steps:

Validate the remaining codecs end-to-end over SD, investigate and fix the AE350 out-of-range AHB access wedge that blocks Vorbis, resolve the merged place2 clk_pixel timing margin, and delete the orphaned FPGA decoder sources and their testbenches.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 38 COMMIT Unreleased 2026-10-01T21:07:32-07:00

#### Coming From:

Unreleased a7894c6

#### Purpose:

Add menu-driven single-file playback through the AE350 and validate every Rockbox codec end to end from the menu.

#### Outcome:

Added a universal resident player and menu routing so files play straight from the Phosphor menu. software/rbhost gained a bench-universal target that embeds all eleven Rockbox codecs (mpa, flac, wav, vorbis, opus, aac, alac, wavpack, wma, a52, tta) into one resident image (resident.tpi, 863,620 bytes), and platform_ae350.c probes the streamed input's magic bytes to name it input.<ext> so rbhost picks the codec from the extension. Tang-Control added utils/ae350_play.cpp, routed the Phosphor menu's single-file selection through it, listed every audio extension in both choosers, and pointed the Phosphor core entry at tang-phosphor-merged.bin (Tang-Control commit 741f392, Tang-Phosphor commit ebf7ef9). A 10 s sine was decoded and played from the menu in every codec except WMA: wav (440,999 samples), flac (444,240), mp2 (440,223), opus (479,688 at 48 kHz resampled to 44.1 kHz), aac (440,999), alac (440,999), wavpack (440,999), ac3 (480,768 at 48 kHz), and tta (440,999), all with zero underruns, plus the earlier full-track mp3 and a full 132 s Vorbis track; WMA silently truncated to 110,592 samples (about 2.5 s of 10 s) and Opus reports a trailing codec error despite a complete decode, and both are recorded as the two known-bad entries to fix later. This also closes the Vorbis wedge question: that load-access fault was the transport failure's error path, not the Vorbis codec, so the earlier wedge note is stale. A synthesis-only pass and the philtomson/tang-console-138k-notes checks confirmed pll_stop on the memory-clock enable, exclusive clock groups, and the single-cycle cmd_en/wr_data_en handshake are already correct, and the RAM mapping is clean (no array written twice per clock became single-port distributed RAM); the 1.9.11.03 netlist is encrypted, which blocks the notes' gate-level replay method.

#### Next Steps:

Fix the WMA truncation and the Opus trailing codec error, resolve the merged place2 clk_pixel timing margin, delete the orphaned FPGA decoder sources and their testbenches, and correct the stale Vorbis-wedge note in project memory.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 39 COMMIT Unreleased 2026-10-01T23:10:33-07:00

#### Coming From:

Unreleased d3cb94b

#### Purpose:

Deploy a timing-clean merged image that carries the PCM sink, after the deployed core was found to be a timing-failing build and the nominally clean placement predated the sink.

#### Outcome:

The cycle began by debugging the persistent-player hang the previous entry left in `software/rbhost/host/platform_ae350.c`, but that work was set aside at the user's direction once the hang was narrowed to the `run_one_track()` extraction itself: the loop form hangs deterministically at `decode_file()` entry (the first log byte never appears, there is no CPU trap, and the RAM bridge is idle with the register-block read never completing), while the single-shot body works, and it hangs identically on every bitstream tried, so it is a code or CPU-side effect rather than FPGA timing. The deployed core was then re-examined: `cores/console138k/tang-phosphor-merged.bin` on the SD, byte-identical to `tang-phosphor-play.bin` at CRC `d3bf308e` (the `place2` build), is not timing clean (`clk_pixel` setup TNS -0.973 ns), and the only timing-clean existing placement, `place1`, is a stale build that still instantiates `src/audio/wav_stream_player.sv` (the silence stub) with no `pcm_sink`, so it cannot play. A fresh merged build was run with `MERGED_PLACE_OPTIONS="1 2 3 4" scripts/build-merged.sh` from the current tree; `place3` (`clk_pixel` Fmax 80.4 MHz) and `place4` (74.8 MHz) met timing with all clocks TNS 0.000 and `pcm_sink` present, while `place1` (-1.920 ns `clk_pixel`, -0.862 ns `ui_clk`) and `place2` (-0.973 ns `clk_pixel`) failed. The timing-clean, complete `build/merged/place3/tang_phosphor_merged.bin` was uploaded as `cores/console138k/tang-phosphor-merged.bin` and `cores/console138k/tang-phosphor-play.bin` with matching SD-readback CRC, and `build/rbhost/bench/resident.tpi` (the working single-shot player, CRC `b8929e4d`) as `ae350/resident.tpi`. On hardware `place3` streamed, decoded `music/test.wav` to 441,000 samples at 44.1 kHz, and played them with the playback rate register reading `0xac44` and zero underruns; the persistent-player loop change remains deferred, and the user's audible acceptance of the deployed image was not reported before the handoff.

#### Next Steps:

Diagnose and fix the persistent-player hang in `software/rbhost/host/platform_ae350.c`, where the `run_one_track()` function extraction plus `for(;;)` loop wedges the first `decode_file()` log write while the single-shot body does not, and requalify it on the deployed `place3` image; also pin the standing deployable placement option so the SD is not left holding a timing-failing or stub variant again.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: NOT RUN

---

## 40 COMMIT Unreleased 2026-10-02T07:43:05-07:00

#### Coming From:

Unreleased afa054c

#### Purpose:

Verify on hardware over the two-wire Tang-Control path that the timing-clean merged core recorded in entry 39 accepts the extended debug protocol and plays WAV, FLAC, and MP3 audio through the AE350 PCM sink.

#### Outcome:

The `place3` merged core recorded in entry 39 was accepted on hardware over the two-wire Tang-Control CDC path. The SD image `cores/console138k/tang-phosphor-merged.bin` was downloaded and found byte-identical to `build/merged/place3/tang_phosphor_merged.bin` (SHA-256 `a4e0f726d281a2b4f5af601aeff430a318d38227760cc3d750f4f3d225b36f01`, CRC-32 `49b0072b`, `5005716` bytes), and the local placement report is timing-MET with `clk_pixel` Fmax `80.438` MHz, so the card is confirmed to hold a verified timing-clean image rather than a failing or stub variant. The core was loaded from the SD card through `tangctl.py core` in 5.8 s and answered the extended protocol: magic `0x54504830`, register ABI `0x00010007` (1.7), build date `0x20260927`, core capabilities `0x000000ff`, transport protocol 1 with transport capabilities `0x0000001f`, a scratch write of `0x12345678` read back and restored to zero, an unmapped read at `0x2c` returning `0xdeadbeef`, and zero transport CRC-error and malformed-request counts. Playback through the universal `ae350/resident.tpi` via `tangctl.py play` reached audio state 4 for every test with detected and active HDMI rate `0xac44`: `music/test.wav` presented exactly `441000` samples, `music/test.flac` presented `444240` samples, and `music/underground.mp3` presented exactly `4697903` samples. A single PCM underrun appeared during the first FLAC session and did not recur across four further sessions (a WAV replay, the MP3, another WAV replay, and a FLAC replay), so it reads as a one-off startup transient rather than a repeatable fault. The user confirmed that the WAV, FLAC, and MP3 playback all sounded good. The running BL616 firmware reports `app_sha256 deb2dfeb` at `265073` bytes, which is newer than the `daedf8df` image that entry 37 recorded, so the pinned Tang-Control client revision in project memory is now stale. No engineering file changed this cycle; `cpu_mode` was cleared to restore the default transport routing, and the loaded core remained responsive. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 40 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Characterize the single FLAC-start PCM underrun on the deployed `place3` image before dismissing it, and reconcile project memory's pinned Tang-Control client revision with the firmware actually running on the board (`app_sha256 deb2dfeb`, `265073` bytes, versus the `daedf8df` image that entry 37 recorded). Then resume the deferred persistent-player feature, which must be re-derived from the current tree because the `run_one_track()` loop named in entry 39 was never committed, and after that address the WMA truncation and the Opus trailing codec error recorded in entry 38.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: PASS
- User Test: PASS

---

## 41 COMMIT Unreleased 2026-10-02T08:42:33-07:00

#### Coming From:

Unreleased 3579c4f

#### Purpose:

Eliminate the spurious PCM FIFO underrun that the raw-PCM sink counted during a session's prefill and end-of-stream drain windows without changing the audio path.

#### Outcome:

The raw-PCM sink no longer counts an underrun until playback is genuinely underway: the one changed condition in `src/audio/pcm_sink.sv` now reads `state == ST_PLAYING && !end_seen`, excluding both the prefill interval between `stream_start` (which clears the FIFO) and the first assembled sample and the one-cycle transition from `ST_PLAYING` to `ST_DONE` after the last sample drains. The count condition had been inherited from the decoder-based `wav_stream_player` without that player's `PREFILL_LEVEL` gate, so a sample tick landing in the roughly microsecond prefill gap was counted once and then retained, because `underruns_r` resets only on core reset while `samples_played` resets at `stream_start`; a scratch Verilator testbench reproduced `underruns=1` with `samples_played=0` on the unmodified RTL and showed that the gate removes it while still counting a genuine starvation tick, and a controlled ten-session run had already failed to reproduce the artifact (`0` overruns), establishing the low event rate. `tests/pcm_sink_tb.sv` gained a startup-window case asserting that a tick before the first sample is not counted and that a starvation after playback begins still is, and all twelve Verilator regressions pass. A four-placement merged build under the memory cap produced two timing-clean seeds, `place2` at `clk_pixel` Fmax `76.753` MHz and `place3` at `76.412` MHz, while `place1` and `place4` missed setup; `place3` was uploaded as `cores/console138k/tang-phosphor-merged.bin` with SHA-256 `f708e977649dc58e1229dff77d87ddb3445a96f1140a6b0be3cd5c4326c33f34` and CRC-32 `0fb6ab7e`, byte-identical on SD readback, and loaded through `tangctl.py core` to a core reporting magic `0x54504830`, register ABI `0x00010007`, build date `0x20260927`, core capabilities `0x000000ff`, and a clean scratch write/readback. On hardware `music/test.flac` presented exactly `444240` samples, `music/test.wav` `441000`, and `music/underground.mp3` `4697903`, all at `0xac44` with `0x6c` staying zero, and a sweep of the resident player's remaining media found `music/test.mp2` `440735`, `music/test.tta` `441000`, `music/test.m4a` (ALAC) `441000`, `music/test.mp4` (AAC) `441000`, `music/test.wv` `441000`, `music/test.ac3` `480768` at `0xbb80`, and `music/kakariko-village.ogg` `5821679` all correct, while `music/test.wma` again truncated to `110592` samples exactly as entry 38 recorded and `music/test.opus` produced no audio in three attempts because the sink received no samples at all, which differs from entry 38's record of a complete Opus decode with a trailing error and was not explained in this cycle. The user reported that all of the playback sounded perfect. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 41 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Push the two pending commits for entries 40 and 41 to `origin/main`, then investigate the Opus silence, which now produces no samples where entry 38 recorded a complete decode with a trailing error, and the WMA truncation at `110592` samples. After that, resume the deferred persistent-player feature, which must still be re-derived from the current tree because the `run_one_track()` loop named in entry 39 was never committed, and pin a standing deployable placement seed, since `place1` and `place4` traded places between the entry 39 and entry 41 builds and the default option 4 currently fails timing.

#### Files Modified:

- src/audio/pcm_sink.sv
- tests/pcm_sink_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 42 COMMIT Unreleased 2026-10-02T10:19:01-07:00

#### Coming From:

Unreleased a087883

#### Purpose:

Fix the two known-bad codecs, the WMA decode truncation and the Opus total silence, so every Rockbox codec plays correctly from the resident AE350 player.

#### Outcome:

Both defects were reproduced off-target before being fixed: `qemu-riscv32` running the project's own rbhost harness produced numbers identical to the Tang, which made iteration local. Opus was never played at all, and not because of a decode failure: the AE350 log showed `Codec: Opus`, `Frequency: 48000 Hz`, `error: codec error`, `Samples: 479688`, and the program's result register read `0x600d0001`, so `software/rbhost/host/platform_ae350.c` skipped `play_output()` because it gated playback on `bench_play && exit_status == 0` while the Opus codec returns a trailing error after a complete decode; the gate now keys on samples actually produced (`output_size > 0x2e`), so a nonzero codec status no longer suppresses a good decode. WMA decoded exactly `numpackets x 2048` samples (110592 of 441000 for the test file, and the same one-frame-per-packet pattern at 5, 10 and 20 seconds, 128 and 192 kbps, mono and stereo), and an instrumented run showed the decoder consuming the entire file with no error and no early end of input, so the loss was inside libwma: `wma_decode_superframe_init` hardcoded `nb_frames = 1` whenever the bit reservoir was unused, and each ASF packet in fact carries several block-aligned frames (3200-byte packets with `block_align` 743 or 1115). `third_party/rockbox/lib/rbcodec/codecs/libwma/wmadeci.c` now derives the frame count from the packet payload and `block_align` and repositions the bit reader at each frame's `block_align` slot; forcing the bit-reservoir path instead was tried and rejected because these files carry no superframe headers. After the fix the local decode is a clean 440 Hz tone (zero-crossing rate 880/s and a steady RMS matching ffmpeg, where before the extra frames were garbage) at the correct length, and ffprobe confirmed the input was an ordinary 10 s stereo 44.1 kHz 128 kbps `wmav2` file that VLC plays correctly, whose reported 13099 ms duration is only the ASF `play_duration` including its 3100 ms preroll. Because the libwma change lives in a submodule and a superproject commit cannot capture a dirty submodule, the fix is carried as `third_party/patches/0001-libwma-frames-per-packet.patch` with an idempotent `scripts/apply-rockbox-patches.sh`, which `software/rbhost`'s Makefile now runs before compiling any Rockbox source; reverting the submodule and rebuilding was verified to re-apply the patch and keep the decode correct. The rebuilt resident player (`ae350/resident.tpi`, 863764 bytes, CRC-32 `f4709ebe`) was uploaded with a byte-identical SD readback, and on hardware `music/test.wma` presented 442368 samples at 44.1 kHz, `music/test.opus` presented 479688 samples at 48 kHz, `music/test.flac` presented 444240, and `music/test.ac3` presented 480768, all with zero underruns. The user reported that all codecs pass now. All twelve FPGA regressions and the five rbhost codec vectors pass. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 42 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Push this cycle, then decide whether to add an automated regression for the WMA path, which currently has none because `make check` covers only FLAC vectors and a WMA vector would depend on the ffmpeg version. Beyond that, the standing items are the deferred persistent-player feature that must still be re-derived from the current tree, pinning a deployable placement seed, and the debugging-capability work the user is considering for Tang-Control, where the agreed priority is a firmware-independent register plane plus sticky and per-session counters rather than deeper JTAG.

#### Files Modified:

- THIRD_PARTY.md
- scripts/apply-rockbox-patches.sh
- software/rbhost/Makefile
- software/rbhost/host/platform_ae350.c
- third_party/patches/0001-libwma-frames-per-packet.patch

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 43 COMMIT Unreleased 2026-10-02T11:06:59-07:00

#### Coming From:

Unreleased 0da404d

#### Purpose:

Verify end to end, over the two-wire link alone, that a freshly installed TangCore SD card carrying this firmware plays every supported audio format.

#### Outcome:

The card was a fresh TangCore install holding only `cores/`, and the Tang sat at its main menu with the BL616 CDC attached, so `music/` and `ae350/` were created and every artifact was transferred without a reboot or a cable change. The corpus could not be reused from the previous card because no copy exists on the host, so `test.wma` and `test.opus` were the two surviving originals while the other ten files were regenerated with ffmpeg from a 10 s 440 Hz stereo 44.1 kHz tone; the regenerated `test.flac` came out at exactly 131631 bytes, the same size as the original corpus file, which corroborates the regeneration, and all twelve were decoded locally under `qemu-riscv32` first so that the expected sample counts were known. Uploaded were the twelve files to `music/` and `build/rbhost/bench/resident.tpi` (`863764` bytes) as `ae350/resident.tpi`, each verified against its SD readback by size and CRC. The merged core was then built fresh with `MERGED_PLACE_OPTIONS="1 2 3 4"` under the memory cap: `place2` and `place3` met timing while `place1` and `place4` failed, and the bitstreams came out byte-identical to the entry 42 build, `place3` at SHA-256 `f708e977649dc58e1229dff77d87ddb3445a96f1140a6b0be3cd5c4326c33f34`, which is expected because only the AE350 software had changed. `place3` was uploaded as `cores/console138k/tang-phosphor-merged.bin` with a byte-identical readback and loaded with `tangctl.py core`, after which the core reported magic `0x54504830`, register ABI `0x00010007`, build date `0x20260927` and capabilities `0x000000ff`. The sweep then played all twelve formats in order, each reaching audio state 4 with zero underruns: `music/test.wav` presented `441000` samples, `music/test.flac` `444240`, `music/test.mp2` `440735`, `music/test.mp3` `441000`, `music/test.ogg` `441000`, `music/test.mp4` `441000`, `music/test.m4a` `441000`, `music/test.wv` `441000`, `music/test.ac3` `442368`, `music/test.tta` `441000`, `music/test.wma` `442368`, and `music/test.opus` `479688` at 48 kHz. The FLAC count is the one unexplained observation: the file nominally holds `441000` samples and `qemu-riscv32` reports `441000`, but the AE350 consistently presents `444240`, the same figure recorded in entries 38 and later, so it is not a regression from this work but an unresolved local-versus-hardware divergence. The regenerated AC-3 file plays at 44.1 kHz rather than the original corpus file's 48 kHz, which was stated incorrectly when the test was announced and is corrected here. The user reported that all twelve sounded identical and boring and that WMA and Opus, the two formats fixed in entry 42, were perfect. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 43 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Push this cycle, then investigate the FLAC local-versus-hardware sample-count divergence, where the same file decodes to `441000` samples under `qemu-riscv32` and `444240` on the AE350. Consider committing a deterministic generator for the codec test set, which the project already does for its other vectors through `tools/generate_wav_test.py`, `tools/generate_flac_test_vectors.py` and `tools/generate_gapless_test.py`, since the corpus uploaded here was regenerated ad hoc. The standing items remain the missing automated WMA regression, the deferred persistent-player feature, a pinned deployable placement seed, and the debugging-capability work the user is considering for Tang-Control.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 44 COMMIT Unreleased 2026-10-02T11:52:38-07:00

#### Coming From:

Unreleased ba153b7

#### Purpose:

Make the Phosphor core entry recognisable as an audio player and give its core image the same file-naming convention as the other TangCore cores.

#### Outcome:

Tang-Control's core-info entry for core id `0x50` now names its image `phosphortang.bin` instead of `tang-phosphor-merged.bin`, matching the `<system>tang.bin` convention already used by `nestang.bin`, `snestang.bin`, `gbatang.bin`, `mdtang.bin`, `smstang.bin` and `pctang.bin`; the display name deliberately stays `Phosphor`, because it is the project's lineage identity and upstream MiSTer-Phosphor is itself an FPGA audio player and visualizer, so taking Rockbox's name for the core was rejected as misattribution when Rockbox has no RISC-V target and this project consumes its codecs unmodified apart from the carried libwma patch. The recognisability work adds `--- Phosphor - Audio Player ---` as a single definition, `phosphor_menu_title()` declared in `core/cores.h` and defined in `core/phosphor.cpp`, used for both the PhosphorMenu header and the file chooser header. The chooser header was required because selecting Phosphor from the main menu calls `menu_loadrom` and opens the file chooser directly rather than the PhosphorMenu, so the header alone was not visible in the main flow; it is drawn on the first overlay text line, which the chooser left blank, while the TangCore logo seen below the list is drawn by the FPGA text display at a fixed pixel position rather than from the overlay character buffer. `docs/phosphor-loader.md` was also refreshed because it still described the old `cores/console138k/tang-phosphor.bin` path and a WAV-and-FLAC-only scope. The Tang-Control commits are `d531e4c` and `a500a2c`. The firmware was rebuilt to `265233` bytes and installed twice with `tangctl.py firmware`; each install leaves the BL616 in its vendor loader and requires a power-on before TangCore returns, which reconfirms entry 16, and the running image was verified as `app_sha256 baef1bab04b59625e981a5e354f467fa999904e3792f5581c44dbf8cf26c0767`. The card was migrated so that it was never unresolvable: `cores/console138k/phosphortang.bin` was uploaded before the first flash and the obsolete `tang-phosphor-merged.bin` filename was removed only after the new firmware was running, and the renamed core loads and reports magic `0x54504830`, register ABI `0x00010007` and capabilities `0x000000ff`, with a `music/test.wma` sanity play presenting `442368` samples at 44.1 kHz and zero underruns. The user confirmed that the main-menu entry still reads Phosphor, that the core image was renamed on the card, and that the audio-player header appears in both the main-menu path and the OSD pop-up. One correction is recorded: the `0403:6010` "Sipeed USB Debugger" the host sees after a reset is the BL616's vendor loader rather than a separate FTDI device, which agrees with the schematic's `USB-JTAG(BL616)` and supersedes the earlier reasoning that the supplied schematics did not match the board. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 44 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Push both repositories, since Tang-Control carries `d531e4c` and `a500a2c` and Tang-Phosphor carries this entry. Any SD card still holding `tang-phosphor-merged.bin` will no longer resolve with this firmware and needs that file renamed to `phosphortang.bin`. The standing items then remain the FLAC local-versus-hardware sample-count divergence, the missing automated WMA regression, the deferred persistent-player feature, a pinned deployable placement seed, and the debugging-capability work the user is considering for Tang-Control. The possible in-house codec corpus remains undecided and entry 43 still stands.

#### Files Modified:

None.

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 45 COMMIT Unreleased 2026-10-02T12:41:22-07:00

#### Coming From:

Unreleased f42efde

#### Purpose:

Make a community rebuild from a fresh clone reproduce this project's timing closure and artifact for the merged core.

#### Outcome:

Determinism was established first, by rebuilding placement option 3 from the current tree and comparing against the deployed artifact: the result was byte-identical at SHA-256 `f708e977649dc58e1229dff77d87ddb3445a96f1140a6b0be3cd5c4326c33f34` and `4989844` bytes with identical timing, every clock at TNS `0.000` and `clk_pixel` Fmax `76.412` MHz against the `74.25` MHz constraint, `ui_clk` `123.399`, `bus_clk` `99.469`, `clk50` `232.591`, `clk400` `2016.129` and `clk12` `94.890`. Because `scripts/build-merged.sh` rsyncs the sources into a fresh temporary tree for each run, both builds were effectively clean builds, so the recipe itself is reproducible rather than an artifact of a warm working tree. The default seed was then corrected, because `MERGED_PLACE_OPTIONS` defaulted to `4` while options 1 and 4 fail setup on this netlist and only 2 and 3 meet it, so a plain default build produced a timing-failing image; the default is now `3` with a comment explaining the pin, and the script's closing hash list prints only the options actually built instead of every stale `place*` directory left by earlier runs. The README gained a `Building from source` section that lists the requirements, the Gowin EDA and RISC-V toolchain environment variables and fallback paths, the submodule and automatically applied Rockbox patch, the locally generated DDR3 IP and the memory ceiling, the build command, the expected artifact size and SHA-256 and per-clock Fmax figures, and how to verify the result with `sha256sum` and `tools/gowin_timing_summary.py`; the quick-start example that flashed `build/merged/place4/tang_phosphor_merged.fs`, a timing-failing artifact, now names `place3`. `software/rbhost`'s Makefile no longer demands `BENCH_INPUT` for the universal player, which receives its input over the stream loader and never uses an embedded one, so the documented community build works without a dummy file; the non-streaming `bench` target still refuses without it, and this was verified by building the player with no input (`863748` bytes), by confirming the guard still fires for the non-streaming target, and by the five codec vectors continuing to pass. All twelve FPGA regressions pass. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 45 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Continue release preparation: give the core version a single source of truth instead of the hand-synced `BUILD_DATE` in `src/debug/debug_regs.sv` and the `V` field of `CONF_STR` in `src/iosys/iosys_bl616.v`, draft `docs/RELEASE_NOTES.md`, and propose the content for the `Releasing` section of `.ai/core.md`, which is still empty and must be approved by the user because `core.md` is RESTRICTED. The open release decisions remain the artifact set, the FLAC local-versus-hardware sample-count divergence, the missing automated WMA regression, and the supported-scope statement for 0.1.0.

#### Files Modified:

- README.md
- scripts/build-merged.sh
- software/rbhost/Makefile

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 46 COMMIT Unreleased 2026-10-02T15:14:19-07:00

#### Coming From:

Unreleased 1b313fe

#### Purpose:

Bring the Digilent Pmod OLEDrgb up on the Tang Console dock as a self-contained PMOD verification core so that a later module can be judged on hardware without disturbing the player.

#### Outcome:

The Pmod OLEDrgb was implemented as a standalone core that shares no logic with the player, so a PMOD fault cannot be mistaken for a playback fault. `src/oled/oled_spi.sv` is the mode-3 SPI master, deliberately not driving chip select so the caller holds it low across an entire sequence, and `src/oled/oled_pmod_top.sv` performs the power sequencing, replays the 44-byte SSD1331 initialisation list from the module's reference manual, and then cycles seven test patterns of roughly one second each; `src/boards/console138k_oled.cst` places the module on PMOD0, the socket furthest from the HDMI port, with the interleaved Sipeed IO numbering, and leaves IO4 unconstrained because the module does not connect that pin. The module seats with its ICs facing up, the same orientation as the verified PmodVGA placement, and the user confirmed that orientation on hardware. A Verilator bench added to `tests/run.sh` checks the power-up order, in which PMODEN precedes the reset release and VCCEN rises only after the command list, the 44 initialisation bytes in order, display-on following VCCEN, the per-frame address window, the first pixel bytes with D/C high, and mode-3 sampling stability with chip select low throughout; the suite now reports 13 passing tests, no failures, and exit status 0. Simulation caught three real defects before any hardware was touched: D/C was driven from a dead register, so every byte would have been sent as a command and no pixel would ever have been accepted, the nine-state sequencer was declared three bits wide, and the bench's own bit counter latched a byte after seven bits rather than eight. `scripts/build-oled.sh` built the core in about fifteen seconds for `GW5AST-138C` with setup and hold total negative slack both `0.000` and `sys_clk` Fmax `137.291` MHz against its `50` MHz constraint, the only warning being generic routing on `sys_clk`, which is benign for a single-clock design with that margin; the artifact is `build/oled/tang_phosphor_oled.bin` at `4330802` bytes with SHA-256 `1fe63b8237459ec5bf4ae2ea48ccbb67e547fcc2ae4fa5a3b77e1e60cede9c24`. The image was uploaded as `cores/console138k/oledtang.bin` with a byte-identical SD readback and loaded over the two-wire interface from the TangCore menu, and the user reported that all seven patterns appeared and that every colour matched its expected position, which verifies the RGB565 byte order, the window addressing and the full 96x64 area on real silicon. The debug protocol correctly reports no active Phosphor core while this image runs, because the bring-up core intentionally instantiates no transport registers and the panel itself is the indicator. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 46 of 100 with exactly six sections, and confirmed that no settled history was rewritten; the audit also corrected a stale closing note in `.ai/core-syntax.md` that still described the active log as empty, which would have invited a future agent to restart the entry numbering at 1. The socket numbering, the module pinout and the orientation rule were recorded in `.ai/core-reference.md` so that the remaining modules can reuse them.

#### Next Steps:

Bring up the remaining four Pmod modules the user has acquired, each as its own bring-up core on the same socket, reusing the socket numbering and orientation rule now recorded in `.ai/core-reference.md`; the user still needs to supply the module names or reference manuals, because the DigiKey part numbers listed so far could not be confirmed against Digilent's catalogue and one of them was only tentatively matched. The standing items then remain the FLAC local-versus-hardware sample-count divergence, the missing automated WMA regression, the deferred persistent-player feature, a pinned deployable placement seed, the debugging-capability work the user is considering for Tang-Control, and the deferred `0.1.0` release preparation, which stays paused while the PMOD work is in progress.

#### Files Modified:

- src/oled/oled_spi.sv
- src/oled/oled_pmod_top.sv
- src/boards/console138k_oled.cst
- src/boards/console138k_oled.sdc
- build-oled.tcl
- scripts/build-oled.sh
- tests/oled_pmod_tb.sv
- tests/run.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 47 COMMIT Unreleased 2026-10-02T16:05:36-07:00

#### Coming From:

Unreleased 9d46de5

#### Purpose:

Give the project one output-agnostic renderer and one PMOD socket layer, so that the same frame reaches every screen and bringing up a module becomes a personality rather than a fork.

#### Outcome:

The core now has a single source of truth for pixels and a boundary between rendering and presentation. `src/ui/ui_frame_store.sv` holds one 96x64 RGB565 plane doubled into two banks, with the row address multiply written as shifts because 96 is 64 plus 32; nothing else in the design stores pixels, so mirroring is structural rather than a discipline. `src/ui/ui_scanout.sv` is the whole integer upscaler: output pixel (x, y) shows source pixel ((x - X0) / K, (y - Y0) / K), computed by a pair of mod-K counters rather than a divider, with everything outside the scaled rectangle left as a bar. `src/pmod/pmod_slot.sv` converts a personality's Digilent lane order to the dock's interleaved IO numbering and applies seating orientation, and `src/pmod/pmod_io_buf.sv` isolates the tri-state, so the permutation is plain combinational logic. `src/ui/ui_swap.sv` flips banks only after every registered output has crossed a frame boundary and holds the renderer off until then, which is what makes tear-free multi-output mirroring a mechanism instead of a hope. `src/ui/ui_pattern_demo.sv` is a stand-in renderer that already meets the contract a menu renderer must meet, and it adds an eighth pattern: a test card with a border, one corner block and two diagonals, so a flipped seating or a shifted active rectangle is diagnosable at a glance. The panel protocol was extracted from the bring-up core into `src/oled/oled_panel.sv` so it exists once and takes its pixels from a port; `src/oled/oled_pmod_top.sv` is now a thin top that supplies a built-in pattern, and the original bring-up test passes unchanged against the extracted engine, which is what proves the extraction faithful. Personality and orientation are module parameters on `src/pmod_mirror_top.sv`: the seam a transport register will drive once `/tang.ini` selects them at run time. Simulation caught two real defects before hardware, both of which would have looked like a broken panel: the mapper's registered counters describe the coordinate presented one pixel earlier, so a mapping computed for the next pixel is right only for a dense raster and shifted every pixel by one source column on the paced panel, and the engine launched each byte one clock after advancing its coordinate, which is one clock short of the mapper plus the store's registered read, so every pixel would have carried the previous pixel's colour; the engine now waits two clocks between pixels. A further three failures were the testbench's own, not the RTL's: stimulus driven with blocking assignments at the same instant as the clock edge silently lost the store's first write and the swap pulse, and the socket read path could not be exercised through an inout wire, which is why the tri-state now lives in its own module. The suite reports 17 passing tests and no failures, of which the mapper is checked against an independently written model over 1407744 coordinates at K equal to 1, 8 and 11, and the panel model decodes the SSD1331 pins out of PMOD0's raw socket pins so a wrong interleave or orientation fails in simulation rather than on a bench. `scripts/build-pmod.sh` built the core in sixteen seconds for `GW5AST-138C` with setup and hold total negative slack both 0.000 and `sys_clk` Fmax 120.486 MHz against its 50 MHz constraint, producing `build/pmod/tang_phosphor_pmod.bin` at 4460544 bytes with SHA-256 `756dc1a6c7485e2163b2cd9383f92a894edbed23aab991e4c96b7d90f475ad82`. The image was uploaded as `cores/console138k/pmodtang.bin` with a byte-identical SD readback and loaded over the two-wire interface, and the user reported that every pattern passes, including the new orientation card, which confirms the store, the mapper, the bank swap and the interleaved socket mapping on real silicon with the panel that was already trusted. The user also settled the configuration design for this work: a flat-key `/tang.ini` at the SD-card root naming the module and seating orientation per socket, with an absent file leaving both sockets released as the safe state, and the parser belonging to Tang-Control while the personality registry belongs beside the RTL. The Tang Mega NEO Dock schematics supplied as board documentation were found not to describe this dock at all, since their PMOD nets sit on balls shared with SDRAM1 and the camera port and match neither verified socket, so pin assignments continue to come from the hardware-verified record and that discrepancy is now recorded rather than left to be rediscovered. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 47 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The next backend is HDMI at K equal to 11, giving 1056x704 inside 1280x720, and it is the first build where mirroring claims anything because it is the first with two screens. It should land together with the check that makes this architecture worth having: a per-output CRC over the emitted pixel stream plus a `tools/ui_mirror_check.py` that computes the expected scaled raster independently and compares, so all outputs can be proven to agree with nothing plugged in, which is the only method available when the PmodVGA needs both sockets and therefore cannot be attached alongside the OLED. After that the VGA backend at K equal to 8, then the remaining modules as personalities, and only then the fold into the player, where the 720p-native `phosphor_album_ui.sv` gives way to a menu renderer writing this store. The open design decision carried forward is that a dense raster must delay its own coordinate by one pixel to match the mapper's registered mapping, which the HDMI backend must honour.

#### Files Modified:

- src/boards/console138k_pmod.cst
- src/boards/console138k_pmod.sdc
- src/oled/oled_panel.sv
- src/oled/oled_pmod_top.sv
- src/pmod/pmod_io_buf.sv
- src/pmod/pmod_oledrgb.sv
- src/pmod/pmod_slot.sv
- src/pmod_mirror_top.sv
- src/ui/ui_frame_store.sv
- src/ui/ui_pattern_demo.sv
- src/ui/ui_scanout.sv
- src/ui/ui_swap.sv
- build-pmod.tcl
- scripts/build-pmod.sh
- tests/ui_mirror_tb.sv
- tests/run.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 48 COMMIT Unreleased 2026-10-02T16:26:26-07:00

#### Coming From:

Unreleased 92d4746

#### Purpose:

Put the same frame on the HDMI output as on the panel, and make the composition of the scaled image on the second screen a checked property rather than something judged by eye.

#### Outcome:

The renderer now drives two presentation backends, and the second one was added as a backend and a constraint file rather than a second copy of the image. `src/video/ui_hdmi_scan.sv` scales 96x64 by 11 into 1056x704 and centres it at (112, 8) inside 1280x720 with the rest black; `src/video/ui_hdmi_backend.sv` wraps the project's existing Sameer Puri derived transmitter and owns nothing but its scan mapper and the bank latch. `pmod_mirror_top.sv` was split into a top that holds only the PLL chain, the reset and the differential output buffers and a `src/pmod_mirror_core.sv` that takes its clocks as inputs, which is what makes the logic simulatable at all: the vendor PLL and ELVDS_OBUF primitives cannot be elaborated by the project's simulator, and the same split had already been applied to the panel protocol. Every backend, both frame-store read ports, the renderer and the HDMI transmitter now run on clk_pixel, so the design contains no clock-domain crossing anywhere and the bank swap needs no handshake. The cycle's real finding is that the latency between a coordinate and its pixel is not one number: horizontally the coordinate changes every clock, so the mapper's registered mapping is one pixel behind and the store's registered read adds another, while vertically the coordinate changes once per line, so the mapper's register is already aligned with the line it belongs to and the store returns that line's pixel, requiring no correction at all; a single shared constant shifted the whole image up by one source row, and the two constants are now separate and documented. The bar decision was likewise corrected to be taken combinationally from the coordinate the transmitter presents, since the colour presented must belong to that coordinate and only the pixel needs compensating. Each backend also latches its read bank at its own frame boundary, because the swap controller flips the shared bank when the last registered output has crossed a frame, which need not be that backend; the cost is one frame of latency on an update and the benefit is that no output can have its bank change part way through a frame. The HDMI audio path reuses the project's deterministic `audio_test_source` so its packet machinery stays exercised. `tests/ui_hdmi_scan_tb.sv` checks the composition against an independently written model over all 921600 pixels of a frame, 178176 of which must be bars, and reports the image landing at (112, 8) at 11x; the suite now reports 18 passing tests and no failures. The third-party transmitter cannot be elaborated by the simulator because it assigns to some signals both blocking and non-blocking, so the integration test builds the core with `HDMI_BACKEND` clear and covers the OLED and socket paths, while the composition has its own test that needs no transmitter; that split is deliberate and is stated in both files. `scripts/build-pmod.sh` built the core in twenty-six seconds for `GW5AST-138C` with setup and hold total negative slack both 0.000 and `clk_pixel` Fmax 79.133 MHz against its 74.250 MHz constraint, a margin of only 6.6 percent where the same core measured 86.732 MHz before HDMI, which is recorded as a watch item rather than a defect since the constraint is met, and producing `build/pmod/tang_phosphor_pmod.bin` at 4571648 bytes with SHA-256 `e3f47c12d546200c01d0676eb85aba5a21e690f4399b674cece6ab5989cd5c7f`. The image was uploaded as `cores/console138k/pmodtang.bin` with a byte-identical SD readback and loaded over the two-wire interface, and the user reported that both screens look perfect, which confirms the shared store, the second scan mapper, the two-axis latency rule and the per-backend bank latch with two outputs live at once for the first time. The checker that the previous entry's next steps called for was deliberately deferred to its own cycle rather than landed here, because its expected values depend on this backend's geometry and debugging the two together would conflate whether the backend is right with whether the checker is right. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 48 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The next cycle is the mirror checker, which is what makes this architecture provable rather than merely visible: a per-output CRC32 over the emitted pixel stream with a frame counter and an epoch, the BL616 debug transport added to this core so those registers can be read, a new core id so Tang-Control can tell this image from the player, the personality and orientation parameters driven by those registers so `/tang.ini` becomes live, and `tools/ui_mirror_check.py` to compute the expected raster independently and compare. It matters because the PmodVGA needs both sockets and therefore can never share the bench with the OLED, so three outputs can never be confirmed by looking. After that the VGA backend at K equal to 8, then the remaining modules as personalities, then the fold into the player. The watch items carried forward are the 6.6 percent `clk_pixel` margin, which a third backend may consume, and the two-axis latency rule, which any dense-raster backend must honour.

#### Files Modified:

- src/boards/console138k_pmod.cst
- src/boards/console138k_pmod.sdc
- src/oled/oled_panel.sv
- src/pmod/pmod_oledrgb.sv
- src/pmod_mirror_core.sv
- src/pmod_mirror_top.sv
- src/video/ui_hdmi_backend.sv
- src/video/ui_hdmi_scan.sv
- build-pmod.tcl
- tests/ui_hdmi_scan_tb.sv
- tests/ui_mirror_tb.sv
- tests/run.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 49 COMMIT Unreleased 2026-10-02T16:46:16-07:00

#### Coming From:

Unreleased 7a236dd

#### Purpose:

Add the PmodVGA as a third presentation backend and find out whether the timing margin survives it, since the margin recorded at two backends looked like it might not.

#### Outcome:

The VGA backend does not generate a raster of its own; it observes the one the HDMI transmitter already produces and derives syncs and colour from it, which is how Tang-PSX drives its VGA output. That was a deliberate choice over a true 800x600 mode, because 800x600 at 60 Hz needs a 40 MHz pixel clock and 74.25 divided by 40 is not a rational-integer ratio, so it cannot be produced by a clock enable from clk_pixel and would force a real second clock domain with an asynchronous FIFO and a duplicated store through a design whose single clock is precisely why its bank swap and per-backend bank latch are trivial. `src/video/ui_vga_backend.sv` therefore takes the transmitter's raster and colour and derives the syncs from the CEA-861 VIC 4 windows -- 40-pixel horizontal sync after a 110-pixel front porch, 5-line vertical sync after a 5-line front porch, both positive polarity -- with the top four bits of each channel feeding the module's resistor ladder. `src/pmod/pmod_vga.sv` is the dual-socket personality: J1 carries red on pins 1-4 and blue on pins 7-10, J2 carries green on pins 1-4 with horizontal and vertical sync on pins 7 and 8 and two unconnected pins. Which socket carries J1 is the personality choice and upside-down seating is the same `flipped` bit every other module uses, so Tang-PSX's two placement mode bits become declarations rather than mode bits. The first VGA build exposed a trap worth recording: it produced a bitstream byte-identical to the OLED build, because with no socket selecting the VGA personality the entire backend was dead logic and the synthesiser removed it, so a build that merely contains VGA code is not a build that has VGA in it. The variant therefore selects the personalities for real, through `src/pmod_vga_top.sv` with J1 on PMOD1 and J2 on PMOD0, matching Tang-PSX's verified default. That top is a sibling of `pmod_mirror_top` rather than a wrapper around it, because wrapping puts the PLL outputs one level down and this tool version cannot name hierarchical nets from the SDC and does not support patterns in `get_nets`, which was established by two failed builds rather than assumed; each variant now owns an identical twenty-line clock block and both keep the same root-level net names. `scripts/build-pmod.sh` gained the variant argument and builds either configuration. The timing answer is the point of the exercise: the OLED variant measures `clk_pixel` Fmax 79.133 MHz and the VGA variant, with all three backends live, measures 78.946 MHz, a difference of 0.187 MHz or 0.24 percent, both meeting the 74.250 MHz constraint. The margin is therefore not held by the presentation backends at all, and a fourth backend would very likely also fit, which retires a watch item the previous entry carried. The suite reports 18 passing tests and no failures. The image was uploaded to `cores/console138k/vgatang.bin` with a byte-identical SD readback and loaded over the two-wire interface, and the user reported that HDMI and VGA are identical, the first time this bench has run a 720p60 raster over the PmodVGA port. One gap is recorded rather than glossed: the VGA backend still has no simulation test, so its sync windows and lane mapping were verified on hardware before they were verified in simulation, which is the reverse of this project's usual order and is the next thing to fix. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 49 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The next cycle is the mirror checker, which remains what makes this architecture provable rather than merely visible and which is now overdue: a per-output CRC32 over the emitted pixel stream with a frame counter and an epoch, the BL616 debug transport added to this core so those registers can be read, a distinct core id, the personality and orientation parameters driven by those registers so `/tang.ini` becomes live and the two configurations stop needing separate tops, and `tools/ui_mirror_check.py` to compute the expected raster independently and compare. A simulation test for the VGA backend folds into that cycle, so the sync windows and lane mapping are covered before anything else is built on them. After that the remaining PMOD modules as personalities, then the fold into the player. The watch item remaining is the 6.4 percent `clk_pixel` margin, now known not to be consumed by presentation backends.

#### Files Modified:

- build-pmod.tcl
- build-pmod-vga.tcl
- scripts/build-pmod.sh
- src/boards/console138k_pmod.sdc
- src/pmod/pmod_vga.sv
- src/pmod_mirror_core.sv
- src/pmod_vga_top.sv
- src/video/ui_hdmi_backend.sv
- src/video/ui_vga_backend.sv
- tests/run.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 50 COMMIT Unreleased 2026-10-02T16:56:58-07:00

#### Coming From:

Unreleased f695e04

#### Purpose:

Give the socket bring-up core the BL616 debug transport so that its state can be read out, and turn the socket personalities and seating orientation from build-time parameters into declarations the host sends.

#### Outcome:

The transport is the same `iosys_bl616` the player uses, so the project's existing host tools reach this core unchanged; the OSD, controller, ROM-loading and stream interfaces are tied off because this core has no OSD and plays nothing, and only the debug bus matters. The core id is the player's `0x50`, not a new one, because the host firmware gates the extended debug protocol on that id and `0x51` is already Tang-PSX's; a dedicated id belongs with the `/tang.ini` parser, which is a firmware rebuild and reflash rather than a host change, and is recorded as such rather than half-done. `src/debug/ui_debug_regs.sv` is this core's register bank, deliberately separate from the player's because sharing one bank would couple two unrelated register sets; it exposes magic, build date, uptime, render frames, the current pattern, the source bank, the declared socket configuration and per-output frame counters, and it accepts a write that sets both personalities, both orientations and a renderer hold bit. Writing that register is what turns `/tang.ini` from a document into a mechanism, and it collapsed the two build variants into one artifact: `src/pmod_vga_top.sv` and its build script are deleted because configuration B is now a host write rather than a second bitstream. The hold bit freezes the pattern so a host can compare checksums against a frame it can predict, which is the precondition for any automated mirror check. Two implementation constraints were found rather than assumed. First, a bit-serial CRC32 is sixteen gates deep per input bit and cannot close at 74.25 MHz with one pixel per clock, so the checksum half of the checker needs either a parallel sixteen-bit update or per-domain pacing, and it was deliberately deferred rather than guessed at. Second, the transport instantiates a vendor block-RAM primitive that this project's simulator cannot elaborate, so the core gained a `TRANSPORT` parameter mirroring the existing `HDMI_BACKEND` escape hatch and the integration test builds without it. Build and timing improved rather than degraded: `clk_pixel` Fmax is 89.340 MHz against the 74.250 MHz constraint, up from 79.133, because the parameterized personality multiplexer is gone, and the 6.6 percent margin carried as a watch item since entry 48 is closed. The suite reports 18 passing tests and no failures. The image was uploaded as `cores/console138k/pmodtang.bin` and loaded over the two-wire interface; `status` reports `active_core` 80, `caps` reports protocol 1 with capabilities `0x0000001f`, and `peek 0` returns `0x54504830`, so the transport is confirmed live. The user-visible test was the mechanism itself: the core powers up as the panel configuration, the host read `0x12` from the control register, wrote `0x230` to select the VGA on both sockets, read back `0x234` with the live pattern field in the low bits, and the user reported that the picture was the same as the previous run, which had been produced by a separate build-time variant. Counters were confirmed alongside it, reading uptime `0x3660efe9`, thirteen rendered frames and 799 transmitter frames. One qualification is recorded: the user's visual pass was on the image built immediately before a generate wrapper was added around the transport to let the simulation test exclude it, and that wrapper changes hierarchy but not behaviour; the artifact committed here is the wrapped build at SHA-256 `3c59fac2ebb5aefd2aa915eb158d8f811c3ae1e7db57b95dcc6b9a4b4b5db8db`, and the card still carries the pre-wrapper image because writing the card requires the main menu. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 50 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The next cycle finishes the checker: the per-output checksum over the emitted pixel stream and a checksum over the source frame, using a parallel update or per-domain pacing as the throughput constraint dictates, then `tools/ui_mirror_check.py` to compute the expected rasters independently and compare against the registers this cycle made readable. A simulation test for the VGA backend, still outstanding since entry 49, folds into that cycle. The socket configuration also needs its `/tang.ini` parser in Tang-Control, which is when the core should get its own id, since that is a firmware rebuild and reflash. After the checker, the remaining PMOD modules as personalities, then the fold into the player.

#### Files Modified:

- build-pmod-vga.tcl
- build-pmod.tcl
- scripts/build-pmod.sh
- src/boards/console138k_pmod.cst
- src/debug/ui_debug_regs.sv
- src/pmod_mirror_core.sv
- src/pmod_mirror_top.sv
- src/pmod_vga_top.sv
- src/ui/ui_pattern_demo.sv
- tests/run.sh
- tests/ui_mirror_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 51 COMMIT Unreleased 2026-10-02T17:42:47-07:00

#### Coming From:

Unreleased e9093e1

#### Purpose:

Build the mirror checker the architecture has been promising, so that agreement between the outputs becomes a measured verdict rather than something the user has to look at.

#### Outcome:

Two per-frame signatures now cover the two streams that can genuinely disagree. `src/ui/ui_checksum.sv` folds a stream with `signature = signature * 5 + pixel`, a rolling hash rather than a CRC, and the file records why: a bit-serial CRC32 is sixteen gates deep per input bit and cannot close at 74.25 MHz with one pixel per clock, and the tabular and parallel-matrix forms are 8 KiB of LUT or a hand-derived XOR network needing its own proof. One instance covers the frame as the renderer writes it and one covers what the transmitter puts on the wire, blanking excluded. The first version cost 531 LUT/ALU, 256 registers and 30 percent of the clock; the culprit was a 32-bit pixel counter and its publish multiplexer, and removing it halved the logic and bought back 10.6 MHz, because the pixel count is a property of the frame the host models anyway. Each boundary is wired to a cycle carrying no pixel, the source one cycle after the write and the transmitter's the cycle after the last visible pixel, so a published pair is always a whole frame. `tools/ui_mirror_check.py` computes both signatures in Python from the pattern definition and the scaling geometry, sets the renderer hold so it compares settled frames, reads the registers over the transport, and restores the hold state it found. It reports three verdicts. Mirror compares each stream against the model. Liveness requires the frame counters to advance, and exists because a frozen frame is a legitimately mirrored state, so mirror alone cannot detect a stopped renderer. Held reports that the renderer is frozen on purpose, and its detection is observational rather than a register read, which mattered immediately: the tool's first run found that the control register writes hold at bit 0 and reads it back at bit 3, and a tool trusting that bit had read a pattern bit as held. That layout mismatch is fixed. Two false alarms are recorded deliberately rather than quietly repaired, because together they are the argument for the tool existing: the author froze the renderer with his own hold bit, forgot, and spent an hour hunting a defect that did not exist, and a liveness check that ran four million cycles before the panel engine's power-on delays had completed reported zero frames and looked like a reproduction until the window was moved past the panel's first frame and made longer than one panel frame. On hardware the check passes with the renderer running: the socket configuration reads back as VGA J2 on PMOD0 and VGA J1 on PMOD1 with hold clear, liveness passes on all three counters, and both measured signatures match their models exactly, which validates the scaling geometry, the bar placement and the latency compensation against a reference computed outside the FPGA. The suite reports nineteen passing tests, the new one being renderer liveness at seven frames and six panel ticks, and the panel path's pixel check was reduced from an asserted colour to the structural claim it was really making, since with the shortened hold the pattern advances every frame and a captured frame's colour is no longer fixed. The build measures `clk_pixel` Fmax 76.412 MHz against the 74.250 MHz constraint, MET but down from 83.329 after an edit that was only a register repacking, recorded as a suspected placement shift to confirm rather than explained away. The panel's own stream remains unmeasured and is the one genuinely independent comparison left, since the PmodVGA observes the transmitter's raster and cannot disagree with it. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 51 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The panel needs a per-pixel strobe out of `src/oled/oled_panel.sv` and a third checksum instance, which by the measured rate costs about 130 LUT/ALU and 100 registers and cannot pressure timing because the panel's stream is paced at sixteen clocks per pixel; the tool then reports three streams instead of two. After that, the store wrapper, moving both frame-store copies inside one module that owns the write bus so that one source of truth is structural rather than a wiring convention, at no cost in logic or timing. The Fmax question should be answered before more logic is added, and the deployed image still needs the register-layout fix, which requires a visit to the main menu.

#### Files Modified:

- build-pmod.tcl
- src/debug/ui_debug_regs.sv
- src/pmod_mirror_core.sv
- src/pmod_mirror_top.sv
- src/ui/ui_checksum.sv
- src/video/ui_hdmi_backend.sv
- src/video/ui_hdmi_scan.sv
- tests/run.sh
- tests/ui_mirror_tb.sv
- tools/ui_mirror_check.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 52 COMMIT Unreleased 2026-10-02T18:00:29-07:00

#### Coming From:

Unreleased 37f801d

#### Purpose:

Complete the mirror check with the panel's own stream, and settle where this core's Fmax actually comes from before adding anything else to it.

#### Outcome:

The panel now reports a per-pixel strobe, asserted at the launch of each pixel's high byte so that it lands on a cycle where the coordinate and therefore the pixel data are unchanged, and a third checksum instance folds that stream. The panel is the only genuinely independent third stream: the PmodVGA observes the transmitter's raster and cannot disagree with it, so a checksum there would be evidence of nothing. Its expected value is the source's own fold, because 1:1 scaling with no bars emits the store contents in exactly the order the renderer wrote them, and on hardware the two agree to the bit at `0xd6991800` while the transmitter's scaled stream reads its own `0xca1c5800`. That agreement is the strongest evidence the design has produced: the source signature is folded off the renderer's write port and the panel signature off the SPI stream leaving the FPGA, so two physically independent paths, running at different rates through different logic, produce the same number. The Fmax question was settled by measurement rather than by the pipeline stage first proposed. The critical path is `rgb` through the TMDS encoder's `q_m` XOR/XNOR network and population counts into the running-disparity accumulator, seventeen logic levels: the `q_m` stage is eight serial XORs by construction, so its depth is inherent to TMDS encoding and not a consequence of anything added here. Across placement options that path moves the reported Fmax by eleven MHz: option 0 fails the constraint at 65.724 MHz while option 2 reaches 77.543, option 3 76.412 and option 4 77.500, so the design sits near the edge and the option decides which side it lands on. Pipelining the encoder was rejected on second look, and the reversal is recorded because it matters: the disparity accumulator is a feedback loop inside third-party code, and a mistake there breaks HDMI output rather than costing a few MHz. `build-pmod.tcl` now pins option 2 with all four measurements written beside it and a note to re-measure when the netlist changes materially, the same discipline entry 45 applied to the merged image. Adding the strobe and the third checksum moved Fmax to 79.355 MHz, MET and better than the pinned 77.543, so the addition cost nothing and the placement shifted favourably. The suite reports nineteen passing tests. The image was uploaded as `cores/console138k/pmodtang.bin` with a byte-identical SD readback and loaded over the two-wire interface, and it is the first deployed image carrying the register-layout fix from entry 51, so the checker's layout fallback is no longer load-bearing. The check then passes on all three streams with liveness confirmed and the hold state restored. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 52 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

One structural item remains before the architecture can be called finished: moving both frame-store copies inside a single module that owns the write bus and exposes one read port per output, so that one source of truth is enforced by structure rather than by whoever last edited the top level. It costs no logic and no timing, and without it a future edit could feed the two copies different data without anything failing loudly. After that the remaining PMOD modules become personalities, then the fold into the player, where the renderer becomes a menu and the checker is the regression gate. The transmitter's marginal path stays a known, measured risk: if the margin ever genuinely bites, the cure is a deliberately staged encoder pipeline, validated against the mirror check rather than in place of it.

#### Files Modified:

- build-pmod.tcl
- src/oled/oled_panel.sv
- src/pmod/pmod_oledrgb.sv
- src/pmod_mirror_core.sv
- tools/ui_mirror_check.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 53 COMMIT Unreleased 2026-10-02T18:11:08-07:00

#### Coming From:

Unreleased b56e2b0

#### Purpose:

Make one source of truth a property of the design rather than a convention of the top level, by giving the frame stores an owner that fans the write bus itself.

#### Outcome:

`src/ui/ui_frame_bank.sv` instantiates the store copies and owns the write port, so callers can only read; earlier the top level created one store per output and wired the same write signals to each, which worked but meant a future edit could give one copy a different source and nothing would fail loudly, because each copy would remain internally consistent and simply display a different frame. It costs no logic and no timing, and the measurement confirms it: Fmax moved from 79.355 to 78.946 MHz across the change. Doing the relocation properly rather than as a bulk edit exposed a real latent defect. `ui_hdmi_backend` has latched the bank at its own frame boundary since entry 48, and its comment claimed the store read used that value, but the store was wired to the live global bank instead, so the latch was dead logic and the transmitter could have had its bank changed part way through a frame by a swap triggered at another output's boundary. That is the tearing protection the design documented but did not implement, and it is unreachable by simulation because the third-party transmitter cannot be elaborated, so the mirror check is the only instrument that can confirm the rewiring. It does: after deploying and loading the image, all three measured streams return values bit-identical to the run before the change, `0xd6991800` for the source, `0xca1c5800` for the transmitter and `0xd6991800` for the panel, with liveness passing and the hold state restored. A structural change producing identical measured output is the cleanest available regression evidence, and the two agreeing folds remain the strongest single result in the project, folded as they are off physically independent paths. The suite reports nineteen passing tests. `build-pmod.tcl` and `tests/run.sh` gained the new file. The image was uploaded as `cores/console138k/pmodtang.bin` with a byte-identical SD readback and loaded over the two-wire interface. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 53 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The architecture is now complete for its purpose: one owned frame store, a presentation backend per output, a socket layer with runtime declarations, and a checker that can prove agreement with nothing attached. Two directions remain. The remaining PMOD modules become personalities, each a file and a socket declaration rather than a new structure. Then the fold into the player, where the renderer becomes a menu writing the same store and the mirror check becomes the regression gate before each release, which is where its value grows rather than shrinks. The transmitter's marginal path stays the one measured risk, documented in `build-pmod.tcl` with the placement measurements and the reason pipelining was rejected.

#### Files Modified:

- build-pmod.tcl
- src/pmod_mirror_core.sv
- src/ui/ui_frame_bank.sv
- src/video/ui_hdmi_backend.sv
- tests/run.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 54 COMMIT Unreleased 2026-10-02T19:31:43-07:00

#### Coming From:

Unreleased 81795b8

#### Purpose:

Bring up the Digilent Pmod ENC as a rotary control on the second socket, which is the first personality whose pins are all inputs and the first intended to drive the interface rather than display it.

#### Outcome:

`src/pmod/pmod_enc.sv` debounces the four module pins, decodes the quadrature pair into a count, and normalises the push button and slide switch, all against a contract recorded in the file rather than inferred by its consumers. It drives nothing: every module pin is an input to the host, so both the lane outputs and the enables stay low, and the socket layer only ever reads. Two encoder instances exist, one per socket, because the module can sit on either; only their decoded state is selected, never their lanes, since there are no lanes to drive. The bring-up produced one real bug and one real design error, and both were found by differential measurement rather than by reasoning. The bug was seating: the module is a 1x6 part, so it occupies one row of the dock's 2x6 socket rather than spanning both, and in the row the lane mapping assumed, the personality read pins 7-10, which the module does not touch. That is the same physical situation the `flipped` bit already existed for, an upside-down module, so the fix was a single declaration and no new code; the differential that proved it was the raw pins reading `1111` with the flip clear, which is the empty row, and changing to a real state with it set, with the count advancing by exactly four per detent across two independent measurements, five clicks giving plus twenty and four clicks giving plus sixteen. The design error was the button polarity: the manual states that the button reads low in its native state, my normalisation inverted it, and a released button therefore read as pressed. It was caught by reading a known state rather than by reasoning about the manual's wording, and the fix is one line. A third item was removed rather than added. A derived `steps` register was implemented to divide the four-count detent down to one step per click, and the user rejected the need for it on the grounds that a detent is always four counts and any other delta means the module is broken, which is the consumer's concern and not the hardware's. That rejection was worth more than it looked: deleting the register and its offset-rebase arithmetic raised `clk_pixel` Fmax from 77.272 to 85.470 MHz, taking the margin from 2.5 percent to 15, and it removed a convenience register whose only purpose was to do arithmetic the consumer already gets for free -- which is the first step towards the convenience layer the hardware should not own. The counts-per-detent ratio, the incremental nature of the counter, the reset to centred on reload and the fact that a press shorter than the polling interval will be missed by design are all recorded in the file as a contract, since the consumer is deliberately responsible for polling properly. Placement was re-measured against the new netlist and the numbers written into `build-pmod.tcl`: option 0 reaches 70.026 MHz and fails, option 3, which was the default until entry 53, reaches 73.973 and also fails, while option 2 reaches 78.666 and 4 reaches 78.270, so option 2 is pinned. On hardware the personality reads back as configured, the count centres on load, the button reads zero when released where the inverted version read one, and the removed register returns zero because nothing decodes it. The suite reports nineteen passing tests. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 54 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Two modules the user has named remain: the eight-LED Pmod and whatever else follows, each a file and a socket declaration. The `flipped` bit's second meaning, covering a 1x6 module in the other row as well as an upside-down module, belongs in `core-reference.md` with the encoder's contract and pinout. After the modules, the fold into the player, where the renderer becomes a menu and the mirror check becomes the regression gate. One judgement call is left deliberately open for the fold: whether a register derived for a consumer's convenience is a hardware fact or a software shortcut, since `steps` was rejected as the latter and the same argument will return for anything similar.

#### Files Modified:

- build-pmod.tcl
- src/debug/ui_debug_regs.sv
- src/pmod/pmod_enc.sv
- src/pmod_mirror_core.sv
- tests/run.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 55 COMMIT Unreleased 2026-10-02T22:07:32-07:00

#### Coming From:

Unreleased da6551e

#### Purpose:

Fold the PMOD socket layer and its runtime configuration into the player itself, so the frames the player renders reach every screen from the player and the mirror check becomes the gate that proves it, with the rotary encoder as the first personality that is not a display.

#### Outcome:

The folded player now owns the whole socket surface. `src/pmod_mirror_core.sv` gained the inputs it had never had -- both personalities, both seating orientations and the renderer hold -- plus the encoder's decoded state as outputs, with the bring-up core's own register bank kept on separate signals and selected by `EXPOSE_STATE`, which is the same split `EXTERNAL_AUDIO` already makes for audio; `src/tang_phosphor_top.sv` now drives them from the player's `debug_regs` and reads the encoder back, and `src/pmod_mirror_top.sv` and `tests/ui_mirror_tb.sv` tie the new inputs off because both run with the bank inside. Without those inputs the player's register block, which is what a `/tang.ini` parser is meant to drive, wrote to nothing: the sockets ran on the bring-up core's power-on default and the hold bit was inert, so a developer could set a socket declaration and a freeze that reached no logic. The fold's first measurement was therefore the checker failing against a panel that was visually perfect, and the cause was not the panel. Nine wires in the player top were undeclared, and this tool gives an implicit net connected to a module port a width of one, so the 4-bit personality and the 32-bit encoder count were silently truncated: personality 4 became 0, which left the encoder's socket undeclared and made the core report its own defaults instead of the module's pins, and the count, always a multiple of four, read zero however far the knob turned. The OLED worked throughout on luck, because personality 1 fits in one bit, and the build log had named every one of those wires from the start; they were harmless only while they carried nothing. Explicit declarations fixed it, and the same truncation was why `raw` reading `0xf`'s low bit had looked like a real pin level while the encoder was in fact dead. The hold is now verified rather than assumed: with the renderer held, the pattern and the render count stay static while the panel keeps producing its own frames, where before the fold the pattern advanced through p3, p5 and p0 while held. `tools/ui_mirror_check.py` was wrong in a second way: it accepted a source match on the pattern before the one it reported and so printed PASS beside two numbers that plainly disagreed, and it could stop on a uniform fill, which any reordering satisfies; it now identifies each stream independently against all eight patterns, refuses to bank a verdict on a uniform frame and releases the hold to try the next one, which is how it reached a patterned frame at all. The user's decision that the player's sockets must power up released then exposed a defect no register could have shown: `src/oled/oled_panel.sv` runs its power-up and its 44-byte initialisation list once after configuration and never returns to them except through `rst`, so with the socket still released those bytes went out on a high-impedance pin and were lost, and a later declaration could only feed pixels to a panel that was never initialised or switched on, leaving it dark permanently rather than until configured. The engine is now held in reset until its socket is declared as OLEDRGB, so the init lands on a live socket, and because `ui_swap` waits on every output's frame tick the undeclared socket is masked out of that wait as well; without that second half, gating the engine would have stalled the renderer and blanked the HDMI on any card with no PMOD, which is a worse fault than the one being fixed. Both halves were measured rather than argued: undeclared, the render counter advanced while the panel frame counter stayed at zero, and declaring `0xc0 = 0x2410` released the engine, which ran its init and then produced frames at roughly 74 per second, after which the user confirmed the OLED was lit. The encoder was verified on hardware in the same session: the count resets to its centred `0x8000_0000`, five detents move it by exactly twenty, and `raw` reads `0xf` with the switch on and the button held and `0xb` with the button released and the switch still on. `scripts/build-merged.sh` with the pinned place3 seed reports timing MET with `clk_pixel` Fmax 80.503 MHz, and the artifact `1b9c8c80e813c92b1fbeb6380e12981a0bc41c865d3bf0c6fa89d10a4bb2a011` was uploaded as `cores/console138k/phosphortang.bin` with a byte-identical SD readback; the bring-up core still builds and meets timing at 85.470 MHz, and the suite reports nineteen passing tests. One limitation is recorded rather than excluded: the panel's stream folds to a value matching no whole frame for patterns 5 and 6, reproducibly `0x621c8400` and `0x27e05f33` against models of `0xef831c00` and `0x44328c00`, while patterns 0 to 4 and 7 agree exactly, so the check passes on pattern 7 and fails on 5 and 6 and the gate is not yet green. The agreements on 0 to 4 carry little weight because a flat colour folds to the same value under any reordering, and pattern 7, the card built to make a shift or a flip visible, agrees exactly, which suggests the panel is displaying correctly and the fault is in how the checksum captures its stream; but no tested permutation -- rotation by one either way, a dropped or duplicated pixel, column-major order, a per-row shift or a byte swap -- reproduces the measured values, so that remains a hypothesis for the next cycle rather than a diagnosis. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 55 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The panel stream's disagreement on patterns 5 and 6 is the next cycle, and the first thing to instrument is the checksum's capture rather than the display: `panel_px` is the live frame-store read bus sampled on the cycle after the panel engine latches its byte, so the folded sequence and the transmitted sequence can differ by a pixel, and the fix would be to fold the same registered value the engine sends. Because a fixed skew would also have broken pattern 7, the interaction with the engine's two-clock inter-pixel wait is the part that needs measuring, and the tool's own check should be made to cover a patterned frame on every run before it is called a gate. After that the renderer becomes the menu and the check runs before each release, which is where its value grows rather than shrinks. The remaining modules the user has named, starting with the eight-LED Pmod, stay behind that.

#### Files Modified:

- build-merged.tcl
- src/boards/console138k_merged.cst
- src/debug/debug_regs.sv
- src/pmod_mirror_core.sv
- src/pmod_mirror_top.sv
- src/tang_phosphor_top.sv
- tests/ui_mirror_tb.sv
- tools/ui_mirror_check.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 56 COMMIT Unreleased 2026-10-02T22:49:04-07:00

#### Coming From:

Unreleased 709ffa0

#### Purpose:

Fix the panel's frame-boundary pixel, which the mirror check's patterned frames exposed and the flat fills had hidden, so that all three of its streams agree on every pattern.

#### Outcome:

The mirror check's last open failure is closed, and the route to it was a user observation rather than a measurement. Patterns 5 and 6 had been the only two of eight where the panel's fold matched no whole frame, reproducibly `0x621c8400` and `0x27e05f33` against models of `0xef831c00` and `0x44328c00`, while source and transmitter matched their own models on every run; the flat fills could not see anything because a uniform fill folds identically under any reordering, and the orientation card agreed, so the display was believed correct and the checksum's capture was suspected instead. The user, looking at a frozen ramp frame, reported a single white pixel at the exact top-left corner, which is worth more than it looks: the ramp's first pixel should be `0x0000` while its last pixel is `0xBFFF`, so the corruption was a plausible-looking wrong pixel rather than obvious garbage. That fixed the hypothesis, and it then tested exactly: replacing each frame's first pixel with its last reproduces the measured panel fold on all eight patterns while leaving the flat fills and the orientation card unchanged, and the user confirmed the prediction independently by reporting that the corrupt pixel on the ramp was the same colour as the frame's bottom-right corner. `src/oled/oled_panel.sv` was at fault and not the checksum: the inter-pixel path waits two clocks (`S_PIXWAIT`) so that the mapper's registered mapping and the store's registered read can deliver the pixel belonging to the coordinate, but `S_FRAME` went straight into `S_PIX`, so the frame's first pixel was launched while both still held the previous raster position and carried address `(95,63)`, the last pixel of the frame that had just ended. The address window now hands over through `S_PIXWAIT` with the same two-clock wait. The defect had been present since the panel checksum was added and was invisible to every earlier test for a reason worth recording: the bring-up verification's headline result, that two physically independent paths folded to the same number, was measured on `0xd6991800`, which is pattern 3, a flat white frame whose first and last pixels are identical, so that agreement was real and blind at the same time. On hardware after deploying `32e31f68a4b8bef1e2c10101cdb5edce27b619fcaf3e4cf3ce72e9a197c5fe8e`, a held-frame sweep over all eight patterns now gives panel equal to source on every one including 5 and 6, `tools/ui_mirror_check.py` reports PASS on pattern 5 with all three measured streams matching their models, and the encoder regression is unchanged at count `0x8000_0000` with `raw` reading `0xb` with the switch on and the button released. The build reports timing MET with `clk_pixel` Fmax 76.771 MHz, down from 80.503 for a one-line state-machine change, which is recorded as a suspected placement shift to re-measure rather than explained away, and the artifact's SD readback matched; the suite still reports nineteen passing tests, but nothing in it could have caught this fault and that is the cycle's real debt, because `tests/ui_mirror_tb.sv` asserts the panel's init list, window commands and D/C polarity and then explicitly declines to assert a pixel's value on the stated grounds that the panel has no per-pixel strobe, which has been untrue since entry 52 and is now stale. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 56 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The first work of the next cycle is the test that should have caught this: `tests/ui_mirror_tb.sv` already decodes the SSD1331 stream out of the raw socket pins, so it can assert that a captured frame's first transmitted pixel is one of the values a frame's first pixel may legitimately take, which fails on the pre-fix behaviour and needs no model of the whole frame. That assertion rests on the premise the mirror check now enforces from the other side, which is that a claim measured only on flat colours is not a claim. The placement is then re-measured against the new netlist with the numbers written beside the pinned seed in `build-merged.tcl`, the discipline entries 45 and 52 applied, since a 3.7 MHz drop for a one-line change is unexplained and may not be real. After that the panel path is closed out and the renderer becomes the menu, with the check running before each release, which is where its value grows rather than shrinks.

#### Files Modified:

- src/oled/oled_panel.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 57 COMMIT Unreleased 2026-10-02T22:55:38-07:00

#### Coming From:

Unreleased 568ffda

#### Purpose:

Add the assertion that would have caught the panel's frame-boundary pixel fault before hardware, so the suite can see a class of defect it was structurally blind to.

#### Outcome:

This cycle changed one test file and no gateware, and its result is a fault that can no longer reach hardware undetected. `tests/ui_mirror_tb.sv` already decoded the SSD1331 stream out of the raw PMOD0 socket pins, so the addition is small: every frame's first transmitted pixel is recorded as it goes past, and each is required to be one of the values the pattern function produces at `(0,0)`, which are red, green, blue, white and black. The ramp's last pixel is `0xBFFF` and is none of those, which is exactly what a first pixel launched one clock early produces, so the assertion is aimed at the mechanism entry 56 fixed rather than at its symptom. It is checked over a full pattern cycle of frames rather than one because the flat fills and the orientation card produce a legal first pixel either way, so only a patterned frame can show it, which is the same blindness that let the fault survive every earlier test. The reason the value was not asserted before has been removed rather than left standing: the file declined to check a pixel's value on the stated grounds that the panel had no per-pixel strobe, which stopped being true in entry 52. The test was then proved against both revisions rather than assumed to work, which is the part worth keeping: with the fix in place the suite reports nineteen passing tests, and with `src/oled/oled_panel.sv` temporarily returned to launching the frame's first pixel without the two-clock wait it exits `134` with seventeen passing and reports frames 3, 4, 6, 8 and 9 starting with `0xf81f`, `0x07ff`, `0xff00`, `0x00ff` and `0xbf00`. Those five values are not identical to the single `0xBFFF` seen on hardware, which is recorded rather than smoothed over: either the corrupted timing shifts which two bytes the testbench assembles at the frame boundary, or the hardware and the simulation fail slightly differently, and the assertion catches the class without claiming to reproduce that one value. No bitstream was rebuilt or deployed and the standing deployment of `32e31f68a4b8bef1e2c10101cdb5edce27b619fcaf3e4cf3ce72e9a197c5fe8e` from entry 56 remains the verified image. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 57 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The placement re-measurement carried from entry 56 is the next work: the pinned seed in `build-merged.tcl` should be re-measured against the new netlist with the numbers written beside it, the discipline entries 45 and 52 applied, because a 3.7 MHz `clk_pixel` drop for a one-line state-machine change is unexplained and may be a placement artefact rather than a real cost. The panel path is otherwise closed out, with the hardware check as its gate on the bench and this assertion as its gate in simulation. After that the renderer becomes the menu writing the same frame store, and the check runs before each release, which is where its value grows rather than shrinks; the remaining PMOD modules the user has named, starting with the eight-LED Pmod, stay behind that.

#### Files Modified:

- tests/ui_mirror_tb.sv

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 58 COMMIT Unreleased 2026-10-02T23:05:38-07:00

#### Coming From:

Unreleased 37d633e

#### Purpose:

Re-measure the merged placement against the current netlist and pin the fastest seed by measurement rather than by inheritance.

#### Outcome:

The merged placement was re-swept because entry 56's one-line change moved `clk_pixel` Fmax from 80.503 to 76.771 MHz, which is more than such a change should cost and could have been either a real cost or a placement artefact. Four options were built from the current netlist and every one meets timing, so the standing note that options 1 and 4 fail setup was measured against a different netlist and no longer holds: option 0 reaches 77.264 MHz, option 2 78.674, option 3 76.771 and option 4 76.150, all above the 74.250 MHz constraint. Two things came out of it besides the numbers. The build is deterministic, which the pinned-seed discipline depends on: option 3 reproduced both its artifact and its exact Fmax, `32e31f68a4b8bef1e2c10101cdb5edce27b619fcaf3e4cf3ce72e9a197c5fe8e` at 76.771 MHz, the same values entry 56 deployed and verified. And the seed still moves the clock by 2.5 MHz across options, so pinning it is worth doing: the default moved from 3 to 2 because option 2 is the fastest of them, with all four measurements written beside it in `scripts/build-merged.sh` and the stale claim about options 1 and 4 removed rather than left to mislead a future reader. `build-merged.tcl`'s literal seed was also two revisions out of step with the script's default, because the script always sets the environment variable and the literal applies only when `gw_sh` is run by hand; it now matches and says why. The deployed image is deliberately left alone: the card still holds option 3, which meets timing, and re-deploying the faster seed with the mirror check as its gate is the next step rather than something to assume. No bitstream was rebuilt for deployment in this cycle and none was uploaded. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 58 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Deploy the newly pinned option 2 image and put it through the same evidence the previous one earned, which is the mirror check on a patterned frame, the encoder read, and a visual pass, so that the card holds the fastest measured seed rather than the previous one; that is a hardware cycle and the check is its gate. After that the renderer becomes the menu writing the same 96x64 frame store, with the check running before each release, which is where its value grows rather than shrinks. The remaining PMOD modules the user has named, starting with the eight-LED Pmod, stay behind that.

#### Files Modified:

- build-merged.tcl
- scripts/build-merged.sh

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---

## 59 COMMIT Unreleased 2026-10-02T23:13:14-07:00

#### Coming From:

Unreleased 83f7bb3

#### Purpose:

Put the newly pinned placement seed on the card and give it the same evidence the previous image earned, so the standing image is the fastest measured one rather than the one that happened to be there.

#### Outcome:

The card now holds the option 2 image rather than the option 3 image, and it earned its place rather than inheriting it. The artifact is the one entry 58's sweep built and measured at `clk_pixel` Fmax 78.674 MHz, `5507492ecbbb8de4eb695aece0f8b5e922580394d9d35bc3563de89d540210bb`, so no bitstream was rebuilt for this cycle; it was uploaded as `cores/console138k/phosphortang.bin` and the SD readback matched by size and CRC-32. The evidence is the same set the previous image earned, run on the new seed: a held-frame sweep that reached all eight patterns reports no failures, with the panel folding to the source's value and the transmitter to its own model on every one; `tools/ui_mirror_check.py` passes on pattern 6, which is one of the two patterns that failed until entry 56 and reports source, transmitter and panel all matching their models with liveness confirmed; and the encoder still reads count `0x8000_0000` with `raw` at `0xb`, the switch on and the button released, so the socket path came through the reconfiguration unchanged. The user reported acceptance of the hardware result. This closes the deployment step entry 58 carried forward and leaves the card holding a timing-MET image that is 1.9 MHz better placed than the one before it. No engineering file changed in this cycle. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 59 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The renderer now becomes the menu writing the same 96x64 frame store, which is the step the whole socket layer and the mirror check were built to support: the check runs before each release, and the encoder is the control that drives it. The remaining PMOD modules the user has named, starting with the eight-LED Pmod, are each a file and a socket declaration rather than new structure, and stay behind the menu work. One judgement call carried from the fold is still open for that cycle: the display path now has a working hold, a live socket declaration and an encoder whose state is readable, so a consumer should poll rather than expect the hardware to queue, and the same argument will return for any register that exists to save a consumer arithmetic it already gets for free.

#### Files Modified:

None.

#### Status:

- Build: NOT RUN
- Deployment: PASS
- User Test: PASS

---

## 60 COMMIT Unreleased 2026-10-02T23:29:21-07:00

#### Coming From:

Unreleased 7254843

#### Purpose:

Verify the VGA configuration on hardware, which the checker cannot prove for itself, and make the checker valid in that configuration rather than falsely failing on it.

#### Outcome:

The VGA works, and making it work on the bench exposed a gap in the tool that reports on the bench. Configuration B was re-established physically: the OLED came out of PMOD0 and the encoder out of PMOD1, because the PmodVGA is a dual-socket module, and J2 went to PMOD0 with J1 to PMOD1, ICs up, matching Tang-PSX's verified pairing; the card had to be power-cycled to seat them, so the image was loaded from the SD card rather than re-uploaded. Declaring `0xc0 = 0x230` selects `vga_j2` on PMOD0 and `vga_j1` on PMOD1 with no flips and no hold, and the register evidence is what the VGA has instead of a checksum, since `ui_vga_backend` derives its syncs and colour from the transmitter's raster and cannot disagree with it. Three things were measured. The renderer stays live with no panel declared, which is the first real exercise of the swap masking from entry 55: the panel engine is held off, its frame counter sits at zero, and its tick is masked out of `ui_swap`, so an undeclared output cannot stall the picture. The panel frame counter stayed at zero across the run, confirming the engine is held off rather than quietly driving sync-carrying pins. And the transmitter matched its model on all eight patterns when measured with the renderer held, fourteen samples with no failures; two apparent mismatches in a first pass were the tool's own sampling, since each `peek` is a separate round-trip and a source read and a transmitter read can straddle a pattern change, which holding removes. The user confirmed the CRT image. The gap the configuration exposed is the cycle's other half: `tools/ui_mirror_check.py` required all three frame counters to advance and always expected a panel stream, so it would have reported FAIL on a working VGA configuration, and a gate that fails on a valid board is a gate people learn to ignore. It now judges only the outputs the socket declaration actually creates, and it says plainly that the PmodVGA follows the transmitter's raster and cannot be checked independently rather than implying coverage it does not have. Run in the VGA configuration afterwards it reports source and transmitter matching their models, liveness passing on the declared counters, and the panel line reading not declared; the liveness label was also corrected, because it still named a panel that this configuration does not have. The artifact deployed remains entry 59's option 2 image and no gateware changed. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 60 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The renderer becomes the menu writing the same 96x64 frame store, which is what the socket layer, the hold and the checker were built to support, with the check running before each release and the encoder as the control that drives it. Two small debts travel with it. The VGA configuration has no automated evidence of its own beyond the transmitter it follows, so a test of the backend's sync windows and lane mapping, outstanding since entry 49, would close the last output that is verified only by eye. And the panel and VGA configurations need different socket declarations and different physical seating, so whichever one the next cycle finishes on, the other must be re-verified rather than assumed to still hold.

#### Files Modified:

- tools/ui_mirror_check.py

#### Status:

- Build: N/A
- Deployment: PASS
- User Test: PASS

---

## 61 COMMIT Unreleased 2026-10-02T23:34:34-07:00

#### Coming From:

Unreleased 40c1ff7

#### Purpose:

Record the menu renderer's contract, geometry and slice order in the durable reference before any of it is written, so the shape is settled while changing it is still cheap.

#### Outcome:

No gateware changed in this cycle; it fixes the shape of the next few. Scoping the menu renderer against the existing files produced one finding worth writing down before implementation, which is that `src/ui/phosphor_album_ui.sv` cannot be ported to this job. That module is a pixel-rate overlay evaluator: the raster hands it `(x, y, rgb_in)` and it returns `rgb_out`, looking glyphs and artwork up by address while the beam passes, laid out on a 16x20 cell grid. The menu needs the opposite shape, a frame writer that fills the back bank, raises `render_done` and waits for `render_enable`, which is the contract `src/ui/ui_pattern_demo.sv` already meets. So the work is a new module sharing only the state inputs rather than a port of 865 lines, and treating it as a port would carry a cell geometry that cannot fit 96x64 and a per-pixel evaluation the frame store makes pointless. The arithmetic is kind: a 6x8 cell tiles 96x64 exactly, 16 columns by 8 rows with nothing over, whereas 16x20 cells do not fit and the layout must be redesigned rather than shrunk. Two things carry over unchanged and are the reason the change is smaller than it looks. The characters keep arriving from the host, because `src/ui/phosphor_ui_control.sv` owns `text_memory`, a 256x32 block RAM the transport writes and which is double-buffered, so Tang-Control's protocol needs no change; the host owns text and the FPGA owns glyphs. And every state input a menu needs is already wired, being `visible`, `playlist`, `paused`, `player_state`, `current_track`, `track_count`, `window_start`, the eight track lengths, `elapsed_seconds`, `duration_seconds` and `samples_played`. The four slices are recorded in `.ai/core-reference.md`: the contract first with a fixed frame derived from cell indices, which proves the cell addressing before any glyph data exists; then the 6x8 font and the text grid with a test that renders known strings and checks pixels; then content and layout from the state inputs; then re-verification of both configurations, since panel and VGA need different seatings and different socket declarations and the encoder becomes the menu's control. Recording the plan rather than starting it is deliberate: the alternative was beginning a few hundred lines of RTL with no room to verify them, which is the failure this session avoided each time it came up. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 61 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Slice 1 is the next cycle and it is specified rather than sketched: a renderer that fills the 96x64 store in raster order, raises `render_done` when the back bank is complete, waits for `render_enable` before touching the other bank, and draws a fixed frame whose pixel values are derived from cell indices so the 16-column by 8-row addressing is provable. It should be built with a simulation test asserting the write order and the handshake before hardware is involved, and then worked through the mirror check and a visual pass, which is the same evidence every other change in this architecture has had to earn. After it, the font and the text grid, then the content, then the re-verification of both configurations.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 62 COMMIT Unreleased 2026-10-03T00:33:40-07:00

#### Coming From:

Unreleased 660409f

#### Purpose:

Implement slice 1 of the menu renderer: a frame writer that fills the 96x64 store in raster order under the swap handshake, drawing a fixed frame whose pixels are derived from cell indices so the 16-column by 8-row grid is provable before any glyph exists.

#### Outcome:

Added `src/ui/ui_menu_renderer.sv`, the slice-1 frame writer: it fills the back bank of the shared store in raster order at one pixel per clock, raises `render_done` for one cycle when the bank is complete, and draws a fixed frame whose 16-bit value names its own coordinate, with the cell row at `[14:12]` and the cell column at `[10:7]` above the in-cell offsets, so all 6144 pixels are distinct and the 6x8 cell that tiles the store exactly 16 columns by 8 rows is provable with no glyph, font or state input existing. Two handshake hazards were found and closed while writing it rather than left for hardware. The first is that the swap does not lower `render_enable` until the cycle after `render_done`, so a renderer that re-armed on the pulse would begin the next frame into the bank it had just written, because the bank has not flipped yet; the demo is protected from this only by its one-second dwell, and a menu has no dwell to hide behind, so this renderer instead waits for the swap to acknowledge `render_done` (enable low) and complete (enable high) before starting a frame. The second is that `hold` is consulted only between frames, so a frame in flight is never torn. `tests/ui_menu_renderer_tb.sv` proves both against a real `ui_swap` rather than an assumed stimulus: write N lands at `(N % 96, N / 96)` for 6144 writes a frame, every pixel equals the cell-index model computed independently in the test, no word repeats within a frame, every write lands in the bank the outputs are not reading and the target alternates frame to frame, a frame starts only while the swap is idle and only after the acknowledgment, and no pixel is written while `hold` is asserted. It is registered in `tests/run.sh`; the Verilator suite passes, the new check reporting four frames and 24576 pixels, with every pre-existing check unchanged. No gateware changed in this cycle and the module is not yet instantiated, so no bitstream was built or deployed and the simulation is the gate. Wiring it into `pmod_mirror_core.sv` is deferred for approval because it is not a drop-in: the renderer's frame is a single fixed image rather than the demo's eight patterns, so `tools/ui_mirror_check.py`, which identifies a frame by matching its fold against the eight-pattern model, would need that model extended before the change could be judged on hardware. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 62 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Wire `ui_menu_renderer` into `pmod_mirror_core.sv`, extend `tools/ui_mirror_check.py` with a model for the fixed cell frame, then rebuild and deploy the bring-up image and earn the evidence every other change here has had to: the mirror check green on the fixed frame, a visual pass on the panel and the VGA, and the encoder as the menu's control. That wiring changes the user-visible image from the eight demo patterns to the proof frame and invalidates the checker's pattern identification, so it is held for approval rather than assumed. The font and the text grid, then content and layout from the state inputs already wired, follow the slice order recorded in `.ai/core-reference.md`.

#### Files Modified:

- src/ui/ui_menu_renderer.sv
- tests/ui_menu_renderer_tb.sv
- tests/run.sh

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 63 COMMIT Unreleased 2026-10-03T00:55:56-07:00

#### Coming From:

Unreleased 280f8d3

#### Purpose:

Wire the slice-1 menu renderer into the bring-up core in place of the demo and retarget the mirror check to the frame it draws, so the renderer reaches the store and the checker judges the frame that is actually displayed.

#### Outcome:

`src/pmod_mirror_core.sv` now instantiates `ui_menu_renderer` where `ui_pattern_demo` was, so the store the panel, HDMI and PmodVGA read is filled by the menu's frame writer rather than the demo; the `DEMO_HOLD_MS` parameter is gone, the hold now freezes the menu renderer between frames, and the 3-bit field the host reads at 18:16 of the control register is tied to zero with the comment stating why (a menu publishes one frame, the demo reported a pattern index, and the position is kept so the host map does not move). `src/tang_phosphor_top.sv` drops the now-absent parameter connection; the two `build` tcl file lists and the integration test's source list swap `ui_pattern_demo.sv` for `ui_menu_renderer.sv`; the register-map comments in `src/debug/ui_debug_regs.sv` and `src/debug/debug_regs.sv` now describe that field as the renderer's frame selector. `tools/ui_mirror_check.py` no longer identifies one of the demo's eight patterns by fold: it models the single cell frame, computes the source, panel and transmitter folds directly, and compares each stream against them, which is all a one-frame renderer can support; the pattern-identification, uniform-frame retry and nearest-model language are gone because the demo they guarded is gone. The demo module is retained in the tree as the reference implementer of the contract but is no longer instantiated or built. Verification: `tests/ui_menu_renderer_tb.sv` still passes, and `tests/ui_mirror_tb.sv` now asserts that every captured panel frame begins with the menu frame's (0,0) value `0x0000` -- the previous frame's last pixel `0x77DE` would be the one-clock-early launch -- and cross-checks the core's published source signature against a host model written independently in the testbench, which passes at `0x76491800`; the same value comes out of the Python model in `tools/ui_mirror_check.py`, so the checker is validated against the RTL rather than only on a bench, with the transmitter's scaled model at `0x6c435800` and the panel's expected fold equal to the source's. The full Verilator suite passes, twenty-one checks with no failures. `scripts/build-pmod.sh` built the bring-up core with timing MET, `clk_pixel` Fmax `81.503` MHz against the `74.250` MHz constraint, which is 2.8 MHz better margin than the demo's pinned option 2 measured at `78.666`, and produced `build/pmod/tang_phosphor_pmod.bin`, SHA-256 `db4f85a0f43448597bf8ee1f529a7253fbe2ef0f2ebc0db2020ba69dc6d6f0d6`. Deployment and user testing did not run: no FT2232 or other JTAG device is attached to this machine, so the `.fs` was not flashed and the mirror check was not run against hardware, and the merged player build was not run either because the mirror check targets the bring-up map and the player change is the single removed parameter connection, which a repository-wide search confirms leaves no dangling reference. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 63 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Flash `build/pmod/tang_phosphor_pmod.fs` and run `tools/ui_mirror_check.py` on the seated configuration, expecting source and panel to read `0x76491800` and the transmitter `0x6c435800`, then confirm the fixed cell frame visually on the panel; if the bench is still in the VGA configuration it needs its own socket declaration and seating and must be re-established first. After the renderer is on hardware, slice 2 is the 6x8 font and the text grid, with a test that renders known strings and checks pixels, followed by content and layout from the state inputs already wired and re-verification of both configurations.

#### Files Modified:

- build-merged.tcl
- build-pmod.tcl
- src/debug/debug_regs.sv
- src/debug/ui_debug_regs.sv
- src/pmod_mirror_core.sv
- src/tang_phosphor_top.sv
- tests/run.sh
- tests/ui_mirror_tb.sv
- tools/ui_mirror_check.py

#### Status:

- Build: PASS
- Deployment: NOT RUN
- User Test: NOT RUN

---

## 64 COMMIT Unreleased 2026-10-03T01:23:45-07:00

#### Coming From:

Unreleased 752dc26

#### Purpose:

Put the menu renderer on the standing Phosphor core and re-pin the merged placement seed the changed netlist requires.

#### Outcome:

The merged image was swept with `MERGED_PLACE_OPTIONS="1 2 3 4"` and the seed again decides which side of the constraint the design lands on: option 1 reaches 73.111 MHz, option 2 72.831 and option 4 70.821, all below the 74.250 MHz `clk_pixel` constraint, while option 3 reaches 76.518 MHz and MET. The failing paths are the third-party TMDS encoder's disparity accumulator and the `tangcore_io` transport, not the renderer, so this is the placement sensitivity entry 52 recorded rather than a cost introduced by the menu frame writer, and the previous netlist's note that every option met timing with option 2 fastest no longer holds. Option 3 was uploaded to `cores/console138k/phosphortang.bin` -- the standing Phosphor player image, whose prior contents were the entry 59 artefact -- with a verified SD readback at 5018826 bytes, CRC-32 `969f32b9`, SHA-256 `c497e1344606c70583ad2159b88d9061d056d18bb23ab16a451056b222a651d5`, and loaded through `tangctl.py core` to a core reporting magic `0x54504830`, transport protocol 1 and capabilities `0x0000001f`. `tools/ui_mirror_check.py --map merged` then passed, which is the point of the cycle: with both sockets released the source measured `0x76491800` and the transmitter `0x6c435800`, both exactly the values the RTL and the checker agreed on in simulation, and after the standard OLED and rotary-encoder combo was declared by writing `0xc0 = 0x2410` (PMOD0 oledrgb, PMOD1 the encoder with its seating bit) the panel measured `0x76491800`, equal to the source as 1:1 scaling requires, with liveness confirmed on the render, HDMI and panel frame counters and the hold state restored. The panel signature is folded off the SPI stream leaving the FPGA, physically independent of the renderer's write port, so three streams agreeing on the modelled values is the strongest evidence this design produces and it now holds for the menu frame specifically; the user confirmed the HDMI picture showed the fixed cell frame. The seed was re-pinned from 2 to 3 in `build-merged.tcl`, the sweep was recorded in `scripts/build-merged.sh`, whose comment had said 2 while its own default already read 3 and now agrees, and the stale measurement note in `build-pmod.tcl` was refreshed with the option-2 re-measurement of 81.503 MHz that this cycle's bring-up build produced, MET against 74.250. No RTL changed in this cycle; the renderer reached the design in entries 62 and 63. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 64 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Slice 2 is the 6x8 font and the text grid, with a test that renders known strings and checks pixels against the cell geometry this frame proves, followed by content and layout from the state inputs already wired and then re-verification of both configurations. Two carried items remain: the bring-up core's slot on the card, `cores/console138k/pmodtang.bin`, still holds the old demo build and could be refreshed in a later cycle, and the VGA configuration needs its own socket declaration and seating before it can be re-checked, since declaring it means declaring no panel.

#### Files Modified:

- build-merged.tcl
- build-pmod.tcl
- scripts/build-merged.sh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---
## 65 COMMIT Unreleased 2026-10-04T07:02:13-07:00

#### Coming From:

Unreleased cf300b3

#### Purpose:

Establish whether Gowin's USB 1.1 SoftPHY can be brought into the shipping core at all, and measure what it costs there, before any host controller is written.

#### Outcome:

The SoftPHY cannot be produced the way the DDR3 controller is: its IPSpec declares no `projectName` and no `rtlFiles`, so `create_ipc -name usb_11_softphy` registers an IP that `get_ips` never returns a usable handle for and `generate_target` emits nothing, while Gowin drives this generator from the IP Core Generator dialog. Reading `libUSBSoftPHY.so` recovered that dialog's entire configuration -- a clock frequency of 36, 48 or 60 MHz and a Disable I/O Insertion toggle -- together with the file set it writes, and `scripts/gen-usb-phy-ip.sh` now reproduces that set from the local installation, keeping `usb_softphy.vp` and the other licensed files out of the repository exactly as `scripts/gen-ddr3-ip.sh` keeps the DDR3 core out. `src/pll/pll_48.mod` and its generated `src/pll/pll_48.v` supply the PHY input clock, derived from the DDR3 PLL recipe and differing from `src/pll/pll_12.v` only in the module name, the header, `MDIV_SEL` 18 to 24 and `ODIV0_SEL` 75 to 25, which is 48.0 MHz on a 1200 MHz VCO. An isolated probe first tied the UTMI inputs to constants and GowinSynthesis swept the transceiver as dead logic, reporting WARN NL0002 against 99 LUTs, and only a harness whose register drives the UTMI inputs and is fed back from the PHY's own outputs kept the core live enough to place. The merged core then built with port 1's `usb_hid_host` replaced by the SoftPHY, `pll_48` and that harness, and the swap is net negative on area against placement 3's baseline -- logic 13781 to 13582, registers 13163 to 13039, CLS 12058 to 11894, BSRAM 116 to 115 -- so the full-speed PHY costs less than the low-speed host it displaces, but its price is clocks: PLL 5/12 to 6/12 and PRIMARY 6/8 to 7/8 at 88 percent, now the scarcest resource in the design. The PHY's own domain closes at every seed, Fmax 115.311 to 122.624 MHz against its 48 MHz constraint. The placement sweep was then run both ways and overturned the single-seed conclusion this cycle first drew: without the PHY only seed 3 meets timing while seeds 0, 1, 2 and 4 fail, and with it seeds 0 and 4 meet and seed 3 does not, so the PHY does not break closure but reshuffles which seeds land, and no conclusion about this placement-sensitive design may be drawn from one seed. Surveying the standing design's margins, `clk_pixel` at its 74.250 MHz constraint is the only clock that ever fails at any seed, the design's worst setup slack at seed 3 is +0.399 ns and sits on the third-party TMDS encoder inside `display/g_hdmi.hdmi_backend/hdmi_tx/tmds_gen`, the other marginal path is the `tangcore_io` transport, and every other clock passes with wide margin everywhere. The flac and wav decoders are absent from the merged build entirely, their sources remaining in `src/audio/` without being added, so the decoder bit-reader work entry 26 proposed is obsolete, and the area their removal freed did not buy `clk_pixel` margin because the TMDS encoder is the bottleneck. One limitation is recorded rather than repaired: `build.tcl` cannot build the committed `src/tang_phosphor_top.sv`, since it omits the UI, video, PMOD and OLED sources that top instantiates, which are roughly the thirty-two files `build-merged.tcl` carries, so `scripts/build.sh` is non-functional at HEAD. No RTL was landed and the harness was reverted, so this cycle produced no artefact for the Tang and reached no hardware stage. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 65 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Buy back `clk_pixel` margin at its source, the third-party TMDS encoder, because the design's entire timing reserve is +0.399 ns and anything later added to the merged netlist competes for it; run `MERGED_PLACE_OPTIONS="0 1 2 3 4" scripts/build-merged.sh` and compare every option against the same option without the change, since a single seed has now misled this project once. The full-speed host controller is the work that follows and can begin once that margin exists, and the first integration decision it forces is which seed replaces 3. `build.tcl`'s divergence from the top it names remains open and unapproved for repair.

#### Files Modified:

- scripts/gen-usb-phy-ip.sh
- src/pll/pll_48.mod
- src/pll/pll_48.v

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---
## 66 COMMIT Unreleased 2026-10-04T08:36:20-07:00

#### Coming From:

Unreleased 3cc32c0

#### Purpose:

Close `clk_pixel` at every placement seed, because the design's whole timing reserve sat on the third-party TMDS encoder's disparity path and anything later added to the merged netlist would have to compete for it.

#### Outcome:

`src/hdmi/tmds_channel.sv` was changed in two ways that target that path. First, `q_m` is a cumulative XOR of the video byte and the reference writes it as a serial chain, `q_m[i+1] = q_m[i] ~^ video_data[i+1]`, whose seven dependent LUT levels terminate at the disparity accumulator; it is now a Kogge-Stone prefix tree three levels deep, with the XNOR branch expressed as the XOR prefix inverted on odd bits (`pre_xor ^ 8'b1010_1010`) and `q_m[8] = ~xnor_branch`, which is the same function exactly. Second, the encoder is split into two `clk_pixel` stages, `q_m` registering alongside `mode`, `control_data` and `data_island_data` so the disparity decision and the mode select run from registered values. Because the split is uniform across all five modes the TMDS symbol stream is delayed by exactly one pixel clock, and since the stream carries its own sync the picture, the guard bands and the framing are unchanged, so no latency compensation was needed anywhere. The rewrite was proved equivalent before it was trusted: a bench in `build/tmds-check/` ran the rewritten module against the original pulled from git with random video, island, control and mode traffic and found zero mismatches over 400003 cycles, the new output equalling the reference delayed by one pixel clock, and the project suite passes unchanged including `ui_mirror` and the HDMI scan test. The placement sweep then went from one closing seed to five: before the change `clk_pixel` reached 68.971, 73.111, 72.831, 76.518 and 70.821 MHz at seeds 0 through 4 with only seed 3 meeting its 74.250 MHz constraint, and afterwards it reaches 76.314, 75.011, 78.088, 82.089 and 86.655 MHz with TNS zero everywhere and worst setup slack between +0.137 and +1.928 ns. The encoder has left the critical path entirely; the tightest remaining paths are the `tangcore_io` transport on `clk_pixel` and the AE350 register block on `bus_clk`, and the cost of the change is 44 registers and roughly fifteen fewer LUTs with BSRAM unchanged. The merged image was uploaded as `cores/console138k/phosphortang.bin` at 4971210 bytes with CRC-32 `15d7a59b` and a matching SD readback, loaded to `active_core` 80 with `peek 0` returning `0x54504830`, and `tools/ui_mirror_check.py --map merged` passed with source `0x76491800` and transmitter `0x6c435800`, the same two values entry 64 recorded before the change, so the rendered frame is provably identical rather than merely plausible; the user confirmed the HDMI picture. This cycle also closed the PMOD question that entry 64 left open, and the answer was physical rather than logical. With the merged core loaded and both sockets declared, and with the pinout report confirming all sixteen `pmod0_io` and `pmod1_io` pins placed as `io` at the documented balls, neither the OLED panel nor a PmodVGA produced anything, and the same was true on the bring-up image at `cores/console138k/pmodtang.bin`, which had previously driven the VGA; the socket enable chain was therefore audited end to end and found correct, through `EXPOSE_STATE` and the register wiring from `debug_regs` to `pmod_mirror_core`, the personalities' asserted enables (`8'hff` for VGA J1, `8'h3f` for J2, `8'hfb` for the OLED), `pmod_slot`'s gating-free permutation, `pmod_io_buf`'s tri-state, and pin constraints identical to the bring-up core's. The cause was that the module was seated inverted, which swaps pins 1-4 with 7-10 while leaving power and ground in place, so two unrelated modules looked dead together across two different bitstreams with entirely correct gateware; once seated correctly the VGA worked on the merged core and then the OLED. One reference ambiguity is recorded rather than fixed: `PMOD-003` gives the socket control register as `0x10`, which is the bring-up map's address, while the merged core's is `0xc0`, and the two cores carry different register maps generally, which the checker already encodes as its `bringup` and `merged` maps. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 66 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The margin this cycle bought was the precondition for the full-speed USB host whose feasibility entry 65 recorded, so that work can begin; if further margin is wanted first, the next target is the `tangcore_io` transport, whose +0.137 ns at seed 1 is now the tightest path in the design. Two items are carried. `build.tcl` still cannot build the committed `src/tang_phosphor_top.sv`, because it omits the UI, video, PMOD and OLED sources that top instantiates, so `scripts/build.sh` remains non-functional until that divergence is resolved or the build is retired. And `PMOD-003` should say which core's register map its socket control address belongs to, since a host that pokes `0x10` on the merged core silently writes nothing.

#### Files Modified:

- src/hdmi/tmds_channel.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---
## 67 COMMIT Unreleased 2026-10-04T09:49:24-07:00

#### Coming From:

Unreleased 994ce89

#### Purpose:

Define TinyTang's keyboard link and prove the FPGA end of it in simulation, so the keyboard's firmware is written against a receiver that already works.

#### Outcome:

TinyTang's keyboard input will not use USB, and this cycle settled why that is possible and what it costs. The front USB-A port is two FPGA pins wired to the connector and nothing else, and the target keyboard is an STM32F401 whose USB data pins are not dedicated silicon: `keyboards/keychron/k2_he/board.h` in Keychron's own QMK fork configures GPIOA with `PIN_MODE_ALTERNATE(GPIOA_OTG_FS_DM)` and `PIN_MODE_ALTERNATE(GPIOA_OTG_FS_DP)`, so PA11 and PA12 are general-purpose pins whose mode the firmware chooses, and the STM32's USB pull-up is internal to the peripheral, so nothing external has to be defeated when the pins are taken back. The K2 HE is a boot-protocol HID device and is otherwise an ordinary full-speed one, which matters because the design's existing `usb_hid_host` is low-speed only (NEST-001) and the keyboard's receivers negotiate 12M, so USB would have required the full-speed SoftPHY host that entry 65 costed. The protocol chosen is a fixed-baud UART, one direction per wire, full duplex, with no addressing and no polling discipline imposed by anything but us; the baud is 750 kbaud because both ends divide it exactly, `clk_pixel` at 74.25 MHz giving 99 cycles per bit and the STM32F401's 72 MHz giving 96, which no standard baud rate does and which is only available because both ends are ours. `usb1_dp` carries the keyboard's PA12 and `usb1_dn` the Tang's output to PA11. The frame is `A5 LEN payload[LEN] SUM`, where LEN is 8 and the payload is the HID boot keyboard report the keyboard already builds internally, so the keyboard side is nearly free, and SUM is the 8-bit sum of every preceding frame byte. `src/input/keylink_rx.sv` implements the synchroniser, an 8N1 receiver, the frame parser, the checksum and resynchronisation, and holds the last accepted report with a one-cycle `o_valid` alongside the diagnostic counters the other transports carry. `tests/keylink_rx_tb.sv` drives the line as the keyboard would and checks that valid frames latch, that a bad checksum and a wrong length are refused and counted without latching, and that a frame abandoned part way is counted and the link recovers; `tests/run.sh` now builds it and the whole suite passes, twenty-two tests, with the new one reporting that frames latch, malformed frames are rejected and counted, and the link recovers. The bench earned its keep immediately by catching two real faults that would have been miserable on hardware: the receiver first sampled the start bit as data bit 0, because it waited only half a bit time after the falling edge instead of skipping the start bit, which shifted every received byte, and then reloaded its bit counter with the full bit period where the reload cycle is already one of them, making the period one clock long and drifting the sampling a clock per bit until the stop-bit check walked into the next byte and rejected every byte as a framing error. The debug output made both plain, the received bytes appearing as `aa 00 04 00` rather than `a5 08 02 00` and the bit samples then measuring 22 ns apart where 20 was intended. One finding about the existing tree is recorded rather than fixed: `src/iosys/uart_fixed.v` cannot be elaborated by Verilator at all, because it instantiates a parameter-check module with a string argument, which is why nothing in the tree uses it and why no test compiles it, so the receiver was written self-contained rather than made to depend on a file no simulator can read. Nothing was deployed and the user tested nothing, because this slice is deliberately simulation-only and the hardware result belongs with the keyboard's own firmware. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 67 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Slice B is the keyboard side: a small QMK module or patch for `keyboards/keychron/k2_he` that takes PA11 and PA12 as GPIO, holds them in their idle state, and emits the frame defined here at 750 kbaud carrying the same boot keyboard report the firmware already maintains, which the user flashes to the keyboard. Slice C then brings it up on hardware with the flashed keyboard and is the first cycle in this sequence with a user test. Two things are carried from earlier: `build.tcl` still cannot build the committed `src/tang_phosphor_top.sv`, and `PMOD-003` still does not say which core's register map its socket control address belongs to.

#### Files Modified:

- src/input/keylink_rx.sv
- tests/keylink_rx_tb.sv
- tests/run.sh

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---
## 68 COMMIT Unreleased 2026-10-04T10:44:22-07:00

#### Coming From:

Unreleased 7fab9ff

#### Purpose:

Put the keyboard link's receiver into the shipping core and make it readable over the transport, so a keyboard can be tested on hardware with register reads rather than with eyes.

#### Outcome:

`keylink_rx` is now instantiated in `src/tang_phosphor_top.sv` on `usb1_dp`, displacing port 1's `usb_hid_host` because both need that pin; port 2's low-speed host and gamepad are untouched. The receiver's counters and its last accepted report were added to the debug register map at word indices 26 to 29, which are addresses `0xe8`, `0xec`, `0xf0` and `0xf4`: frames received, bad checksums, truncated frames, and a packed last report of modifiers plus the first two keycodes. Nothing already reading that map moved, because the additions precede the `default` arm and those indices were unused. The wires feeding the clk_pixel synchroniser chain are driven from the link rather than from constants, which is deliberate: entry 66 recorded that tying `joy_usb1_raw` low lets synthesis sweep `joy_usb1_meta`, after which `console138k_merged.sdc` cannot bind its first-stage false path and the build fails. `src/input/keylink_rx.sv` was added to `build-merged.tcl`. The merged build with the receiver in it meets timing at placement 3 with `clk_pixel` reaching 80.315 MHz against its 74.250 MHz constraint, down from 82.089 MHz without the link but still well clear of it, and the cost is 37 more LUTs, 111 more registers and one BSRAM fewer, the last because the receiver displaced the low-speed host's ROM. Nothing was deployed and no hardware was tested: the keyboard's own end was flashed onto the Keychron K2 HE in the same session, but the software that consumes this receiver belongs on TinyTang, where the desktop lives, so the hardware result is recorded with that work rather than this commit. This cycle also re-scoped the effort and the reasoning belongs here: the desktop runs on the BL616 and the keyboard is wired to FPGA pins exclusive to the FPGA, so keycodes have to travel keyboard, FPGA pins, nestang core, BL616, desktop; Tang-Phosphor is not on that path, and this receiver is landed here because it is the right home for a USB host should this core ever bolt one on. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 68 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The receiver is portable RTL and the next cycle carries it to TinyTang: a fourth nestang patch that instantiates it in place of port 1's host and maps the arrow keycodes, Enter and Escape into the joypad word the core already reports to the BL616 as response `0x03` every 20 ms, which needs no firmware change and is observable as pointer movement. That is followed by a real keycode channel, a new FPGA-to-BL616 response carrying the keyboard report and firmware that injects it as console input, so the desktop and shell accept typing rather than navigation alone. Two items remain carried from earlier cycles: `build.tcl` still cannot build the committed `src/tang_phosphor_top.sv`, and `PMOD-003` still does not say which core's register map its socket control address belongs to.

#### Files Modified:

- build-merged.tcl
- src/debug/debug_regs.sv
- src/tang_phosphor_top.sv

#### Status:

- Build: PASS
- Deployment: N/A
- User Test: N/A

---
## 69 COMMIT Unreleased 2026-10-05T02:35:45-07:00

#### Coming From:

Unreleased a22ec9c

#### Purpose:

Stop the resident AE350 player built from this tree from hanging before its first decode, which TinyTang found while requalifying every format on the board.

#### Outcome:

`software/rbhost/Makefile` now reserves 16 bytes where a streamed player's input would go, restoring the layout the player was qualified with in entry 43. Entry 45 had let `bench-universal` build with no `BENCH_INPUT`, and the player that produced (863748 bytes, CRC `3d762d13`, reproducible from this tree) hangs on hardware: TinyTang streamed it and a 10 s WAV through its new `phosphor` command, and the AE350 logged `stream rx 1764044 first 52494646` and then nothing, the loader stayed in RUN, the RAM bridge counted ERROR responses with the first at address `0x00000000`, and its trace showed line fills at the top of the stack, a fill at address 0, then fetches from the program entry at `0x40000000`. With the code unchanged, players padded by 0 and 32 bytes hung on every run and players padded by 16 and 48 bytes played on every run, so the trigger is the image layout and not the empty input entry; instrumenting the player with step markers moved its code and the hang disappeared, even with the data layout matched to 32 bytes, and working runs also record ERROR responses from address 0. The cause is therefore not found and this is a workaround, recorded in the Makefile comment. The player built from the fixed Makefile (`make -C software/rbhost bench-universal BENCH_NAME=resident`, 863764 bytes, CRC `ef1502ed`) has the same data layout as the qualified 16-byte case, and on the entry 68 merged image it passed TinyTang's twelve-format sweep with every sample count equal to entry 43's -- `441000` for WAV, MP3, Vorbis, AAC, ALAC, WavPack and TTA, `444240` FLAC, `440735` MP2, `442368` AC-3 and WMA, and `479688` Opus at 48 kHz -- with zero underruns and the output rate switching both ways between 44.1 and 48 kHz. The corpus was regenerated deterministically by TinyTang's `tools/make_codec_corpus.sh` from the same 10 s 440 Hz tone, with `test.wma` and `test.opus` the surviving originals; the regenerated `test.flac` is 131601 bytes, 30 under the original only because ffmpeg's bitexact mode drops the encoder tag. Two facts about the merged image surfaced on the way and are recorded in TinyTang's reference rather than changed here: its FPGA player is the raw-PCM `pcm_sink`, which takes its rate from the AE350 and parses no WAV or FLAC, so a file streamed with `cpu_mode` 0 plays as raw bytes at the last announced rate; and a restart through `0x3f0` takes effect about a millisecond after the write, so a host must not read the loader's WAIT state immediately afterwards, which TinyTang now allows for. The entry 68 image also ran the AE350 path on hardware for the first time in this cycle.

#### Next Steps:

The hang's cause remains open, and its signature is now documented: the log stopping after `stream rx`, the loader still in RUN, and bridge ERROR responses from address 0. The first step towards it is a trap handler that records `mcause`, `mepc` and `mtval` in the program result words, since today a fault wedges the AE350 silently; the ERROR responses from address 0 in working runs suggest the CPU touches address 0 in every run and only some layouts turn that into a fault. The items carried from entry 68 stand.

#### Files Modified:

- software/rbhost/Makefile

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 70 COMMIT Unreleased 2026-10-05T13:46:03-07:00

#### Coming From:

Unreleased 9e6f183

#### Purpose:

Give the merged core TinyTang's desktop layer, keyboard report and pointer mode so that it runs under TinyDesk with F12 switching between the player and the desktop, the way TinyTang's patched NES core does.

#### Outcome:

The merged top now carries the three pieces TinyTang's nestang patch series adds to the NES core. The desktop layer is `src/iosys/textdisp_wide.sv`, the 80x45 cell store with per-cell BGR5 colours, taken verbatim from TinyTang's patched nestang tree with its font `src/assets/font.vh` and attributed in `THIRD_PARTY.md`; `iosys_bl616.v` decodes commands 0x13 (cursor), 0x14 (five-byte cells, wrapping at column 80, with the cell phase reset at every frame) and 0x15 (enable), and the new `src/video/ui_desk_layer.sv` replaces the whole HDMI picture with the layer when both the layer enable and the TangCore overlay are set, threaded through `ui_hdmi_backend.sv` and `pmod_mirror_core.sv` with every other instantiation tied off. Because hdmi.sv samples the colour on the same edge as the coordinate's visibility, and `textdisp_wide` already looks four pixels ahead, the layer is selected combinationally with no added register, unlike nestang's one-pixel-late stock path. The keyboard link's receiver now runs at 281250 baud, 264 clocks per bit at 74.25 MHz, the rate TinyTang's NES core and the keyboard's 72 MHz STM32F401 (256 clocks) use, replacing 750k; iosys sends the latched boot report to the BL616 as response 0x08 (`AA 00 09 08 mods 00 k0..k5`) on change and every 100 ms, after pending replies and disk requests and before the joypad; and holding left-alt makes the arrows, Enter and Esc drive the pad bits the BL616 turns into a pointer and its left and right clicks, withholding those keys from the report. `tests/ui_desk_layer_tb.sv` checks every visible pixel of two whole frames, and of the frames around the enable changes, against a cell model with zero mismatches and fails with 287455 when the layer is delayed one pixel, `tests/iosys_debug_tb.sv` now covers the three commands, wrap, phase reset, the 0x08 frame and its ordering behind a pending reply, and `tests/run.sh` passes in full. `scripts/build-merged.sh` met timing with `clk_pixel` at 74.895 MHz against 74.25 MHz and BSRAM at 127 of 340, up from 115; the place3 image `tang_phosphor_merged.bin`, 5129930 bytes, MD5 `28536b620a1c0b324ea43c5cf08036a4`, went onto the card as `/cores/console138k/phosphortang.bin` with the previous image kept as `.bak`, alongside TinyTang firmware `aafca8e-dirty.a7d2d8d` and a `phosphor.tdsh` that leaves the desktop up. After a power cycle the user reported everything working: the track played on the core's own screen, F12 switched to TinyDesk and back both during the track and after it ended without the menu core appearing, typing reached TinyDesk, and left-alt drove the pointer. The core-syntax audit required by this entry was performed against `.ai/core-syntax.md`, which was re-read; `.ai/core.md` was not read, as TinyTang's handoff directs, and `git diff` confirms it unchanged; the complete `.ai/` diff adds only this entry, which is number 70 of 70 in the active log.

#### Next Steps:

The layer's path leaves `clk_pixel` under 1% of slack, so any further logic on the HDMI path should be checked against timing first. The work continues in TinyTang with a background playback task on the BL616 in place of the blocking `phosphor play` and then a Phosphor app in TinyDesk, which may want Phosphor-side registers for now-playing state. The resident player's layout hang from entry 69 remains open, and the `.bak` core on TinyTang's card can be removed once the user is satisfied.

#### Files Modified:

- THIRD_PARTY.md
- build-merged.tcl
- build-pmod.tcl
- src/ae350/ae350_ddr3_top.sv
- src/ae350/ae350_smoke_top.sv
- src/assets/font.vh
- src/input/keylink_rx.sv
- src/iosys/iosys_bl616.v
- src/iosys/textdisp_wide.sv
- src/pmod_mirror_core.sv
- src/pmod_mirror_top.sv
- src/tang_phosphor_top.sv
- src/video/ui_desk_layer.sv
- src/video/ui_hdmi_backend.sv
- tests/iosys_debug_tb.sv
- tests/keylink_rx_tb.sv
- tests/run.sh
- tests/ui_desk_layer_tb.sv
- tests/ui_mirror_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 71 COMMIT Unreleased 2026-10-06T12:41:41-07:00

#### Coming From:

Unreleased 4936ed1

#### Purpose:

Make the PMOD OLED work under TinyTang by separating the merged core's stream-routing bit from the socket control word it shared, and by having TinyTang declare the sockets when it loads the core.

#### Outcome:

The OLED was dark under TinyTang for two reasons. Nothing declared the sockets, because the merged core powers up with both released (entry 55) and TinyTang has no `/tang.ini` parser, and even a hand declaration did not survive a track, because `cpu_mode` was bit 0 of the socket control word at `0xc0`: entry 55 placed the mirror block at `0xc0` on top of the `cpu_mode` register that already lived there, so `debug_regs` and `tang_phosphor_top` both decoded that write, and TinyTang's `ae350_play.cpp` writing `0xc0 = 1` for every track set hold and released both sockets, while a declaration such as `0x2410` cleared `cpu_mode` and would have sent a stream raw into `pcm_sink`. `cpu_mode` now lives in `src/debug/debug_regs.sv` at `0xa8`, the first of the unused words `0xa8`-`0xbc`, readable there, with the top taking it from an explicitly declared wire, and the register ABI at `0x04` reads 1.8; `scripts/play_stream.py`, `scripts/mp3_single_cable.py` and `tools/ae350_run.py` write `0xa8`, and `docs/debug-registers.md` now documents `0xa8`, the mirror and keyboard-link words `0xc0`-`0xf4`, the AE350 window at `0x4000`, and how the merged core's `pcm_sink` reads differently at `0x64`, `0x6c`, `0x30`, `0x8c` and `0x90` (TinyTang's `PHOS-009`). The new `tests/debug_regs_tb.sv`, registered in `tests/run.sh`, checks that each word moves only its own fields, that both read back and that reset clears both, and it reports four failures against a copy with the old aliasing restored; the full suite passes. `scripts/build-merged.sh` met timing only at placement 3, `clk_pixel` 74.435 MHz against 74.250, while placements 0, 1 and 2 failed at 72.208, 70.601 and 73.868 MHz and placement 4 was stopped at the user's direction and is treated as failed; no failing path touches `debug_regs` or `cpu_mode`, all of them being entry 70's desk-layer read address from `hdmi_tx`'s `cx` and the keyboard link's keycodes into `tangcore_io`'s pointer decode and transmit arbiter, with one `tangcore_io` stream-offset path, and placement 3's worst setup slack is +0.034 ns on the keyboard path, so entry 70's single-seed result had hidden a design that closes at one seed of four. The placement 3 image, 5031936 bytes, MD5 `2a7591833d04640aed715ce6d7d9db7e`, CRC-32 `10340a55`, went onto TinyTang's card as `/cores/console138k/phosphortang.bin` through its guarded `tinytang_put.py`, with entry 70's image kept as `phosphortang.bin.bak`. In the same approved cycle TinyTang's `ae350_play.cpp` was changed to select the CPU at `0xa8` on every play and to refuse a core older than ABI 1.8, and its `phosphor.tdsh` now declares `0xc0 = 0x2410`, overridable with `PMOD`, as a stopgap for the parser; that firmware, `f8d6fdf-dirty.43c548f`, was flashed and confirmed by `platform` after the power cycle in which the user seated the OLEDrgb in PMOD0 and the encoder in PMOD1, and the TinyTang change is logged in its own repository. On hardware `phosphor.tdsh` loaded the core as core 80 and declared the sockets, the ABI read `0x00010008`, `0xa8` read 1 and `0xc0` read `0x2410` before, during and after two plays of `/music/test.mp3`, each completing at 441000 samples at 44.1 kHz with zero underruns, the panel frame counter at `0xd8` advanced throughout, and the source and panel signatures both read `0x76491800`, the modelled menu frame. The user confirmed the OLED lit with the cell frame and the tone heard perfectly. A record for the merged map's socket control and stream routing was added to `.ai/core-reference.md` after the bring-up map's `0x10` record, which is left as written. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 71 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Restore `clk_pixel` margin across placements before anything else is added to the merged netlist: register the keyboard link's keycode comparisons ahead of `tangcore_io`'s pointer decode and arbiter, and shorten the desk layer's read-address path from `hdmi_tx`'s `cx`, then sweep placements 0 to 4 and compare each against this cycle's figures. The `/tang.ini` parser in TinyTang should replace `phosphor.tdsh`'s fixed declaration. The resident player's layout hang from entry 69 and `build.tcl`'s divergence from the committed top remain open, and the `.bak` core on TinyTang's card can be removed once the user is satisfied.

#### Files Modified:

- docs/debug-registers.md
- scripts/mp3_single_cable.py
- scripts/play_stream.py
- src/debug/debug_regs.sv
- src/tang_phosphor_top.sv
- tests/debug_regs_tb.sv
- tests/run.sh
- tools/ae350_run.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 72 COMMIT Unreleased 2026-10-06T13:00:12-07:00

#### Coming From:

Unreleased b7ec367

#### Purpose:

Restore `clk_pixel` margin in the merged core so that at least three of placements 0 to 3 meet timing, after entry 71 found the design closing at one placement of four.

#### Outcome:

Entry 71's sweep failed at placements 0, 1 and 2 on three path groups, all added by entry 70 or earlier and none by entry 71, and each now has one register stage. The keyboard link's keycodes went through the six-compare left-alt pointer filter in `src/tang_phosphor_top.sv` and then `iosys_bl616`'s 56-bit report-changed compare into the bottom of its transmit arbiter in one cycle; the filtered report and modifiers are now registered in the top, and `src/iosys/iosys_bl616.v` keeps the compare as a registered `kbd_changed`, one clock stale, which cannot send twice because a send reloads `kbd_timer`. `src/iosys/textdisp_wide.sv` computed the desk layer's look-ahead, its wrap test against `frame_width` and the row multiply in front of `raddr_r`; the look-ahead coordinate and its on-screen flag are now a stage of their own and `LAT` is 5, and `tests/ui_desk_layer_tb.sv` passes every visible pixel at 5 and fails at 4, so the alignment PROT-009 in TinyTang's reference warns about is held. The 32-bit `stream_offset_rx == stream_expected_offset` compare in front of the stream acceptance chain and its error counter is a registered `stream_offset_match`, safe because the offset arrives in the header and the expected offset only moves when a frame drains, which the host waits on before sending the next. The full suite passes. `MERGED_PLACE_OPTIONS="0 1 2 3" scripts/build-merged.sh` met timing at all four placements, `clk_pixel` reaching 78.431, 79.276, 82.095 and 89.052 MHz against entry 71's 72.208, 70.601, 73.868 and 74.435, with worst setup slack across every clock of +0.718, +0.854, +0.703 and +2.004 ns, none on a fixed path; placement 3's worst path is now inside the DDR3 IP, so the pinned seed stays 3 and placement 4 was not built, at the user's direction. The placement 3 image, 5034698 bytes, MD5 `81de63b48ebf610f0d4db6b6b3973b0a`, CRC-32 `78fe7d2c`, went onto TinyTang's card as `/cores/console138k/phosphortang.bin` with entry 71's image kept as `phosphortang.bin.bak`; with TinyTang firmware `f8d6fdf-dirty.43c548f` unchanged, `phosphor.tdsh` loaded it as core 80, the ABI read 1.8, `0xa8` read 1, `0xc0` held `0x2410`, `/music/test.mp3` completed at 441000 samples with zero underruns through the new offset match, and the source and panel signatures both read `0x76491800`. The user reported all tests passing, the OLED, the desk layer under F12 and the Bluetooth keyboard and mouse included; the wired keyboard link was not exercised on hardware because the user no longer uses that keyboard, so the keyboard-path change rests on `tests/iosys_debug_tb.sv`, which covers the report frame and its ordering. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 72 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The design now meets timing at every placement tried with at least +0.7 ns of setup slack, so new logic can be added to the merged core again, with each addition checked by the same four-placement sweep against this entry's figures. The `/tang.ini` parser in TinyTang, the resident player's layout hang from entry 69 and `build.tcl`'s divergence from the committed top remain open, and the `.bak` Phosphor core on TinyTang's card can be removed once the user is satisfied.

#### Files Modified:

- src/iosys/iosys_bl616.v
- src/iosys/textdisp_wide.sv
- src/tang_phosphor_top.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 73 COMMIT Unreleased 2026-10-06T17:10:58-07:00

#### Coming From:

Unreleased 90e386c

#### Purpose:

Make songs start sooner by playing the resident AE350 player's decoded audio while it decodes, and, when rebuilt players stopped starting tracks, find out why before shipping one.

#### Outcome:

The delay was measured on a 3236120-byte MP3: 13.34 s to send the 863764-byte player and the file, then 17.92 s decoding the whole 199 s track into DDR3 before the first sample, because `software/rbhost/host/platform_ae350.c` receives, decodes and plays strictly in sequence and returns after each track, so TinyTang resends the player every song; a long track whose decode exceeds TinyTang's 30 s start timeout is reported as failed. The first of three planned cycles changes the player's output file layer to hand PCM to the play stream as the codec writes it, and when a build of it played, playback began as soon as the send finished; but rebuilt players repeatedly received the file and never decoded it -- the log stopping after `stream rx`, result word 7 holding the input size, the loader in RUN with no trap -- which is the failure entry 69 had worked around with padding. The investigation kept the player unchanged where it could and moved instrumentation into the boot ROM and small probe programs run through TinyTang in place of `resident.tpi`. `software/ae350/programs/busfault` showed a load from address 0 traps precisely (`mcause` 5, `mepc` the load, `mtval` 0) and that speculative fetches at 0 produce bridge ERRORs without trapping, so the address-0 ERRORs in failing and working runs are not the fault; `triggers` and `watch` showed the A25 has at least seven debug triggers whose chained address matches fire in M-mode only with `tcontrol.mte` set and report the exact instruction. `software/ae350/boot/start.S` and `boot.c` now clear triggers 0-5 at reset, enter programs through `boot_call`, which poisons the stack below the loader's frame with `0xbadbad00`, watches the loader's frames for loads and stores and boot ROM code for execution while the program runs, logs `run` per call, and records `ra` and `sp` in result words 11 and 12 on a trap (`software/ae350/include/ae350.h`). None of these fired on a failing run and the log showed one call per image, ruling out a read or write of the loader's frame, re-entry into the boot ROM, a second call, and stale stack values; a heap fill test was confounded by layout. Layout experiments then pinned `.data`, `.bss`, the entry stack and the data after the input slot to 64-byte boundaries, and showed the outcome follows absolute addresses with no padding rule, then that it is not fixed per build: the same images failed every run before a power cycle and played after one, and on the next boot the default streaming build failed the format sweep on its first three formats. The streaming change is therefore parked as `software/rbhost/parked/0001-play-while-decoding.patch` with a README, the layout experiments were reverted, and the qualified player (863764 bytes, CRC-32 `ef1502ed`) is back on the card as `/ae350/resident.tpi` and played to completion, while the open fault and the trigger facts are recorded in `.ai/core-reference.md`. The boot ROM change rebuilt the merged core: `MERGED_PLACE_OPTIONS="0 1 2 3"` met timing at placements 0, 1 and 3 with `clk_pixel` at 78.633, 76.248 and 80.036 MHz and failed at placement 2 at 69.934 MHz, worst setup -0.831 ns on `tangcore_io`'s receive path into the desk layer's colour latch and the bad-request counter, which this cycle did not touch; the placement 3 image, 5031936 bytes, MD5 `3d6de6d3195f30597ce0c14cfaff7d66`, CRC-32 `eb1935c2`, is `/cores/console138k/phosphortang.bin` on TinyTang's card with entry 72's image as `phosphortang.bin.bak`, and its boot ROM is byte-identical to this commit's. The user saw no track play from the streaming build, so the cycle's purpose is not met. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 73 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The start failure is flagged and left until it shows itself more clearly, at the user's direction; when it is taken up, the untested leads are the RAM bridge's burst read path, DDR3 margin, and AE350 CPU debug through its JTAG port, which `src/ae350/ae350_soc.sv` ties off. Until then no rebuilt resident player ships, so faster starts, a resident player loop and gapless playback wait on it. Placement 2's `tangcore_io` receive path is the next `clk_pixel` target.

#### Files Modified:

- software/ae350/boot/boot.c
- software/ae350/boot/start.S
- software/ae350/include/ae350.h
- software/ae350/programs/busfault/main.c
- software/ae350/programs/triggers/main.c
- software/ae350/programs/watch/main.c
- software/rbhost/parked/0001-play-while-decoding.patch
- software/rbhost/parked/README.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: FAIL

---

## 74 COMMIT Unreleased 2026-10-06T17:32:30-07:00

#### Coming From:

Unreleased d500bb7

#### Purpose:

Try the parked play-while-decoding player once against the normal format sweep from a cold boot, and when it failed, revert entry 73 entirely and requalify the entry 72 core and the qualified player.

#### Outcome:

The parked `software/rbhost/parked/0001-play-while-decoding.patch` was applied to `d500bb7` and built with `make -C software/rbhost bench-universal BENCH_NAME=resident`, giving an 863924-byte player with CRC-32 `6a9b37eb`, which went onto TinyTang's card as `/ae350/resident.tpi` on the entry 73 core. After the user power-cycled the Tang, TinyTang's `tools/phosphor_format_sweep.py` failed on its second file: `phosphor status` reported `/music/test.flac` sent in 3246 ms, 0 samples and the loader at `0x00000003`, the same start failure entry 73 recorded, so a power cycle alone does not clear it and entry 73's suggestion that the test setup was the whole cause does not hold. The user judged entry 73 not worth keeping, so `d500bb7`'s engineering changes were reverted: the boot ROM's trigger clearing, stack poisoning, frame watches and trap context in `software/ae350/boot/boot.c`, `software/ae350/boot/start.S` and `software/ae350/include/ae350.h`, the `busfault`, `triggers` and `watch` probe programs, and the parked patch and its README, all of which remain at `d500bb7`. The tree outside `.ai` is now identical to `90e386c`, and entry 73's log entry and reference records were kept as history, with the two records in `.ai/core-reference.md` corrected for the revert and the cold-boot failure. The player rebuilt from the reverted tree is byte-identical to the qualified one, 863764 bytes with CRC-32 `ef1502ed`. `MERGED_PLACE_OPTIONS="3" scripts/build-merged.sh` met timing with `clk_pixel` at 89.052 MHz and reproduced entry 72's image exactly, 5034698 bytes with MD5 `81de63b48ebf610f0d4db6b6b3973b0a`. That image, loaded from `phosphortang.bin.bak` after a second power cycle, and the qualified player passed the full sweep, all thirteen plays matching entry 43's sample counts with zero underruns and the rate switching both ways between 44.1 and 48 kHz. The verified rebuild was then installed as `/cores/console138k/phosphortang.bin`, so it and `.bak` are now the same entry 72 image. The OLED was dark at first only because the core was loaded with a bare `tangload` rather than through `phosphor.tdsh`, so nothing declared the sockets, and `phosphor poke 0xc0 0x2410` lit it. The user confirmed the OLED on and every track sounding good. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 74 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

The user wants track load time reduced next. Entry 73 measured 13.34 s to send the player and a 3.2 MB MP3, and 17.92 s decoding the whole track before the first sample. Any approach that needs a rebuilt resident player meets the open start failure recorded in `.ai/core-reference.md`, so each proposal should say whether it needs a player rebuild and be qualified by the twelve-format sweep alone. Entry 73's placement 2 timing failure belonged to the reverted netlist, and the restored core is entry 72's, which met timing at placements 0 to 3. The `/tang.ini` parser in TinyTang and `build.tcl`'s divergence from the committed top remain open.

#### Files Modified:

- software/ae350/boot/boot.c
- software/ae350/boot/start.S
- software/ae350/include/ae350.h
- software/ae350/programs/busfault/main.c
- software/ae350/programs/triggers/main.c
- software/ae350/programs/watch/main.c
- software/rbhost/parked/0001-play-while-decoding.patch
- software/rbhost/parked/README.md

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 75 COMMIT Unreleased 2026-10-06T18:00:42-07:00

#### Coming From:

Unreleased c1af2db

#### Purpose:

Compare the AE350 setup with Tang-PSX's and give AE350 programs a way to request byte ranges of a file from the BL616 on demand, as Tang-PSX requests disc sectors, proved with a probe program before any player depends on it.

#### Outcome:

The user approved a three-step plan to replace sending each whole file before decoding with on-demand reads, playing while decoding and a resident gapless player, modelled on Tang-PSX's `disc_request` path, which reads only the sectors a game asks for over the same link, and informed by the BL616 CHD streaming in `rtissera/firmware-bl616` (`core/pcecd.cpp`, Apache-2.0), which decompresses CHD on the BL616 and streams sectors and CD audio over the UART with DMA overlap at about 2 Mbaud. The step 0 comparison changed no files. Tang-PSX writes back the whole data cache before calling a program where this boot ROM only executes `fence rw, rw` and `fence.i`, but Tang-PSX's JIT relies on that fence pair alone and its reference AE350-004 records that it is sufficient, so the difference is not a likely cause of the resident player start failure. This core's RAM bridge is its own SystemVerilog design rather than Tang-PSX's hardware-proven LiteX bridge; its randomized testbench covers BUSY, IDLE, out-of-range errors and both clock domains, and reading it found nothing, so it remains an open lead, as does this core keeping the loader's stack, which programs run on, in DDR3 where Tang-PSX keeps it in fabric RAM. The start failure is narrower than entry 73 recorded: a failing player stops after logging `stream rx` and before `rbhost.c` prints its `Codec:` line, so it stalls before or inside metadata parsing over the whole-file input, which the on-demand design replaces. For step 1, `software/ae350/include/ae350_request.h` defines a mailbox in USER(13..15), sequence, offset and length, which the BL616 reads at `0x4074` to `0x407c` and answers with one stream session per request, and provides inline request and receive helpers with a bus-clock timeout; `docs/debug-registers.md` documents it. The probe `software/ae350/programs/fileread`, 2552 bytes as a TPI, requests six ranges of the corpus `test.wav` and publishes each CRC-32 and byte count. TinyTang's new `phosphor run` command, recorded in TinyTang's log, loaded it on the entry 72 core and served the requests from the card. All six ranges arrived intact, the AE350's CRC equalling both the CRC TinyTang computed while sending and a CRC of a copy regenerated on the PC with TinyTang's `tools/make_codec_corpus.sh` commands: 44 bytes `8e6da437`, 65536 bytes `fa070481`, 100001 unaligned bytes `aeabcb44`, the last 1000 bytes `0fd0a46e`, a range running past the end correctly returning 10 bytes `3b14b2d1`, and the whole 1764044-byte file `0326bacf` in 5179 ms, about 340 KB/s, with a request of a few bytes taking about 10 ms in total. The probe returned `0x600d0000` with no failures and the loader returned to WAIT; the user accepted the result. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 75 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Step 2 changes the resident player to read its input through the mailbox with read-ahead instead of receiving the whole file first, and to play decoded audio as the codec produces it from a buffer in DDR3 that keeps `pcm_sink`'s 2048-sample FIFO fed, with TinyTang serving the requests during playback; it is qualified by the twelve-format sweep and measured by time to first sample against entry 73's 31 s for a 3.2 MB MP3. The player must stop clearing USER(13..15) at start, and its bridge counters in USER(10..12) stay where they are. Step 3, a resident player with gapless track changes, follows.

#### Files Modified:

- docs/debug-registers.md
- software/ae350/include/ae350_request.h
- software/ae350/programs/fileread/main.c

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 76 COMMIT Unreleased 2026-10-06T18:24:39-07:00

#### Coming From:

Unreleased bae67ec

#### Purpose:

Make the resident player read its input on demand through the file-request mailbox and play as it decodes, so a track starts after its first chunks instead of after the whole file has been sent and decoded.

#### Outcome:

`software/rbhost/host/platform_ae350.c` gained an on-demand input mode, selected by `BENCH_STREAM=2` and built by the new `make -C software/rbhost bench-ondemand` target, while `bench-universal` keeps the whole-file mode. The player first sends a request of length 0, which TinyTang answers with the file's size as a four-byte session, a convention now documented in `software/ae350/include/ae350_request.h` and `docs/debug-registers.md`. It then fills `INPUT_BASE` in 64 KiB chunks at the file's own offsets, requesting a chunk a read is waiting for first and otherwise the next missing chunk in order, draining each answer from the stream FIFO at most 256 entries at a time and asking again after two seconds of silence. `_read` waits only for the chunks it needs, `_fstat` now reports the size, and USER(13..15) are no longer cleared at start. With `BENCH_PLAY=1` the output WAV is written into the 256 MiB output buffer as a ring and its PCM is handed to the play stream whenever the stream reports room, never waiting on it, starting half a second in or when the output closes; every `_read` wait and `_write` services both input and output, playback finishes before the output CRC is computed so the CRC cannot starve it, and the CRC reads 0 once the ring has wrapped. The on-demand player is 865816 bytes with CRC-32 `c7a89035`, and the qualified whole-file player was rebuilt from `bae67ec`'s sources byte-identical at 863764 bytes and CRC-32 `ef1502ed`. On TinyTang's card the on-demand player replaced `/ae350/resident.tpi`, the qualified one was kept as `/ae350/resident-qualified.tpi`, and TinyTang firmware `3d86aea-dirty.34645d2`, recorded in TinyTang's log, served the requests during playback. On the entry 72 core the twelve-format sweep passed all thirteen plays with zero underruns and the rate switching both ways between 44.1 and 48 kHz, every sample count equal to entry 43's except FLAC, which now presents exactly 441000 samples where entry 43 recorded an unexplained 444240; the likely but unproven cause is that the whole-file path counted the input in whole words, padding the 131601-byte file by three bytes, where the on-demand path uses the exact size. The ten-second files started 2723 ms after the play, 8 ms after the 2715 ms player send. Entry 73's 3236120-byte `Fleetwood Mac - Landslide.mp3` started 2733 ms after the play against entry 73's 31 s, and played its full 3:19, 8796143 samples, with zero underruns. The user heard the sweep and the track play correctly and accepted the result. The required `.ai` core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged, validated this entry as number 76 of 100 with exactly six sections, and confirmed that no settled history was rewritten.

#### Next Steps:

Step 3 keeps the player resident between tracks, removing the roughly 2.7 s player send that is now nearly all of a track's start, and plays consecutive tracks without a gap by requesting the next track's first chunks before the current one ends; a sample-rate change between tracks needs boundary handling in `pcm_sink`, whose boundary outputs are tied to 0. The `/tang.ini` parser in TinyTang follows step 3, prompted by the user's report that the OLED shows garbage after a cold power-up before any socket declaration, which is consistent with the released PMOD pins floating with no pull while the panel misses a clean reset, though that cause is not yet confirmed. The resident player start failure of entries 69, 73 and 74 has not appeared with the on-demand player.

#### Files Modified:

- docs/debug-registers.md
- software/ae350/include/ae350_request.h
- software/rbhost/Makefile
- software/rbhost/host/platform_ae350.c

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 77 COMMIT Unreleased 2026-10-06T21:37:53-07:00

#### Coming From:

Unreleased df24687

#### Purpose:

Qualify stereo analog output through a Digilent Pmod I2S2 with an exact 48 kHz master clock and independently checked test tones.

#### Outcome:

The merged core now supports output-only PMOD personality 5, routed through the existing socket permutation, with a 1 kHz left square wave and a 2 kHz right square wave at one-quarter full scale; the ADC row remains released, and normal player and HDMI audio remain on their existing timebase. Two revision-C PLL recipes produce 24 MHz from the 50 MHz oscillator at VCO 1200 MHz, then 12.288 MHz at VCO 768 MHz with the supported 62.5 output divider, inside DS1239's 650–1300 MHz limits. Gowin's automatic clock report instead shows the integer-divider frequency, so the added clock probe counts actual MCLK edges over 7,425,000 pixel clocks and publishes the count at `0xf8` and synchronized lock/measurement status at `0xfc`; on hardware status read 7 and repeated counts were exactly `0x0012c000`, confirming nominal 12.288 MHz. `i2s_tx` latches coherent stereo pairs, changes data at falling bit-clock edges and presents the I2S delay bit followed by 16 significant bits and zero padding in 32-bit channel slots. The full simulation suite passed, including serial decoding, clock measurement, tone periods, withdrawal, both sockets, orientation and clock loss; shifting the transmitter's MSB launch one bit made the serial bench fail, and the new register reads passed their focused bench. The diagnostic was built from committed `df24687` plus this cycle's changes, excluding the checkout's pre-existing player, bridge and JTAG experiments. The four-placement sweep met setup and hold timing at 0 and 3, with pixel Fmax 74.801 and 86.641 MHz, while 1 failed on the DDR3 controller clock domain and 2 on the existing HDMI packet path; placement 3 was deployed. PRIMARY clocks are now 8/8 and PLLs 7/12, so further audio clock additions must account for routing capacity. The 5,063,680-byte image, MD5 `458ff2611ef245b8acbad28a1a99984d`, SHA-256 `de2907e6098f419b256b79c974d8758a516a39c0a743f2112db23e9140dce52f`, was uploaded separately as `/cores/console138k/phosphortang-i2s2-tone.bin` alongside `/scripts/i2s2-tone.tdsh`, leaving the qualified playback image in place. After the user powered down, replaced the OLED and encoder with the I2S2 in PMOD0, set JP1 to SLV and powered up, the script loaded core 80 and declared `0xc0 = 0x50`; clock status and count remained correct, and the user reported perfect stereo output. The Cirrus converter datasheets and device-specific Gowin clock limits were added to the reference, including corrections to the Digilent manual's ADC ratio and MCLK units. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete staged `.ai` diff, confirmed `.ai/core.md` unchanged and all settled entries retained, and validated this entry as number 77 of 100 with exactly six sections; pre-existing log trimming and other unrelated changes remain outside this commit.

#### Next Steps:

Connect normal PCM playback to the I2S2 after establishing one sample cadence shared by the player, HDMI and I2S, and add the 44.1 kHz clock path and muted rate transitions before qualifying the twelve-format sweep on analog output. The primary clock resources are full, so clock sharing or routing must be resolved within that design. Line input is deferred, and the OLED and encoder are on hold at the user's direction. The earlier resident/gapless player and JTAG work remains uncommitted and separate from this qualified output diagnostic.

#### Files Modified:

- build-merged.tcl
- docs/debug-registers.md
- docs/i2s2-bringup.md
- src/audio/i2s_tx.sv
- src/audio/i2s_clock_probe.sv
- src/boards/console138k_merged.sdc
- src/debug/debug_regs.sv
- src/pll/pll_i2s2_ref.mod
- src/pll/pll_i2s2_ref.v
- src/pll/pll_i2s2_audio.mod
- src/pll/pll_i2s2_audio.v
- src/pmod/pmod_i2s2_tone.sv
- src/pmod_mirror_core.sv
- src/pmod_mirror_top.sv
- src/tang_phosphor_top.sv
- tests/debug_regs_tb.sv
- tests/i2s_tx_tb.sv
- tests/run.sh
- tests/ui_mirror_tb.sv
- tools/gen_i2s2_plls.sh
- tools/i2s2-tone.tdsh

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---

## 78 COMMIT Unreleased 2026-10-06T22:05:43-07:00

#### Coming From:

Unreleased 17ce020

#### Purpose:

Play normal stereo PCM through the I2S2 at native 44.1 and 48 kHz using one sample cadence shared with HDMI.

#### Outcome:

The merged core now fetches coherent PCM pairs through a held-data toggle handshake, emits them through I2S and returns the same pair and frame pulse to HDMI; stream epochs reject canceled prefetched samples and pause stops FIFO consumption. The existing audio PLL switches under reset between 12.288 and 11.2896 MHz using supported fractional dividers, with 0.5 ms of zeros before switching and 300 ms of zeros after lock; no further PLL or primary clock route was added. ABI 1.9 adds active-rate, ready and settling bits to `0xfc`. The full simulation suite passed, including sample sequence, both rates, pause, cancellation and lock recovery, and a further HDMI ACR check passed N/CTS at both rates. The four-placement build used committed `17ce020` plus only this cycle's changes; placement 2 alone met setup and hold, with pixel Fmax 82.572 MHz and zero violated endpoints, while PRIMARY remains 8/8 and PLL 7/12. Its 5,095,424-byte image, SHA-256 `d72e5701d2484605e9166926f04b7121fa3e6e08d78b4e5aa5aa1f022efe16b4`, was deployed separately as `/cores/console138k/phosphortang-i2s2-play.bin`, with `/scripts/i2s2-play.tdsh` declaring PMOD0 personality 5 and leaving PMOD1 released. TinyTang firmware `fd2933e-dirty.d2b8b07` used the unchanged on-demand player; the user reported perfect WAV output. All twelve formats and the final WAV passed with zero underruns and entry 76's sample counts; repeat Opus/WAV checks measured exactly 1228800 and 1128960 MCLK edges per 100 ms, with status `0x1f` and `0x17`. `tools/i2s2_format_sweep.py` makes those checks repeatable, and `docs/i2s2-bringup.md` records the artifact and evidence. The core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete staged `.ai` diff, confirmed core.md unchanged and settled history retained, and validated entry 78 of 100 with exactly six sections; the pre-existing log trimming and player, bridge and JTAG work remain outside this commit.

#### Next Steps:

The I2S2 output playback cycle is complete. Line input is deferred and the OLED and encoder remain on hold. Resume the separate resident/gapless player work only in a subsequent approved cycle, using this shared cadence and accounting for the muted rate transition.

#### Files Modified:

- build-merged.tcl
- docs/debug-registers.md
- docs/i2s2-bringup.md
- src/audio/i2s_clock_control.sv
- src/audio/i2s_playback.sv
- src/audio/pcm_sink.sv
- src/debug/debug_regs.sv
- src/pll/pll_i2s2_audio.mod
- src/pll/pll_i2s2_audio.v
- src/pmod_mirror_core.sv
- src/pmod_mirror_top.sv
- src/tang_phosphor_top.sv
- tests/debug_regs_tb.sv
- tests/i2s_playback_tb.sv
- tests/pcm_sink_tb.sv
- tests/run.sh
- tests/ui_mirror_tb.sv
- tools/i2s2-play.tdsh
- tools/i2s2_format_sweep.py

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---
