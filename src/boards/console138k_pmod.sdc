// SPDX-License-Identifier: GPL-3.0-only
//
// Tang-Phosphor PMOD socket bring-up core.
//
// The board clock is the PLL reference and nothing else; every backend runs on
// the PLL-derived pixel clock, so there is no logic crossing between clk50 and
// the pixel domain and no CDC to constrain.  The groups below are declared
// conservative anyway, matching the merged image.

create_clock -name clk50 -period 20 -waveform {0 10} [get_ports {sys_clk}]
create_clock -name clk27 -period 37.037 [get_nets {clk27}]
create_clock -name clk_pixel -period 13.468 [get_nets {clk_pixel}]
create_clock -name clk_pixel_x5 -period 2.694 [get_nets {clk_pixel_x5}]

set_clock_groups -exclusive -group [get_clocks {clk50 clk27}] -group [get_clocks {clk_pixel clk_pixel_x5}]
