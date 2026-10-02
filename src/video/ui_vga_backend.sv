// SPDX-License-Identifier: GPL-3.0-only
//
// PmodVGA presentation backend.
//
// The PmodVGA does not get a raster of its own.  It observes the one the HDMI
// transmitter is already producing and derives syncs and a 12-bit colour from
// it, which is how Tang-PSX drives its VGA output and why that output needed no
// second mode and no second clock.  That matters here beyond convenience: an
// 800x600 raster would need a 40 MHz pixel clock, and 74.25 / 40 is not a
// rational-integer ratio, so it could not be produced by a clock enable from
// clk_pixel and would force a real second clock domain, with an async FIFO and
// a duplicated store, through a design whose single clock is the reason its
// bank swap is trivial.
//
// Timing is CEA-861 VIC 4, the same mode the transmitter is configured for:
// 1280x720 active, 1650x750 total, 40-pixel horizontal sync after a 110-pixel
// front porch and 5-line vertical sync after a 5-line front porch, both with
// positive polarity.  The PmodVGA presents that timing through a 12-bit
// resistor ladder whose most significant bit per colour is the largest step,
// so the top four bits of each channel are exactly right.
//
// The colour input is the composition the transmitter is showing, which already
// has its latency compensated, so no second compensation belongs here.

module ui_vga_backend #(
    parameter integer H_ACTIVE = 1280,
    parameter integer H_FRONT  = 110,
    parameter integer H_SYNC   = 40,
    parameter integer V_ACTIVE = 720,
    parameter integer V_FRONT  = 5,
    parameter integer V_SYNC   = 5
) (
    input  logic [11:0] cx,
    input  logic [11:0] cy,
    input  logic [23:0] rgb,
    output logic [3:0]  vga_r,
    output logic [3:0]  vga_g,
    output logic [3:0]  vga_b,
    output logic        vga_hs,
    output logic        vga_vs
);
    localparam integer H_SYNC_END = H_ACTIVE + H_FRONT + H_SYNC;
    localparam integer V_SYNC_END = V_ACTIVE + V_FRONT + V_SYNC;

    // Both syncs are asserted inside their window and nowhere else; the raster
    // covers the whole frame, blanking included, so the windows are absolute.
    assign vga_hs = (cx >= H_ACTIVE + H_FRONT) && (cx < H_SYNC_END);
    assign vga_vs = (cy >= V_ACTIVE + V_FRONT) && (cy < V_SYNC_END);

    // Top four bits per channel: RGB888 down to the ladder's four steps.
    assign vga_r = rgb[23:20];
    assign vga_g = rgb[15:12];
    assign vga_b = rgb[7:4];
endmodule
