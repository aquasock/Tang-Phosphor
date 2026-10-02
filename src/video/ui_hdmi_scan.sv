// SPDX-License-Identifier: GPL-3.0-only
//
// The HDMI presentation backend's colour composition.
//
// Kept apart from the transmitter so that the geometry can be tested with a
// synthetic raster instead of a full TMDS simulation.  The transmitter owns the
// timing and presents a coordinate; this module turns a frame-store pixel and
// that coordinate into the 24-bit colour the transmitter samples.
//
// Latency compensation.  Registered stages sit between the coordinate and the
// pixel, and the mapper is placed that many pixels earlier so the arithmetic
// comes out exact rather than approximate: with the mapper at X0 - X_LATENCY,
// the source column for display column u is
// ((u - X_LATENCY) - (X0 - X_LATENCY)) / K, which is (u - X0) / K.  The same
// argument applies vertically with its own constant, and the two constants
// differ because the two coordinate rates differ.

module ui_hdmi_scan #(
    parameter integer K        = 11,
    parameter integer W        = 96,
    parameter integer H        = 64,
    parameter integer ACTIVE_X = 112,
    parameter integer ACTIVE_Y = 8,
    // Registered stages between the coordinate and the pixel, which differ per
    // axis and are not a single number:
    //
    //   * Horizontally the coordinate changes every clock, so the mapper's
    //     registered mapping is one pixel behind and the store's registered
    //     read puts the pixel one further behind: two pixels.
    //   * Vertically the coordinate changes once per line, so the mapper's
    //     register is already aligned with the line it belongs to, and the
    //     store's read returns the same line's pixel because the address is
    //     constant across it: no correction at all.
    //
    // Treating both axes the same shifts the image up by one whole source row.
    parameter integer X_LATENCY = 2,
    parameter integer Y_LATENCY = 0
) (
    input  logic        clk,
    input  logic        rst,
    input  logic [11:0] cx,
    input  logic [11:0] cy,
    input  logic [15:0] src_px,     // the frame store's registered read output
    output logic [6:0]  src_x,
    output logic [5:0]  src_y,
    output logic [23:0] rgb
);
    wire in_image;

    ui_scanout #(
        .K(K), .W(W), .H(H),
        .X0(ACTIVE_X - X_LATENCY), .Y0(ACTIVE_Y - Y_LATENCY)
    ) map (
        .clk      (clk),
        .rst      (rst),
        .out_x    (cx),
        .out_y    (cy),
        .in_image (in_image),
        .src_x    (src_x),
        .src_y    (src_y)
    );

    // The bar decision is taken from the coordinate the transmitter presents
    // now, combinationally, because the colour presented must belong to that
    // coordinate.  Only the pixel itself needs the mapper's compensation, and
    // the mask keeps a stale pixel from leaking into a bar.
    localparam [11:0] X_END = ACTIVE_X + K * W - 1;
    localparam [11:0] Y_END = ACTIVE_Y + K * H - 1;

    wire in_rect = (cx >= ACTIVE_X[11:0]) && (cx <= X_END) &&
                   (cy >= ACTIVE_Y[11:0]) && (cy <= Y_END);

    // RGB565 to RGB888 by bit replication, so the panel's exact 16-bit value
    // and the HDMI's 24-bit value describe the same colour.
    function automatic logic [23:0] expand565(input logic [15:0] p);
        expand565 = {p[15:11], p[15:13], p[10:5], p[10:9], p[4:0], p[4:2]};
    endfunction

    always_comb rgb = in_rect ? expand565(src_px) : 24'h000000;
endmodule
