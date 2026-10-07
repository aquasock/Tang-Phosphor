// SPDX-License-Identifier: Apache-2.0
//
// Tang-Phosphor merged image: FPGA player + AE350 + DDR3 in one bitstream.
// The 50 MHz board clock, 400 MHz memory clock, and 100 MHz controller user
// clock are asynchronous to each other and to the player's PLL-derived
// pixel/video clocks; every crossing uses a two-stage synchronizer, a
// Gray-coded FIFO pointer, or a synchronized handshake (src/ae350/async_fifo.sv,
// src/ae350/debug_read_cdc.sv).  The pixel clock is itself derived from the
// board clock through the player PLL chain, but the subsystem synchronizes
// that crossing like any asynchronous boundary, so clk_pixel and clk50 are
// kept in separate clock groups.

create_clock -name clk50 -period 20 -waveform {0 10} [get_ports {sys_clk}]
create_clock -name clk400 -period 2.5 -waveform {0 1.25} [get_nets {cpu_subsystem/memory_clk}]
create_clock -name ui_clk -period 10 -waveform {0 5} [get_pins {cpu_subsystem/u_ddr3/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]
create_clock -name bus_clk -period 13.333 -waveform {0 6.667} [get_nets {cpu_subsystem/bus_clk}]

# Player PLL-derived clocks.
create_clock -name clk27 -period 37.037 [get_nets {clk27}]
create_clock -name clk_pixel -period 13.468 [get_nets {clk_pixel}]
create_clock -name clk_pixel_x5 -period 2.694 [get_nets {clk_pixel_x5}]
create_clock -name clk12 -period 83.333 [get_nets {clk12}]
create_clock -name clk_i2s2_ref -period 41.667 [get_nets {clk_i2s2_ref}]
create_clock -name clk_i2s2_mclk -period 81.380208 [get_nets {clk_i2s2_mclk}]

set_clock_groups -exclusive -group [get_clocks {clk400}] -group [get_clocks {ui_clk}] -group [get_clocks {bus_clk}] -group [get_clocks {clk50 clk27 clk12}] -group [get_clocks {clk_pixel clk_pixel_x5}] -group [get_clocks {clk_i2s2_ref clk_i2s2_mclk}]

# The controller USB engines and the video/control logic use independent PLLs.
# Constrain only the asynchronous inputs to the explicit first synchronizer
# stage; all paths after this stage remain normally timed.
set_false_path -to [get_regs {joy_usb1_meta* joy_usb2_meta* controller_status_meta*}]
