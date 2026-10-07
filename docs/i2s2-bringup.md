# Pmod I2S2 output bring-up

The merged core's PMOD personality `5` outputs the player's stereo PCM at
native 44.1 or 48 kHz. One I2S frame cadence feeds both the analog DAC and
HDMI, including identical silence during pause, drain and clock transitions.
Line input is deferred. The OLED and rotary encoder remain on hold.

The separately retained `phosphortang-i2s2-tone.bin` image generates the
previously qualified 48 kHz left 1 kHz / right 2 kHz diagnostic tones.

## Clocks and framing

Two revision-C Gowin PLL recipes generate the shared audio master clock:

| Stage | Input | Multiplier | Output divider | VCO | Output |
|---|---:|---:|---:|---:|---:|
| Reference | 50 MHz | 24 | 50 | 1200 MHz | 24 MHz |
| Audio, 48 kHz | 24 MHz | 32 | 62.5 | 768 MHz | 12.288 MHz |
| Audio, 44.1 kHz | 24 MHz | 36.75 | 78.125 | 882 MHz | 11.2896 MHz |

Both use input and feedback dividers of 1. The second output divider uses the
PLL's supported eighth-step division. The new VCOs are within DS1239's
650–1300 MHz range. This does not qualify analog clock jitter on hardware.
`tools/gen_i2s2_plls.sh` regenerates the attributed vendor wrappers from
`src/pll/pll_i2s2_*.mod`; the varying generation timestamp is removed.

Gowin's automatic clock report uses the integer-only second divider in this
configuration, showing 12.387 MHz instead of the requested 12.288 MHz. Verify
the actual hardware with `phosphor peek 0xfc` and `phosphor peek 0xf8`.
ABI 1.9 adds ready, settling and active-rate status: steady 48 kHz reads
`0x1f` with count `0x0012c000` (1,228,800); steady 44.1 kHz reads `0x17`
with count `0x00113a00` (1,128,960). Allow a complete measurement window
after a clock change. The old tone image uses ABI 1.8 and status `7`.
The counter measures actual MCLK edges over 100 ms of the pixel clock through a registered Gray counter and two-stage synchronization. It
does not infer the frequency from the PLL parameters or PC command timing.

SCLK is MCLK / 4, and LRCK is MCLK / 256. Each
channel has 32 serial clocks. LRCK low selects left and high selects right.
Data and LRCK change on falling SCLK edges; the DAC samples on rising edges.
The first rising edge after a channel change is the I2S delay bit. Sixteen
significant PCM bits follow, then zero padding, giving a 24-bit DAC word with
the 16-bit sample in its high bits. Both channels latch at one frame boundary.

## Socket and setup

Normal PMOD lane order is DAC MCLK, LRCK, SCLK and SDIN on Digilent pins
1–4. Pins 7–10, the ADC interface, remain released. The existing socket layer
maps these to Sipeed IO0, IO2, IO4 and IO6 and handles declared orientation.
Clock loss resets the serializer; withdrawing the declaration releases all
lanes. Socket `5` exists only when the I2S2 backend is compiled in; it is enabled in the merged
core, not the older mirror-only bring-up core.

Power the board off before changing modules or JP1. Remove the OLED and
encoder, set I2S2 JP1 to SLV, and seat the module in the OLED's former PMOD0
socket with module pin 1 aligned to socket pin 1. JP1 affects only the ADC;
SLV is the intended setting for later input work. Connect Line Out to powered
speakers or an amplifier, starting with low volume. The board has no dedicated
headphone amplifier.

Keep the diagnostic image separate from the qualified playback image:

```text
/cores/console138k/phosphortang-i2s2-tone.bin
/scripts/i2s2-tone.tdsh
```

Upload with TinyTang's guarded `tools/tinytang_put.py` at a confirmed shell
prompt. After seating the module and powering up, run:

```text
tdsh run /scripts/i2s2-tone.tdsh
```

The script loads the diagnostic image and declares `0xc0 = 0x50`: PMOD0
personality 5, normal orientation, PMOD1 released. Left should be the lower
tone and right the higher tone. `phosphor poke 0xc0 0` releases both sockets.
Do not run the existing `phosphor.tdsh` for this test: its default declaration
selects the OLED and encoder.

## Music playback

The playback image and launch script use separate paths:

```text
/cores/console138k/phosphortang-i2s2-play.bin
/scripts/i2s2-play.tdsh
```

Run `tdsh run /scripts/i2s2-play.tdsh`, then
`phosphor play /music/test.wav` or another supported track. The script declares
only the I2S2 and hides the desk layer. The existing AE350 on-demand player
remains unchanged. Playback runs through HDMI even if no PMOD is declared.

