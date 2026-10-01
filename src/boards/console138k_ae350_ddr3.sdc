// SPDX-License-Identifier: Apache-2.0
//
// Tang-Phosphor AE350 + DDR3 image.  Clock definitions follow Sipeed's
// TangMega-138K-example ddr3_1v4_hs.sdc (Apache-2.0, commit 06e7d8b), with
// the board clock at its real 50 MHz, as in Tang-PSX's standalone DDR3
// test.  The 50 MHz, 400 MHz memory, and 100 MHz controller user clocks are
// asynchronous; every crossing between them is a two-stage synchronizer, a
// Gray-coded FIFO pointer, or data held stable by a synchronized handshake
// (src/ae350/async_fifo.sv, src/ae350/debug_read_cdc.sv).

create_clock -name clk50 -period 20 -waveform {0 10} [get_ports {clk}]
create_clock -name clk400 -period 2.5 -waveform {0 1.25} [get_nets {subsystem/memory_clk}]
create_clock -name ui_clk -period 10 -waveform {0 5} [get_pins {subsystem/u_ddr3/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]
set_clock_groups -exclusive -group [get_clocks {clk400}] -group [get_clocks {clk50}] -group [get_clocks {ui_clk}]
