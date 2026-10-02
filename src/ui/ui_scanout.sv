// SPDX-License-Identifier: GPL-3.0-only
//
// Output coordinate to frame-store coordinate, for one presentation backend.
//
// This is the whole of the integer upscaler: output pixel (x, y) shows source
// pixel ((x - X0) / K, (y - Y0) / K), and every output pixel outside the
// scaled rectangle is a bar.  Division by K is a pair of mod-K counters rather
// than a divider, so the scale factor costs two small counters and no
// arithmetic in the raster path.  Nothing here filters, blends or interpolates,
// because nothing here needs to: an integer factor maps each source pixel onto
// exactly K x K output pixels.
//
// Contract: src_x/src_y are registered, and they describe the coordinate the
// backend presented one output pixel earlier.  A paced backend such as the
// OLED engine, which holds a coordinate for a whole 16-bit transfer, never
// notices.  A backend with a dense raster, one output pixel per clock, must
// delay its own coordinate by one pixel to compare against these, which it has
// to do anyway to line up with the frame store's registered read.
//
// The counters therefore follow the coordinate being presented now, and the
// backend's raster supplies its own pacing: a coordinate is only consumed once
// its value has changed, so a panel that holds a coordinate for sixteen clocks
// advances the mapping exactly once.
//
// The mapper follows the coordinate as presented, so it needs no knowledge of
// the backend's raster beyond the coordinate itself.
//
// K = 1 makes this an identity, which is how the OLED backend uses it.

module ui_scanout #(
    parameter integer K  = 1,
    parameter integer W  = 96,
    parameter integer H  = 64,
    parameter integer X0 = 0,
    parameter integer Y0 = 0
) (
    input  logic        clk,
    input  logic        rst,
    input  logic [11:0] out_x,
    input  logic [11:0] out_y,
    output logic        in_image,
    output logic [6:0]  src_x,
    output logic [5:0]  src_y
);
    localparam [11:0] X0V   = X0;
    localparam [11:0] Y0V   = Y0;
    localparam [11:0] XLAST = X0 + K * W - 1;
    localparam [11:0] YLAST = Y0 + K * H - 1;
    localparam [4:0]  KM1   = K - 1;

    logic [4:0]  hc;        // horizontal position within the current source pixel
    logic [4:0]  vc;        // vertical position within the current source row
    logic [11:0] out_x_q;
    logic [11:0] out_y_q;

    wire in_x = (out_x >= X0V) && (out_x <= XLAST);
    wire in_y = (out_y >= Y0V) && (out_y <= YLAST);

    assign in_image = in_x && in_y;

    always_ff @(posedge clk) begin
        if (rst) begin
            hc      <= 5'd0;
            vc      <= 5'd0;
            src_x   <= 7'd0;
            src_y   <= 6'd0;
            out_x_q <= 12'd0;
            out_y_q <= 12'd0;
        end else begin
            out_x_q <= out_x;
            out_y_q <= out_y;

            // Horizontal: the image's first column resets the column counter,
            // and the source column advances every K pixels after that.
            if (out_x != out_x_q) begin
                if (out_x == X0V) begin
                    hc    <= 5'd0;
                    src_x <= 7'd0;
                end else if (in_x) begin
                    if (hc == KM1) begin
                        hc    <= 5'd0;
                        src_x <= src_x + 7'd1;
                    end else begin
                        hc <= hc + 5'd1;
                    end
                end
            end

            // Vertical: one step per line, since a coordinate now changes once
            // per line in each of the two rasters this feeds.
            if (out_y != out_y_q) begin
                if (out_y == Y0V) begin
                    vc    <= 5'd0;
                    src_y <= 6'd0;
                end else if (in_y) begin
                    if (vc == KM1) begin
                        vc    <= 5'd0;
                        src_y <= src_y + 6'd1;
                    end else begin
                        vc <= vc + 5'd1;
                    end
                end
            end
        end
    end
endmodule
