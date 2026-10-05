// SPDX-License-Identifier: GPL-3.0-only
//
// TinyTang desktop layer over the HDMI picture.
//
// TinyDesk draws an 80x45 cell grid into textdisp_wide through iosys commands
// 0x13-0x15, and this puts it on screen in place of the player's picture
// whenever both the TangCore overlay (command 0x08, which F12 flips) and the
// layer's own enable are set.  It covers the whole 1280x720 output, so the
// picture underneath is either fully shown or fully replaced.
//
// Alignment.  The transmitter samples `rgb` on the same edge it samples the
// coordinate's visibility, so the colour presented with (cx, cy) must belong
// to (cx, cy) itself -- ui_hdmi_scan's convention.  textdisp_wide's `color` is
// already the pixel for the coordinate being presented now (it addresses its
// store four pixels ahead), so it is selected combinationally here and adds
// no register to the path.
//
// Clocks.  The write port and the scanout share clk_pixel in this core, so the
// enable needs no synchroniser.

module ui_desk_layer (
    input  logic        clk,

    // Raster, as the transmitter produces it.
    input  logic [10:0] cx,
    input  logic [9:0]  cy,
    input  logic [10:0] frame_width,
    input  logic [9:0]  frame_height,

    // Cell write port and enables, from iosys.
    input  logic        we,
    input  logic [6:0]  wx,
    input  logic [5:0]  wy,
    input  logic [6:0]  wch,
    input  logic [14:0] wfg,
    input  logic [14:0] wbg,
    input  logic        overlay,
    input  logic        layer_on,

    input  logic [23:0] picture_rgb,
    output logic [23:0] rgb
);
    wire [14:0] color;

    textdisp_wide layer (
        .clk          (clk),
        .hclk         (clk),
        .we           (we),
        .wx           (wx),
        .wy           (wy),
        .wch          (wch),
        .wfg          (wfg),
        .wbg          (wbg),
        .cx           (cx),
        .cy           (cy),
        .frame_width  (frame_width),
        .frame_height (frame_height),
        .color        (color)
    );

    // BGR5 to RGB8, the widening nestang's compositor uses for the same cells.
    function automatic logic [23:0] expand_bgr5(input logic [14:0] c);
        expand_bgr5 = {c[4:0], 3'b000, c[9:5], 3'b000, c[14:10], 3'b000};
    endfunction

    always_comb rgb = (overlay && layer_on) ? expand_bgr5(color) : picture_rgb;
endmodule
