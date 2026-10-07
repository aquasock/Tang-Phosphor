# O-Scope agent handoff

Terminal result, 2026-10-06: simulation passes; FPGA timing fails. The user
stopped the cycle, requested termination of the remaining two builds, and
authorized logging, committing and pushing this handoff. No scope image or
launch script was deployed. The proposed timing fix has **not** been implemented.

## Implemented behavior

The approved target is a 512x512 stereo XY plane, displayed as a centered
720x720 square in 1280x720 HDMI. The visual branch observes the emitted shared
I2S2/HDMI PCM pair and its new presence tag, reconstructs at 2x sample rate,
queues 256 points, draws connected lines, and derives eight-bit brightness
from timestamp age. Overflow drops visual points and breaks line continuity;
it cannot backpressure audio. Four persistence settings and optional narrow
glow latch at frame boundaries. The desktop retains composition priority.

ABI 1.10 adds registers 0xac through 0xb8. The scope is disabled at reset;
`tools/oscope.tdsh` enables medium trails and glow. See
[oscope-plan.md](oscope-plan.md) and [debug-registers.md](debug-registers.md)
for the complete design and control contract.

## Validation and build evidence

The full `tests/run.sh` suite passed against the isolated scope source.
The scope bench compares all 921600 visible pixels against an independent
geometry/glow model and checks native-cadence full-scale jumps, forced
overflow and discontinuities, pause, retirement, timestamp wrap and RAM
collision regions. Reconstruction checks rounding, saturation, stereo phase
and reset. The shared audio bench checks presence tagging of genuine zero
PCM and coherent I2S/HDMI delivery at both native rates. The existing playback,
HDMI, PMOD, menu, desktop, keyboard and register regressions also pass.
`tools/check_scope_ram.sh` passes against both the portable behavioral memory
and the installed Gowin DPX9B primitive model, covering all 128 blocks and
both ports' two-cycle latency.

The build used committed baseline `1941765` plus only this cycle's scope
changes, excluding the checkout's earlier player/bridge/JTAG experiments.
Tool/device: Gowin EDA 1.9.11.03, GW5AST-LV138PG484AC1/I0, revision C.

| Placement | Result | Pixel Fmax | Pixel setup TNS | Violated endpoints |
|---|---|---:|---:|---:|
| 0 | Measured timing failure | 43.082 MHz | -79565.688 ns | 14598 |
| 1 | Measured timing failure | 46.961 MHz | -67710.695 ns | 14627 |
| 2 | Terminated at user request; assumed failed for handoff | Unmeasured | Unmeasured | Unmeasured |
| 3 | Terminated at user request; assumed failed for handoff | Unmeasured | Unmeasured | Unmeasured |

The pixel constraint remains 74.25 MHz. Placements 0/1 had no setup/hold
violations in the other reported clock domains. Placements 2/3 were still
routing when terminated with SIGTERM; neither produced a final bitstream or
timing report. Their assumed failure is not a measured timing verdict.

Both completed builds use 24352/138240 logic resources, 27596 flip-flops,
257/340 BSRAM blocks (including 128 DPX9B for the plane), 6/298 DSP blocks,
8/8 primary clock routes and 7/12 PLLs. No scope clock, PLL or DDR3 access
was added. The small line cache became about 12288 fabric registers rather
than distributed RAM.

Local evidence remains under `build/oscope-session/`: `regression-final.log`,
`ram-check.log`, `build-hardware-ram.log`, `source-manifest.json`,
`scope-raster.png`, and the saved termination logs. Final completed build
reports and failed bitstreams are under
`build/oscope-stage/build/merged/place0/` and `place1/`; do not deploy them.
The build script's temporary directory was removed after collecting results.
These generated artifacts are ignored by Git; this document records the
durable findings.

## Timing failure and next implementation

The critical path runs from `scope/plane/b_q` through the combinational
`intensity()` age subtraction, trail selection, quadratic brightness and
rounding, then into `scope/cache_cache_RAMREG_*`. Placement 0's worst path
has 23.108 ns data delay and -9.743 ns slack; placement 1's has 21.187 ns
data delay and -7.826 ns slack. This is a scope path, not an existing HDMI
or DDR3 failure. Additional seeds cannot be relied upon to repair this large
gap.

The proposed next change is to pipeline age/validity capture, trail ramp,
square, rounded brightness, and cache publication. Carry row/group tags and
valid strobes through the same stages. Move `cache_ready` publication to the
last actual cache write, keeping publication before x=275. Prefetch currently
ends around x=195, leaving room for added stages without changing visible
pixel alignment. Inspect the implementation's actual cycle timing before
choosing the final pipeline depth.

Also split each of the three cache rows into eight explicit 64x8 lane
memories, with fixed row/lane writers and independent asynchronous reads,
to help Gowin infer distributed RAM and reduce register/data fanout. The
current dynamic multi-dimensional write/read expression expanded into fabric
registers. Verify inference rather than assuming this rewrite fixes it.

These changes were discussed but no source edits were made before the user
stopped work. Resume only when asked. After the change, rerun the full-raster
bench and relevant regression checks, then rebuild. Deploy only after all
required setup/hold constraints pass; collect hardware and user acceptance
before calling the scope qualified.

## Hardware and preserved work

The I2S2 remains in PMOD0, normal orientation, JP1 SLV. OLED and encoder are
on hold; line input and Siglent measurements remain deferred. The qualified
playback baseline remains `1941765`, using
`/cores/console138k/phosphortang-i2s2-play.bin` and
`/scripts/i2s2-play.tdsh`. TinyTang firmware remains
`fd2933e-dirty.d2b8b07`; do not rebuild it or replace its on-demand player
with the checkout's unqualified resident-loop experiments.

Six 4-second 48 kHz fixtures and one 44.1 kHz circle were uploaded to
`/music/scope-<shape>-<rate>.wav`; no scope playback or hardware qualification
was run. `tools/make_scope_fixtures.py` reproduces them. Once an image passes
timing and is loaded, `tools/oscope_check.py` checks fixture sample counts,
visual drops, retirement progress and native MCLK, and
`tools/i2s2_format_sweep.py` repeats the twelve-format audio corpus.
The final console probe reached the shell, but the FPGA register probe had
no answer; no image was loaded in response.

The working tree still contains unrelated changes in `software/rbhost/`,
`src/ae350/`, `tests/ae350_ram_bridge_tb.sv`, the Rockbox submodule, AE350
chainload/wbrace programs and OpenOCD configuration. The top/core working
copies also contain earlier PMOD0/JTAG additions. They were excluded from
the tested scope source and this commit. Pre-existing trimming of
`.ai/core-log.md` and untracked `.ai/archived_logs/` were preserved locally;
settled committed history was retained in this commit. Use a clean checkout
or an archive of the handoff commit when rebuilding; do not accidentally
include those experiments from the shared working tree.
