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
