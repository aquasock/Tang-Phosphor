# Experiment: resident gapless player

Status: unqualified.  Written 2026-10-06 between core-log entries 76 and
79, committed and logged as deferred in entry 83, and still not built or
tested. It is step 3 of the plan approved in
entry 75. The qualified player remains entry 76's on-demand player
(`/ae350/resident.tpi`, 865816 bytes, CRC-32 `c7a89035`); do not replace it
with a build of this work until this experiment is qualified.

## Files

- `software/rbhost/host/platform_ae350.c`: the resident mode (+341/-154
  lines against `f33f53d`).
- `software/rbhost/host/rbhost.c`: `rbhost_reset()`, called before every
  `main()`, restores the codec API and per-track state, and the DSP and
  timestretch buffers are initialised once instead of per track.
- TinyTang's working tree carries the matching BL616 side, also uncommitted:
  `ports/bl616/phosphor/ae350_file_server.cpp` and `.h`,
  `phosphor_player.cpp` and `phosphor_cmd.cpp`.

## Design

A player built with `BENCH_STREAM=2` (`make -C software/rbhost
bench-ondemand`) no longer returns after a track. It asks the BL616 for its
next track with a length-0 request, `QUERY_NEXT`, answered with the track's
size, 0 while nothing is queued, or `ANSWER_STOP`, then reads the track in
64 KiB chunks through the file-request mailbox as entry 76's player does.
While decoding it asks every 100 ms whether to stop (`QUERY_POLL`); a stop
longjmps out of the codec. One request is outstanding at a time, and
`service()`, called from every wait and output write, drains answers so
playback keeps being fed.

With `BENCH_PLAY=1` each track's PCM is appended to one stream of 64-bit
positions held in the output buffer as a ring, handed to the FPGA player
whenever the play stream has room. The stream stays open while consecutive
tracks share a sample rate, so they follow without a gap; a track at another
rate waits for the stream to play out and end, then opens a new one.

The result words publish the player's state: USER(0) `RESIDENT_MAGIC`
(`0x52455331`, "RES1"), USER(1) tracks begun, USER(2) tracks finished,
USER(3) the latest finished track's samples and USER(4) its decode status
(`TRACK_ABORTED` for a stopped track). TinyTang sends the player only when it
is not already resident, treats a track as over when the finished count
reaches its number, and stops a track through the mailbox, halting a player
that does not take the stop up in time.

## Open points

- No build, sweep or hardware result is recorded for it.
- The resident player start failure of entries 69, 73 and 74 (input received,
  never decoded) was never explained, and entry 76's on-demand player has not
  shown it. A player that stays resident across tracks exercises the RAM path
  far longer, so the RAM bridge experiment
  ([experiment-ram-bridge-burst.md](experiment-ram-bridge-burst.md)) should
  be settled first.
- A rate change between tracks currently means a muted stream restart; the
  I2S2 path's muted rate transition (entry 78) must be accounted for.
- Qualification needs both repositories' changes together, the twelve-format
  sweep, a time-to-first-sample measurement against entry 76's 2.7 s, and a
  gapless check across same-rate tracks.
