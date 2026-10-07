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

## 79 COMMIT Unreleased 2026-10-06T23:42:36-07:00

#### Coming From:

Unreleased 1941765

#### Purpose:

Implement the approved 512x512 stereo XY O-Scope with selectable persistence and glow, and preserve its terminal timing failure for agent handoff.

#### Outcome:

The merged I2S2 backend now observes the shared emitted PCM pair with a genuine-sample presence tag, reconstructs the visual stream at 2x, queues connected XY lines and derives eight-bit display brightness from a nine-bit valid/timestamp plane; the 720x720 HDMI square, selectable trails and glow precede desktop composition, and ABI 1.10 adds scope controls and diagnostics at `0xac` through `0xb8`. The full regression suite passed, including independent full-raster comparison, overload discontinuities, timestamp wrap, shared I2S/HDMI audio at both native rates and real zero-PCM tagging; the RAM wrapper also passed against Gowin's DPX9B primitive model. The isolated build used committed `1941765` plus scope changes only, excluding earlier player/bridge/JTAG experiments. Gowin did not define `SYNTHESIS`, so the first attempts selected unsupported inferred read-before-write RAM; the final wrapper defaults to explicit normal-write DPX9B, with `SCOPE_RAM_BEHAVIORAL` for portable benches. Placements 0 and 1 completed but failed the 74.25 MHz pixel constraint at 43.082 and 46.961 MHz, with setup TNS -79565.688 and -67710.695 ns. The critical path is timestamp brightness conversion into the fabric-register line cache; final resources are 24352 logic, 27596 FF, 257/340 BSRAM, 6/298 DSP, PRIMARY 8/8 and PLL 7/12. At the user's direction, placements 2 and 3 were terminated while routing and are assumed failed for handoff, with no measured final timing verdict. The proposed brightness pipeline and explicit lane-cache rewrite were not implemented. Six 48 kHz shape WAVs and a 44.1 kHz circle were uploaded, but no scope image or launcher was deployed and no hardware or user test ran. `docs/oscope-handoff.md` records the evidence and recovery actions; qualified playback remains entry 78. The core-syntax audit re-read core.md and core-syntax.md, inspected the complete staged .ai diff, confirmed core.md unchanged and settled committed history retained, and validated entry 79 of 100 with exactly six sections; pre-existing local log trimming and unrelated work remain outside this commit.

#### Next Steps:

Resume only when the user requests it. Pipeline the age, trail ramp, quadratic brightness and cache-publication path while carrying matching row/group tags and valid strobes, and split the scan-line caches into explicit fixed-row/lane memories to improve Gowin inference and fanout. Verify the resulting raster timing and memory mapping, rerun affected simulations and required regression checks after source changes, then rebuild from a clean scope checkout excluding the preserved experiments. Deploy only an image meeting setup and hold timing, run the fixture and twelve-format tools, and obtain hardware acceptance before qualifying the visualizer. Keep the existing I2S2 playback image, firmware and on-demand player; OLED, encoder, line input and Siglent measurements remain deferred.

#### Files Modified:

- THIRD_PARTY.md
- build-merged.tcl
- docs/debug-registers.md
- docs/oscope-plan.md
- docs/oscope-handoff.md
- src/audio/i2s_playback.sv
- src/debug/debug_regs.sv
- src/pmod_mirror_core.sv
- src/pmod_mirror_top.sv
- src/tang_phosphor_top.sv
- src/video/ui_hdmi_backend.sv
- src/visualizers/scope_phosphor_ram.sv
- src/visualizers/scope_reconstruct.sv
- src/visualizers/scope_xy.sv
- tests/debug_regs_tb.sv
- tests/i2s_playback_tb.sv
- tests/run.sh
- tests/ui_mirror_tb.sv
- tests/scope_ram_tb.sv
- tests/scope_reconstruct_tb.sv
- tests/scope_xy_tb.sv
- tools/check_scope_ram.sh
- tools/i2s2_format_sweep.py
- tools/make_scope_fixtures.py
- tools/oscope.tdsh
- tools/oscope_check.py

#### Status:

- Build: FAIL
- Deployment: NOT RUN
- User Test: NOT RUN

---

## 80 COMMIT Unreleased 2026-10-07T00:06:19-07:00

#### Coming From:

Unreleased 76d5c79

#### Purpose:

Commit the user's intentional shortening of the active log to entries 67 to 79 with a conforming archive of the full log, so that future agents recover project context from those entries only.

#### Outcome:

The user shortened the active `.ai/core-log.md` to entries 67 to 79 after entry 76 to limit the history a resuming agent works from, and placed an uncompressed copy of the log as it stood at `df24687`, entries 1 to 76, in `.ai/archived_logs/core-log_2026-10-06.md`. That copy was not a `tar.gz` archive, the trim was never committed, and entries 77, 78 and 79 each committed only their own additions and recorded the trimming as outside their commits, so the repository still held entries 1 to 79 while the local log held 67 to 79. The uncompressed copy was removed and replaced by `.ai/archived_logs/core-log_2026-10-07T000619-0700.tar.gz`, which contains the complete log as committed at `76d5c79`, entries 1 to 79, verified byte-identical to that commit's `.ai/core-log.md`; the archive was created without being consulted. Entries 67 to 79 remain in the active log unchanged and byte-identical to `76d5c79`, and this commit removes entries 1 to 66 from it. This is a user-directed trim, not the 100-entry rollover, and the archival procedure in `.ai/core.md` and `.ai/core-syntax.md` is unchanged; numbering continues from the highest entry present, and entries 1 to 66 and the archive are not to be inspected or cited without user approval. Nothing was built, deployed or tested. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete `.ai` diff, confirmed that `.ai/core.md` is unchanged and that no retained entry was rewritten, and validated this entry as number 80 with 14 entries in the active log and exactly six sections.

