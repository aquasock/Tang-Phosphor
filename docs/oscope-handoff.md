# O-Scope timing closure and qualification

Result, 2026-10-07: the 512x512 stereo XY scope meets setup and hold timing at
placement 3 and is hardware-qualified (core-log entry 81). The margin
correction below then met timing at placements 1 and 2, and the placement 1
image replaced it on the card (core-log entry 82). Entry 79 recorded
the earlier timing failure that this document originally handed off; the
behavior described in [oscope-plan.md](oscope-plan.md) and the ABI 1.10
registers in [debug-registers.md](debug-registers.md) are unchanged.

## Timing corrections

Entry 79 failed at 43.082 and 46.961 MHz against 74.25 MHz, with the plane
read feeding the whole brightness calculation and a dynamically indexed line
cache that Gowin built from about 12288 flip-flops. Four sweeps followed, each
fixing the critical path the previous one exposed:

1. Brightness is three registered stages (age, trail ramp, square and round)
   with row/group tags and a valid strobe carried alongside, and
   `cache_ready` is set by the last actual cache write. The cache is 24
   explicit 64x8 memories, one per row and lane, with fixed writers and
   asynchronous reads; Gowin infers them as distributed RAM (192 RAM16SDP4).
2. `scope_phosphor_ram` registers both ports' address, enable and data ahead
   of the 128 DPX9B blocks, so no BSRAM pin is driven by deep logic. Reads
   take three cycles and writes one, equally on both ports, so collision
   checks on the unregistered inputs remain valid. The prefetch tags and the
   retirement state machine each gained one stage; retirement still fits its
   16-cycle slot.
3. Cross-port collisions compare each port-A writer's own address with the
   prefetch address instead of the muxed `a_addr`. `flush` and the frame
   start are registered at the scope boundary, so the settings latch at
   `cx==1`, still in the left bar.
4. The prefetch address is a register one step ahead of `load_index`, with
   the neighbouring rows precomputed, `clear_all` is registered, and
   `scope_reconstruct` splits each tap into operand select and pair sum,
   product, and accumulate stages; a reconstructed pair now takes 13 cycles
   of the roughly 1547 available per 48 kHz sample.

`tests/scope_ram_tb.sv` now checks that data is not visible before the third
edge, and its data pattern includes the block index because `addr*37` alone
gave every 2048-word block the same nine-bit values, which hid block-mapping
errors. Deliberately misaligned variants confirmed the benches detect a
one-cycle-short cache pipeline, an early retirement sample, a wrong prefetch
row and the old two-cycle RAM wrapper.

| Sweep | Pixel Fmax by placement 0/1/2/3 (MHz) | Pixel setup TNS 0/1/2/3 (ns) |
|---|---|---|
| Entry 79 | 43.082 / 46.961 / not completed | -79565.688 / -67710.695 / not completed |
| 1 | 58.982 / 60.360 / 58.313 / 59.742 | -770.941 / -706.761 / -791.418 / -862.639 |
| 2 | 60.497 / 62.678 / 63.618 / 64.352 | -272.203 / -139.877 / -156.646 / -587.132 |
| 3 | 66.726 / 60.954 / 72.150 / 64.229 | -30.874 / -124.073 / -1.888 / -85.841 |
| 4 | 70.424 / 71.093 / 72.684 / 75.126 | -4.245 / -1.789 / -0.655 / 0 |

Sweep 4 placement 3 has zero setup and zero hold violations, worst setup slack
+0.157 ns and worst hold slack +0.139 ns, and every other clock domain meets
its constraint. It uses 19382/138240 logic including 209 RAM16, 15519
flip-flops, 257/340 BSRAM, 6/298 DSP, PRIMARY 8/8, PLL 7/12 and LW 5/8.
Placements 0 to 2 fail by 0.290 to 0.732 ns on one remaining path, HDMI `cx`
through `request_pixel` and `read_x` into the cache lane reads feeding
`above_q`, `core_q` and `below_q`; computing those from `cx` one clock ahead
is the margin correction still to be made. Every sweep was built from a clean
worktree of `eb243a7` carrying only the scope changes, with Gowin EDA
1.9.11.03 for GW5AST-LV138PG484AC1/I0 revision C.

## Margin correction

Two further sweeps, built from a clean worktree of `f33f53d` carrying only the
scope changes, removed the remaining scope paths:

