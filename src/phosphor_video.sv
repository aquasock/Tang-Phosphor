// 720p bring-up video with TangCore's 256x224 OSD composited in the center.

module phosphor_video (
    input resetn,
    input clk_pixel,
    input clk_pixel_x5,

    input overlay,
    output reg [7:0] overlay_x,
    output reg [7:0] overlay_y,
    input [14:0] overlay_color,
    output       frame_tick,

    output       tmds_clk_p,
    output       tmds_clk_n,
    output [2:0] tmds_d_p,
    output [2:0] tmds_d_n
);

localparam integer OSD_LEFT = 160;
localparam integer OSD_RIGHT = 1120;

wire [10:0] cx;
wire [9:0] cy;
assign frame_tick = (cx == 0) && (cy == 0);
reg [23:0] rgb;
reg [23:0] pattern_rgb;
reg osd_active = 1'b0;
reg [10:0] x_accum = 0;
reg [10:0] y_accum = 0;
reg [9:0] sweep_y = 0;

// Fractionally scale TangCore's 256x224 OSD to a centered 960x720 image.
always @(posedge clk_pixel) begin
    if (!resetn) begin
        overlay_x <= 0;
        overlay_y <= 0;
        x_accum <= 0;
        y_accum <= 0;
        osd_active <= 0;
        sweep_y <= 0;
    end else begin
        if (cx == 0) begin
            overlay_x <= 0;
            x_accum <= 0;
            osd_active <= 0;

            if (cy == 0) begin
                overlay_y <= 0;
                y_accum <= 0;
                sweep_y <= (sweep_y == 10'd719) ? 10'd0 : sweep_y + 10'd1;
            end else if (y_accum + 11'd224 >= 11'd720) begin
                y_accum <= y_accum + 11'd224 - 11'd720;
                overlay_y <= overlay_y + 8'd1;
            end else begin
                y_accum <= y_accum + 11'd224;
            end
        end

        if (cx == OSD_LEFT - 1)
            osd_active <= 1'b1;
        else if (cx == OSD_RIGHT - 1)
            osd_active <= 1'b0;

        if (osd_active) begin
            if (x_accum + 11'd256 >= 11'd960) begin
                x_accum <= x_accum + 11'd256 - 11'd960;
                overlay_x <= overlay_x + 8'd1;
            end else begin
                x_accum <= x_accum + 11'd256;
            end
        end
    end
end

// A loud, unmistakable pattern: phosphor-green grid, magenta/cyan side rails,
// an animated scan line, and a central cross visible whenever the OSD is off.
always @* begin
    pattern_rgb = 24'h06100b;

    if (cx < OSD_LEFT)
        pattern_rgb = 24'hb00070;
    else if (cx >= OSD_RIGHT)
        pattern_rgb = 24'h00a0b0;
    else if ((cx[5:0] == 0) || (cy[5:0] == 0))
        pattern_rgb = 24'h164028;

    if ((cx >= 636 && cx <= 643) || (cy >= 356 && cy <= 363))
        pattern_rgb = 24'h40ff80;

    if ((cy == sweep_y) || (cy == sweep_y + 10'd1))
        pattern_rgb = 24'hffffff;

    if (cy < 8 || cy >= 712)
        pattern_rgb = 24'h40ff80;
end

always @(posedge clk_pixel) begin
    if (overlay && osd_active)
        rgb <= {overlay_color[4:0], 3'b0,
                overlay_color[9:5], 3'b0,
                overlay_color[14:10], 3'b0};
    else
        rgb <= pattern_rgb;
end

logic [2:0] tmds;
logic tmds_clock;
logic [15:0] silence [1:0];
logic clk_audio = 1'b0;
logic [9:0] audio_divider = 0;
assign silence[0] = 16'b0;
assign silence[1] = 16'b0;

// Clock the HDMI audio packetizer at approximately 48 kHz. The first audio
// milestone will replace the silent samples with a generated test tone.
always @(posedge clk_pixel) begin
    if (audio_divider == 10'd772) begin
        audio_divider <= 0;
        clk_audio <= ~clk_audio;
    end else begin
        audio_divider <= audio_divider + 1'b1;
    end
end

hdmi #(
    .VIDEO_ID_CODE(4),
    .DVI_OUTPUT(1'b0),
    .VIDEO_REFRESH_RATE(60.0),
    .IT_CONTENT(1'b1),
    .AUDIO_RATE(48000),
    .AUDIO_BIT_WIDTH(16),
    .VENDOR_NAME("aquasock"),
    .PRODUCT_DESCRIPTION("Tang-Phosphor")
) hdmi_tx (
    .clk_pixel_x5(clk_pixel_x5),
    .clk_pixel(clk_pixel),
    .clk_audio(clk_audio),
    .rgb(rgb),
    .reset(~resetn),
    .audio_sample_word(silence),
    .tmds(tmds),
    .tmds_clock(tmds_clock),
    .cx(cx),
    .cy(cy),
    .frame_width(),
    .frame_height(),
    .screen_width(),
    .screen_height()
);

ELVDS_OBUF tmds_output [3:0] (
    .I({clk_pixel, tmds}),
    .O({tmds_clk_p, tmds_d_p}),
    .OB({tmds_clk_n, tmds_d_n})
);

endmodule
