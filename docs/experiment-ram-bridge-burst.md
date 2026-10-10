# Experiment: RAM bridge burst prediction fix

Status: unqualified.  Written 2026-10-06 between core-log entries 76 and
79, committed and logged as deferred in entry 83, and still not built or
tested. Its bench has not been run in this state
and it has not been built or tested on hardware.

## Files

- `src/ae350/ae350_ram_bridge.sv`
- `tests/ae350_ram_bridge_tb.sv`

## The suspected fault

`ae350_ram_bridge` serves the AE350's AHB RAM port. To run the rest of a
cache-line burst without wait states, it predicts whether a SEQ beat can
complete from registered burst state plus `HTRANS` and `HWRITE`, and serves a
predicted read beat from the line buffer at lane `p_beat + 1`, without looking
at `HADDR`.

The experiment's comments state that the AE350's RAM port was traced issuing a
NONSEQ beat on one line followed by SEQ beats on a different line, and cite
"core-log entry 77" for it. No such finding was logged; entry 77 is the I2S2
tone cycle. The trace was presumably captured through the AE350 debug JTAG
experiment ([experiment-ae350-jtag.md](experiment-ae350-jtag.md)), but its
evidence is not in the repository. If the sequence is real, the bridge serves
those SEQ beats from the wrong line: wrong data with no error.

That would fit the resident player start failure of entries 69, 73 and 74,
which depended on image layout, came and went across power cycles, and showed
no trap or watched access. It remains a hypothesis until it is reproduced.

## Change

The bridge now records the line of the last accepted transfer (`p_line`,
`HADDR[29:5]`) and predicts a SEQ beat only when its address is the next lane
of that same line (`p_next`). A SEQ beat whose address does not follow is
evaluated as a new transfer, and the line buffer serves only beats on the line
it holds. This adds an address compare to the prediction path; the bridge's
existing comment records about 4 ns of routing on the macro's AHB outputs, so
bus-clock timing must be checked.

The bench adds a "redirected burst" case: a NONSEQ beat on one line, then the
rest of a WRAP4 burst as SEQ beats on another line.

## To qualify

1. Run the bench against the old bridge to show the redirected case fails it,
   then against the fix to show it passes.
2. Build the merged image and check `bus_clk` timing across placements.
3. Run the `wbrace` and `chainload` probes
   ([experiment-ae350-probes.md](experiment-ae350-probes.md)) and the
   twelve-format sweep with the qualified player.
4. Try to reproduce the resident player start failure with and without the fix
   before attributing it to this fault.