- A. `request_pixel` is a register loaded from `cx` 274..993, one clock ahead;
  `cy` cannot change between `cx==274` and `cx==995`. The `cx==275` override
  of `read_x` was redundant, since `source_x` is cleared on every cycle outside
  the view, so `read_x` is the `source_x` register. The `cx` path disappeared,
  exposing the top-level `resetn` feeding `clear_all`, `usable`, `b_read`, the
  draw and retirement hazard compares and `draw_x`, `sweeps` and the point
  FIFO, with about 4.3 ns of routing from the high-fanout reset.
- B. `clear_all` is the registered `clear_q` alone, which already includes
  `!resetn`, and `usable` is a register loaded with the value its old
  combinational definition takes on the next clock. `tests/scope_xy_tb.sv`
  checks that equality on every clock; a copy that simply registered the old
  expression, one clock late, passed the rest of the bench and fails this check.

| Sweep | Pixel Fmax by placement 0/1/2/3 (MHz) | Pixel setup TNS 0/1/2/3 (ns) |
|---|---|---|
| A | 67.473 / 67.046 / 67.415 / 61.907 | -20.935 / -13.099 / -16.377 / -126.819 |
| B | 72.506 / 82.563 / 76.910 / 64.702 | -0.324 / 0 / 0 / -21.545 |

Sweep B placements 1 and 2 have zero setup and zero hold violations in every
clock domain, with worst setup slack +1.025 and +0.466 ns and worst hold slack
+0.140 and +0.143 ns. No scope path fails at any placement. Placement 0 fails
inside the Gowin DDR3 controller (`ui_clk`, -0.608 ns TNS over 2 endpoints) and
on `debug_registers` read address into `debug_rdata` (-0.324 ns), and
placement 3 on the loader FIFO's `wready_q` through `tangcore_io`'s stream
drain into `stream_response_next_offset` (-1.987 ns). Placement 1 uses 18017
logic including 17 RAM16, 15617 flip-flops, 269/340 BSRAM, 6/298 DSP, PRIMARY
8/8, PLL 7/12 and LW 6/8; the move from 209 RAM16 and 257 BSRAM suggests
Gowin now maps the line cache into BSRAM behind the registered `read_x`, which
was not confirmed from the netlist.

## Hardware qualification

The entry 82 image, sweep B placement 1, 5158912 bytes, MD5
`0d0e2b5c1df97bfb3a66e729bbfc4391`, SHA-256
`1c63387762443a3e90ec06c77b75c6421440ec5158b8d7cbdb8b7e947ea535d9`, is
`/cores/console138k/phosphortang-oscope.bin`, loaded by `/scripts/oscope.tdsh`
(`tools/oscope.tdsh`), which declares the I2S2 in PMOD0 and enables medium
trails with glow. Entry 81's placement 3 image, 5283212 bytes, MD5
`75cbeb027133b6e123e116798ef1b560`, is kept as
`/cores/console138k/phosphortang-oscope.bin.bak`. The qualified playback image
`/cores/console138k/phosphortang-i2s2-play.bin` is unchanged.

Both images were qualified the same way. The ABI read 1.10 and the scope
status showed enabled, initialized and cache ready. `tools/oscope_check.py`
passed all seven fixtures, each with its exact sample count (192000 at 48 kHz,
176400 at 44.1 kHz), zero underruns, zero visual drops, about 1233 retirement
sweeps per play and exact MCLK counts of 1228800 and 1128960 edges per 100 ms.
`tools/i2s2_format_sweep.py` passed all thirteen plays with zero underruns and
entry 76's sample counts, switching rate both ways. The user accepted the
display and sound of each.

The fixtures and twelve-format corpus are regenerated by
`tools/make_scope_fixtures.py` and TinyTang's `tools/make_codec_corpus.sh`
(which needs the original `test.wma` and `test.opus`). On the card they are
kept in `/music_oscope-test` and `/music_codec-test` beside the user's library
in `/music`; for a check, rename `/music` aside, rename the test folder to
`/music`, and restore both afterwards.

## Preserved work

The shared working tree still contains unrelated, unqualified changes in
`software/rbhost/`, `src/ae350/`, `tests/ae350_ram_bridge_tb.sv`, the Rockbox
submodule, the AE350 `chainload` and `wbrace` programs, the OpenOCD
configuration and the PMOD0 JTAG additions in the top and core. Build from a
clean checkout so they are not included.