#### Next Steps:

Entry 79's next steps stand: resume the O-Scope only when the user requests it, by pipelining the brightness path and splitting the scan-line caches into explicit lane memories as `docs/oscope-handoff.md` describes, then deploying only an image that meets setup and hold timing. Entry 78's I2S2 playback image, TinyTang firmware and on-demand player remain the qualified baseline. The working tree's uncommitted resident-player, RAM bridge, AE350 JTAG, `chainload`, `wbrace`, OpenOCD and Rockbox submodule changes remain unqualified and outside this commit.

#### Files Modified:

None.

#### Status:

- Build: N/A
- Deployment: N/A
- User Test: N/A

---

## 81 COMMIT Unreleased 2026-10-07T02:02:46-07:00

#### Coming From:

Unreleased eb243a7

#### Purpose:

Close the O-Scope's pixel-clock timing failure recorded in entry 79 and qualify the scope on hardware.

#### Outcome:

Four four-placement sweeps, each built from a clean worktree of `eb243a7` carrying only the scope changes and each fixing the path the previous one exposed, took the pixel clock from entry 79's 43.082 and 46.961 MHz to 75.126 MHz at placement 3 against 74.25 MHz. `src/visualizers/scope_xy.sv` now computes brightness in three registered stages carrying row and group tags, publishes the cache on its last write, and holds the line cache in 24 explicit 64x8 lane memories that Gowin infers as distributed RAM, removing about 12000 flip-flops; it compares each port-A writer's address with a registered prefetch address instead of the muxed port-A address, registers `flush`, the frame start and `clear_all`, and gives retirement one more wait state. `src/visualizers/scope_phosphor_ram.sv` registers both ports' address, enable and data ahead of the 128 DPX9B blocks, giving three-cycle reads, and `src/visualizers/scope_reconstruct.sv` splits each filter tap into select, multiply and accumulate stages. The full suite passed, and `tests/scope_ram_tb.sv` now rejects data visible before the third edge and uses a block-distinct pattern, because its old `addr*37` pattern gave every 2048-word block identical data and hid mapping errors; deliberately misaligned variants confirmed the benches catch a short cache pipeline, an early retirement sample, a wrong prefetch row and the old two-cycle wrapper. Sweep 4 failed only at placements 0 to 2, by 0.290 to 0.732 ns on HDMI `cx` through `read_x` into the cache lane reads, while placement 3 met setup and hold with +0.157 and +0.139 ns worst slack and every other domain passing, using 19382 logic, 15519 flip-flops, 257/340 BSRAM, 6/298 DSP, PRIMARY 8/8 and PLL 7/12. Before the corrections were complete, the user had sweep 2's timing-failing placement 3 image loaded as a diagnostic and judged it visually correct; it is not the qualified image. The qualified image, 5283212 bytes, MD5 `75cbeb027133b6e123e116798ef1b560`, SHA-256 `817b35b1992319f00604731080f9009357b12997f83249fddc184e15928aa837`, is `/cores/console138k/phosphortang-oscope.bin` with `/scripts/oscope.tdsh`, leaving the entry 78 playback image in place; the user had replaced `/music`, so the twelve-format corpus and scope fixtures were regenerated with TinyTang's `tools/make_codec_corpus.sh` and `tools/make_scope_fixtures.py`, matching the recorded corpus CRCs, and uploaded beside the user's files. On TinyTang firmware `fd2933e-dirty.d2b8b07` with the unchanged on-demand player, the ABI read 1.10, `tools/oscope_check.py` passed all seven fixtures with exact sample counts, zero underruns, zero visual drops and exact native MCLK counts, `tools/i2s2_format_sweep.py` passed all thirteen plays with entry 76's sample counts and both rate transitions, and the user accepted the display and sound. `docs/oscope-handoff.md` now records the corrections, every sweep and the qualification evidence, `docs/oscope-plan.md` points to it, and the two scope records in `.ai/core-reference.md` were corrected for the qualified design. The required core-syntax audit re-read `.ai/core.md` and `.ai/core-syntax.md`, inspected the complete staged `.ai` diff, confirmed that `.ai/core.md` is unchanged and that no settled entry was rewritten, and validated this entry as number 81 with 15 entries in the active log and exactly six sections.

#### Next Steps:

Restore timing margin across seeds by computing the pixel request and `read_x` from `cx` one clock ahead, then sweep placements 0 to 3 for at least three passing placements and requalify that image. The user intends each further visualizer, starting with the remaining two MiSTer-Phosphor visualizers, to be its own core sharing one platform, so the next structural step is extracting the platform top and a visualizer slot interface. The resident-player, RAM bridge and JTAG experiments in the working tree remain uncommitted and unqualified.

#### Files Modified:

- docs/oscope-handoff.md
- docs/oscope-plan.md
- src/visualizers/scope_phosphor_ram.sv
- src/visualizers/scope_reconstruct.sv
- src/visualizers/scope_xy.sv
- tests/scope_ram_tb.sv

#### Status:

- Build: PASS
- Deployment: PASS
- User Test: PASS

---
