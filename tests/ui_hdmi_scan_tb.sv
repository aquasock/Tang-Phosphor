// SPDX-License-Identifier: GPL-3.0-only
//
// Self-checking test for the HDMI colour composition.
//
// The transmitter's documented contract is that it samples rgb on the edge
// that presents a coordinate, so this module must present f(cx, cy) for the
// coordinate it is given, with no net delay.  Two registered stages sit inside
// it -- the scan mapper's mapping and the frame store's read -- so the mapper
// is placed two pixels early to cancel them.  This test checks that the
// cancellation is exact for every pixel of a frame, not approximately right:
// each output pixel is compared against the expected source pixel computed
// here from the same store contents, including the bar regions.
`timescale 1ns/1ps

module ui_hdmi_scan_tb;
    localparam int K        = 11;
    localparam int W        = 96;
    localparam int H        = 64;
    localparam int FRAME_W  = 1280;
    localparam int FRAME_H  = 720;
    localparam int ACTIVE_X = 112;
    localparam int ACTIVE_Y = 8;

    logic clk = 1'b0;
    always #6.734 clk = ~clk;           // 74.25 MHz

    int failures = 0;
    int rgb_bad  = 0;
    int desync   = 0;

    // ------------------------------------------------------------------
    // A frame store, modelled: same address order, same registered read.
    // ------------------------------------------------------------------
    logic [15:0] mem [0:W*H-1];
    logic [6:0]  src_x;
    logic [5:0]  src_y;
    logic [15:0] src_px;

    wire [12:0] rd_addr = ({7'd0, src_y} << 6) + ({7'd0, src_y} << 5) + {6'd0, src_x};

    initial begin
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
                mem[y*W + x] = 16'((x << 8) | y);
    end

    // ------------------------------------------------------------------
    // The raster the transmitter presents.
    // ------------------------------------------------------------------
    logic [11:0] cx = 12'd0;
    logic [11:0] cy = 12'd0;
    logic        rst = 1'b1;

    logic [23:0] rgb;

    ui_hdmi_scan #(
        .K(K), .W(W), .H(H), .ACTIVE_X(ACTIVE_X), .ACTIVE_Y(ACTIVE_Y),
        .X_LATENCY(2), .Y_LATENCY(0)
    ) dut (
        .clk    (clk),
        .rst    (rst),
        .cx     (cx),
        .cy     (cy),
        .src_px (src_px),
        .src_x  (src_x),
        .src_y  (src_y),
        .rgb    (rgb)
    );

    always_ff @(posedge clk) begin
        src_px <= mem[rd_addr];
        if (cx == FRAME_W - 1) begin
            cx <= 12'd0;
            cy <= (cy == FRAME_H - 1) ? 12'd0 : cy + 12'd1;
        end else begin
            cx <= cx + 12'd1;
        end
    end

    function automatic logic [23:0] expand565(input logic [15:0] p);
        expand565 = {p[15:11], p[15:13], p[10:5], p[10:9], p[4:0], p[4:2]};
    endfunction

    int checked = 0;
    int bars    = 0;

    initial begin
        repeat (4) @(posedge clk);
        rst <= 1'b0;

        // Align to a frame start rather than assuming where the raster is.
        @(negedge clk);
        while (!(cx == 12'd0 && cy == 12'd0))
            @(negedge clk);

        // One full frame.  Sampling happens at the falling edge, after the
        // rising edge that presented this coordinate, and the coordinate is
        // checked before advancing.
        for (int y = 0; y < FRAME_H; y++) begin
            for (int x = 0; x < FRAME_W; x++) begin
                int want;
                if (cx !== x[11:0] || cy !== y[11:0]) begin
                    desync = desync + 1;
                    if (desync <= 4)
                        $display("FAIL raster desync at (%0d,%0d): saw (%0d,%0d)",
                                 x, y, cx, cy);
                end

                if (x >= ACTIVE_X && x <= ACTIVE_X + K*W - 1 &&
                    y >= ACTIVE_Y && y <= ACTIVE_Y + K*H - 1) begin
                    want = expand565(mem[(y - ACTIVE_Y)/K * W + (x - ACTIVE_X)/K]);
                end else begin
                    want = 24'h000000;
                    bars = bars + 1;
                end
                if ((x == 116 && y == 17) || (x == 112 && y == 8) || (x == 116 && y == 16))
                    $display("DBG (%0d,%0d) cx=%0d cy=%0d src=(%0d,%0d) px=%04h rgb=%06h want=%06h",
                             x, y, cx, cy, src_x, src_y, src_px, rgb, want[23:0]);
                checked = checked + 1;
                if (rgb !== want[23:0]) begin
                    rgb_bad = rgb_bad + 1;
                    if (rgb_bad <= 8)
                        $display("FAIL rgb at (%0d,%0d): got %06h want %06h",
                                 x, y, rgb, want[23:0]);
                end

                @(negedge clk);
            end
        end

        failures = desync + rgb_bad;
        if (failures == 0)
            $display("PASS hdmi scan: %0d pixels, %0d bars, image at (%0d,%0d) at %0dx",
                     checked, bars, ACTIVE_X, ACTIVE_Y, K);
        else
            $display("hdmi_scan: %0d desync, %0d rgb mismatches", desync, rgb_bad);

        if (failures != 0) $fatal(1);
        $finish;
    end

    initial begin
        #200ms;
        $display("FAIL hdmi_scan: timeout");
        $fatal(1);
    end
endmodule
