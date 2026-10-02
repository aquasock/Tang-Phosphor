// SPDX-License-Identifier: GPL-3.0-only
//
// Tang-Phosphor PMOD socket bring-up cores.
//
// Both build variants are sibling tops, so the PLL outputs sit at the root of
// the hierarchy and can be named directly; this tool version does not support
// patterns in get_nets.  The board clock is the PLL reference and nothing else,
// and every backend runs on the pixel clock, so no logic crosses between them
// and no clock groups need declaring.

create_clock -name clk50 -period 20 -waveform {0 10} [get_ports {sys_clk}]
create_clock -name clk27 -period 37.037 [get_nets {clk27}]
create_clock -name clk_pixel -period 13.468 [get_nets {clk_pixel}]
create_clock -name clk_pixel_x5 -period 2.694 [get_nets {clk_pixel_x5}]
