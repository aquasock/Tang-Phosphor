// SPDX-License-Identifier: GPL-3.0-only
//
// HDMI presentation backend.
//
// Wraps the project's existing Sameer Puri derived transmitter and the colour
// composition above it.  It owns no pixels: it reads the shared frame store
// through its own scan mapper, exactly as the OLED backend does, and differs
// only in its scale factor, its active rectangle, and its constraints.
//
// The read bank is latched at this backend's own frame boundary.  The swap
// controller flips the shared bank when the last registered output has crossed
// a frame, which need not be this one, so taking the bank combinationally would
// let it change part way through a frame and tear.  Latching here costs one
// frame of latency on an update and removes tearing entirely.

module ui_hdmi_backend (
    input  logic        clk_pixel,
    input  logic        clk_pixel_x5,
    input  logic        resetn,

    // Audio, supplied by the core's test source.
    input  logic        clk_audio,
    input  logic        audio_rate_48k,
    input  logic [15:0] audio_sample_word [1:0],

    // The bank the outputs are reading, latched here at a frame boundary.
    input  logic        bank,
    output logic [6:0]  rd_x,
    output logic [5:0]  rd_y,
    input  logic [15:0] rd_px,

    // One-cycle pulse at the start of each frame, for the swap controller.
    output logic        frame_tick,

    // Single-ended TMDS.  The differential buffer is a vendor primitive and
    // belongs at the top level with the PLLs, so this stays simulatable.
    output logic        tmds_clock,
    output logic [2:0]  tmds
);
    wire [10:0] cx;
    wire [9:0]  cy;
    wire [23:0] rgb;

    wire rst = ~resetn;
    wire frame_start = (cx == 11'd0) && (cy == 10'd0);

    logic rd_bank_l = 1'b0;
    always_ff @(posedge clk_pixel) begin
        if (!resetn)
            rd_bank_l <= 1'b0;
        else if (frame_start)
            rd_bank_l <= bank;
    end

    ui_hdmi_scan #(
        .K(11), .W(96), .H(64), .ACTIVE_X(112), .ACTIVE_Y(8),
        .X_LATENCY(2), .Y_LATENCY(0)
    ) scan (
        .clk    (clk_pixel),
        .rst    (rst),
        .cx     ({1'b0, cx}),
        .cy     ({2'b0, cy}),
        .src_px (rd_px),
        .src_x  (rd_x),
        .src_y  (rd_y),
        .rgb    (rgb)
    );

    hdmi #(
        .VIDEO_ID_CODE(4),
        .DVI_OUTPUT(1'b0),
        .VIDEO_REFRESH_RATE(60.0),
        .IT_CONTENT(1'b1),
        .AUDIO_BIT_WIDTH(16),
        .VENDOR_NAME("aquasock"),
        .PRODUCT_DESCRIPTION("Tang-Phosphor")
    ) hdmi_tx (
        .clk_pixel_x5       (clk_pixel_x5),
        .clk_pixel          (clk_pixel),
        .clk_audio          (clk_audio),
        .audio_rate_48k     (audio_rate_48k),
        .rgb                (rgb),
        .reset              (rst),
        .audio_sample_word  (audio_sample_word),
        .tmds               (tmds),
        .tmds_clock         (tmds_clock),
        .cx                 (cx),
        .cy                 (cy),
        .frame_width        (),
        .frame_height       (),
        .screen_width       (),
        .screen_height      ()
    );

    always_ff @(posedge clk_pixel) begin
        if (!resetn)
            frame_tick <= 1'b0;
        else
            frame_tick <= frame_start;
    end
endmodule
