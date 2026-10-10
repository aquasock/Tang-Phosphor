# Experiment: AE350 debug JTAG on PMOD0

Status: unqualified.  Written 2026-10-06 between core-log entries 76 and 79,
committed and logged as deferred in entry 83, and still not built or tested in
this state. No image built with it is recorded.

## Files

- `src/tang_phosphor_top.sv`: parameter `AE350_JTAG_PMOD0`, default 0.
- `src/pmod_mirror_core.sv`: parameter `RELEASE_PMOD0`, default 0.
- `src/ae350/ae350_soc.sv`, `src/ae350/ae350_subsystem.sv`: JTAG ports
  through to the macro, which the committed design ties off.
- `src/ae350/ae350_ddr3_top.sv`: ties the new ports off.
- `tools/openocd-ae350.cfg`, untracked.

## Design

The AE350's A25 has a RISC-V debug module behind the macro's TAP (`DBG_TCK`,
`TMS_IN`, `TRST_IN`, `TDI_IN`, `TDO_OUT`, `TDO_OE`). With
`AE350_JTAG_PMOD0 = 1`, a debug build takes PMOD0 for it: Digilent pin 1 TCK,
2 TMS, 3 TDI, 4 TDO and 7 TRST (Sipeed IO0, IO2, IO4, IO6 and IO1), with
`RELEASE_PMOD0` keeping the display stack off the socket. With the default 0,
TCK, TMS and TRST are tied high and TDI low, as before. The comments note that
TRST's polarity is not documented.

`tools/openocd-ae350.cfg` drives a Raspberry Pi Pico 2 running
lonehog/JTAGprobe as a CMSIS-DAP v2 adapter at 1 MHz, declaring a 5-bit-IR TAP
and a `riscv` target. PMOD0 is not the FPGA's configuration JTAG, so the probe
can stay connected while TinyTang reprograms the FPGA.

## Open points

- The default build must be unchanged by it; that has not been checked
  against a committed image.
- A JTAG build needs PMOD0, which the I2S2 now occupies, so debugging and
  analog playback cannot share the socket without moving one of them.
- It is the likely source of the bus trace the RAM bridge experiment relies on
  ([experiment-ram-bridge-burst.md](experiment-ram-bridge-burst.md)); its
  comments cite "core-log entry 77", which was never logged.