A toggle handshake fetches one held stereo pair from the pixel-domain FIFO
for the next I2S frame. The emitted pair returns to HDMI with a synchronized
frame pulse. A stream epoch rejects prefetched samples from a canceled stream.
Pause prevents FIFO pops; at most one prefetched frame completes before silence.

A rate change first sends zero samples for 0.5 ms (at least ten frames),
resets the PLL for 100 microseconds while changing its divider inputs, waits
for lock, then sends zero frames for 300 ms before consuming PCM. This follows
the CS4344 clock-change and initialization guidance. FIFO data waits through
the transition; the clock probe measures the physical MCLK independently.
No new PLL or primary clock route is added beyond the tone build.

`tests/i2s_playback_tb.sv` checks the physical I2S sample words against every
HDMI-delivered pair, sample sequence and counts, both native rates, HDMI ACR
N/CTS, pause/resume, cancellation and PLL lock recovery. The test uses a
shorter settling interval; hardware retains the full 300 ms.

Run `python3 tools/i2s2_format_sweep.py` to repeat the twelve-format corpus
and final WAV, checking exact sample counts, zero underruns, active-rate status
and actual MCLK counts for each play. `--only opus,wav` checks the transition
in both directions. It uses the sibling TinyTang checkout's guarded console
tools; use `--tinytang-tools` for another location.

## References and validation

Use the Cirrus CS4344 datasheet for DAC timing and clock ratios, and the
CS5343 datasheet for future ADC work. The Digilent reference manual contains
errors: its `784×` ADC ratio should be `768×`, and its ADC master-mode
paragraph confuses sample-rate units with MCLK frequency.

`tests/i2s_tx_tb.sv` decodes data at the DAC sampling edge and checks changing
PCM inputs, coherent pairs, framing, zero padding, clock ratios, stereo tone
periods, reset and declaration withdrawal through the socket permutation.
`tests/ui_mirror_tb.sv` additionally checks selection on either socket,
orientation and loss of PLL lock. Run `tests/run.sh`, then
`MERGED_PLACE_OPTIONS="0 1 2 3" scripts/build-merged.sh` and inspect setup
and hold results for every placement before deployment. Listening on the
module remains required for hardware qualification.


## Initial clock qualification

The diagnostic build was staged from `df24687` plus the I2S2 changes,
excluding the checkout's pre-existing player, bridge and JTAG experiments.
The full simulation suite passed. Placements 0 and 3 met setup and hold timing;
placement 1 failed in the DDR3 controller clock domain, and placement 2 failed
on the existing HDMI packet path. Placement 3 was deployed, with pixel Fmax
86.641 MHz against its 74.250 MHz constraint. The new clock consumes the final
two available primary clock resources: PRIMARY is 8/8 and PLL is 7/12, so
future audio clock changes must consider routing capacity.

The deployed diagnostic image is 5,063,680 bytes, MD5
`458ff2611ef245b8acbad28a1a99984d`, SHA-256
`de2907e6098f419b256b79c974d8758a516a39c0a743f2112db23e9140dce52f`.
It loaded as core 80 with both sockets released. Status at `0xfc` was `7`, and
three reads at `0xf8` all returned `0x0012c000`, confirming nominal 12.288 MHz
on hardware. After installation in PMOD0 with JP1 at SLV, the launch script declared
`0xc0 = 0x50`, and the user reported perfect output for the left 1 kHz and
right 2 kHz tones. This qualifies the output bring-up, not measured analog
performance or clock jitter.

## Native playback qualification

The playback build used committed `17ce020` plus the PCM integration,
excluding the existing player, bridge and JTAG experiments. The full simulation
suite passed, with an additional I2S-driven HDMI ACR check at both rates.
Only placement 2 met setup and hold timing in the four-placement sweep, with
pixel Fmax 82.572 MHz against 74.250 MHz and zero violated endpoints. Resource
use remains PRIMARY 8/8 and PLL 7/12.

The deployed playback image is 5,095,424 bytes, MD5
`29bceef7946c6408569b9d286c02bb5d`, SHA-256
`d72e5701d2484605e9166926f04b7121fa3e6e08d78b4e5aa5aa1f022efe16b4`.
It loaded as core 80, register ABI 1.9, on TinyTang firmware
`fd2933e-dirty.d2b8b07`, using the unchanged on-demand AE350 player.
The user reported that the first WAV sounded perfect.

All twelve corpus formats plus the WAV after Opus completed with zero
underruns. Sample counts matched entry 76, including 441000 for FLAC.
A further `tools/i2s2_format_sweep.py --only opus,wav` passed exact count and
physical-clock checks in both directions: Opus produced 479688 samples at
48 kHz, MCLK count 1228800 and status `0x1f`; WAV produced 441000 samples at
44.1 kHz, MCLK count 1128960 and status `0x17`. These checks qualify playback
and native clock selection; analog jitter and line input remain unmeasured.
