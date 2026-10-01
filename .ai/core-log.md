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
