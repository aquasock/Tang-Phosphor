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

module ui_hdmi_backend #(parameter bit SCOPE_BACKEND = 1'b0) (
    input  logic        clk_pixel,
    input  logic        clk_pixel_x5,
    input  logic        resetn,

    // Audio, supplied by the core's test source.
    input  logic        clk_audio,
    input  logic        audio_rate_48k,
    input  logic [15:0] audio_sample_word [1:0],

    input logic [3:0] scope_control,
    input logic scope_flush, sample_present,
    output logic [31:0] scope_dropped, scope_status, scope_sweeps,

    // The bank the outputs are reading, and the one this backend latched at
    // its own frame boundary, which the store read must use.
    input  logic        bank,
    output logic        read_bank,
    output logic [6:0]  rd_x,
    output logic [5:0]  rd_y,
    input  logic [15:0] rd_px,

    // The raster and colour this backend is producing, so the PmodVGA backend
    // can observe them rather than build a second timing.
    output logic [11:0] raster_x,
    output logic [11:0] raster_y,
    output logic [23:0] raster_rgb,

    // The pixel the transmitter is showing, and whether it is inside the
    // visible window at all.  The VGA observes the same raster, so one stream
    // covers both outputs; they cannot disagree by construction.
    output logic [15:0] emitted_px,
    output logic        emitted_strobe,
    output logic        emitted_frame_end,

    // TinyTang desktop layer: cell writes and enables from iosys, on
    // clk_pixel.  Composited over the whole picture by ui_desk_layer.
    input  logic        desk_we,
    input  logic [6:0]  desk_x,
    input  logic [5:0]  desk_y,
    input  logic [6:0]  desk_ch,
    input  logic [14:0] desk_fg,
    input  logic [14:0] desk_bg,
    input  logic        desk_overlay,
    input  logic        desk_on,

    // One-cycle pulse at the start of each frame, for the swap controller.
    output logic        frame_tick,

    // Single-ended TMDS.  The differential buffer is a vendor primitive and
    // belongs at the top level with the PLLs, so this stays simulatable.
    output logic        tmds_clock,
    output logic [2:0]  tmds
);
    wire [10:0] cx;
    wire [9:0]  cy;
    wire [10:0] frame_width;
    wire [9:0]  frame_height;
    wire [23:0] picture_rgb;
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

    // The store read must use this latched value, not the live one: the swap
    // controller flips the shared bank when the last registered output crosses
    // a frame, which need not be this one, so reading the live bank would let
    // it change part way through a frame.
    assign read_bank = rd_bank_l;

    wire [15:0] scan_px;

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
        .rgb    (picture_rgb),
        .emitted_px (scan_px)
    );

    wire [23:0] scope_rgb;
    wire scope_enabled;
    generate if (SCOPE_BACKEND) begin : g_scope
        scope_xy scope (
            .clk(clk_pixel), .resetn(resetn), .control(scope_control),
            .flush(scope_flush), .audio_tick(clk_audio), .audio_present(sample_present),
            .audio_left(audio_sample_word[0]), .audio_right(audio_sample_word[1]),
            .cx(cx), .cy(cy), .enabled(scope_enabled), .rgb(scope_rgb),
            .dropped(scope_dropped), .status(scope_status), .sweeps(scope_sweeps)
        );
    end else begin : g_no_scope
        assign scope_rgb=0; assign scope_enabled=0;
        assign scope_dropped=0; assign scope_status=0; assign scope_sweeps=0;
    end endgenerate
    wire [23:0] selected_picture = scope_enabled ? scope_rgb : picture_rgb;

    ui_desk_layer desk (
        .clk          (clk_pixel),
        .cx           (cx),
        .cy           (cy),
        .frame_width  (frame_width),
        .frame_height (frame_height),
        .we           (desk_we),
        .wx           (desk_x),
        .wy           (desk_y),
        .wch          (desk_ch),
        .wfg          (desk_fg),
        .wbg          (desk_bg),
        .overlay      (desk_overlay),
        .layer_on     (desk_on),
        .picture_rgb  (selected_picture),
        .rgb          (rgb)
    );

    // The visible window is 1280x720; the raster runs 1650x750 including
    // blanking, and blanking is not part of the picture.
    assign emitted_px     = scope_enabled ? {scope_rgb[23:19],scope_rgb[15:10],scope_rgb[7:3]} : scan_px;
    assign emitted_strobe = (cx < 11'd1280) && (cy < 10'd720);
    // The cycle after the last visible pixel of a frame: no strobe, so the
    // checksum can publish without merging a coincident pixel.
    assign emitted_frame_end = (cx == 11'd1280) && (cy == 10'd719);

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
        .frame_width        (frame_width),
        .frame_height       (frame_height),
        .screen_width       (),
        .screen_height      ()
    );

    assign raster_x   = {1'b0, cx};
    assign raster_y   = {2'b0, cy};
    assign raster_rgb = rgb;

    always_ff @(posedge clk_pixel) begin
        if (!resetn)
            frame_tick <= 1'b0;
        else
            frame_tick <= frame_start;
    end
endmodule
