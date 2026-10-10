# Experiment: AE350 cache and loading probes

Status: unqualified.  Written 2026-10-06 between core-log entries 76 and
79, committed and logged as deferred in entry 83, and still not built or
tested. No results are recorded. Both build with the other test
programs (`make -C software/ae350` gives `programs/<name>.tpi`).

## `software/ae350/programs/chainload`

Tests how a program image must be committed to memory before it is run, one of
the open leads for the resident player start failure (entries 73 and 75). It
is linked high, at `0x7e000000`, requests a TPI image from the BL616 through
the file-request mailbox as `phosphor run /ae350/chainload.tpi <image.tpi>`
serves it, copies the payload to its load address through the data cache as
the boot ROM does, checks its CRC-32 there and calls it. `CHAIN_FLUSH` selects
the commit:

- 0: `fence rw, rw; fence.i`, the boot ROM's sequence
- 1: the whole L1 data cache written back and invalidated
  (`L1D_WBINVAL_ALL`), a 1 ms wait, then `fence.i`, as Tang-PSX does
- 2: mode 0, then the program entered with the boot ROM's stack pointer

`CHAIN_TIMER` adds a machine-timer interrupt 3 s in that records the
interrupted program counter, and `CHAIN_TRIGGER` adds a debug trigger that
traps any access below address 32. USER(10..12) hold the payload size, its CRC
as copied and the mode.

## `software/ae350/programs/wbrace`

Tests whether a cache-line fill through the RAM bridge can return DDR3's
contents from before a write-back of the same line issued just ahead of it.
Over 64K lines and four passes with a fresh pattern each:

- `cctl`: 8 words stored to a line, the line written back and invalidated on
  its own (`mcctlbeginaddr` with `L1D_VA_WBINVAL`), then read back
- `evict`: 8 words stored to a line and to the four other lines of its set,
  8 KiB apart in the 32 KiB 4-way cache, so the first is evicted dirty, then
  read back

USER(0) and USER(1) count mismatches in each, USER(2..4) give the first bad
address, the expected word and the word read, and the result is `0x600d0000`
plus the total mismatches.

## Use

Run both with and without the RAM bridge fix
([experiment-ram-bridge-burst.md](experiment-ram-bridge-burst.md)) on the
entry 81 core. A `wbrace` mismatch or a `chainload` mode that fails where
another passes would locate the start failure; clean results on both bridges
would point back at the bridge's burst prediction or elsewhere.
