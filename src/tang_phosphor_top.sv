// Tang-Phosphor bring-up top level for the Tang Console 138K.

module tang_phosphor_top (
    input        sys_clk,

    input        UART_RXD,
    output       UART_TXD,

    inout        usb1_dp,
    inout        usb1_dn,
    inout        usb2_dp,
    inout        usb2_dn,

    output       tmds_clk_p,
    output       tmds_clk_n,
    output [2:0] tmds_d_p,
    output [2:0] tmds_d_n
);

localparam integer LOGIC_FREQ = 74_250_000;
localparam [15:0] CORE_ID = 16'h0050;

wire clk27;
wire clk_pixel;
wire clk_pixel_x5;

pll_27 clock_27mhz (
    .clkin(sys_clk),
    .clkout0(clk27)
);

pll_74 clock_hdmi (
    .clkin(clk27),
    .clkout0(clk_pixel),
    .clkout1(clk_pixel_x5)
);

reg [15:0] reset_counter = 16'hffff;
reg resetn = 1'b0;

always @(posedge clk_pixel) begin
    if (reset_counter != 0)
        reset_counter <= reset_counter - 1'b1;
    else
        resetn <= 1'b1;
end

wire overlay;
wire [7:0] overlay_x;
wire [7:0] overlay_y;
wire [14:0] overlay_color;
wire [15:0] hid1;
wire [15:0] hid2;
wire frame_tick;
wire clk_audio;
wire sample_tick;
wire requested_audio_rate_48k;
wire [31:0] hdmi_audio_rate;
wire hdmi_audio_rate_48k = hdmi_audio_rate == 32'd48_000;
wire [15:0] tone_sample_word [1:0];
wire [15:0] player_audio_left;
wire [15:0] player_audio_right;
wire playback_active;
wire [15:0] audio_sample_word [1:0];

// The two controller-facing USB ports are wired directly to FPGA pins. Use
// the same compact low-speed HID host as the stock Console 138K cores.
wire clk12;
wire pll_lock_12;
wire [11:0] joy_usb1_raw;
wire [11:0] joy_usb2_raw;
wire [1:0] usb_type1_raw;
wire [1:0] usb_type2_raw;
wire usb_error1_raw;
wire usb_error2_raw;
wire [5:0] controller_status_raw = {
    usb_error2_raw, usb_type2_raw, usb_error1_raw, usb_type1_raw
};
reg [11:0] joy_usb1_meta;
reg [11:0] joy_usb1;
reg [11:0] joy_usb2_meta;
reg [11:0] joy_usb2;
reg [5:0] controller_status_meta;
reg [5:0] controller_status;

// Controller reports change many orders of magnitude more slowly than either
// clock. Synchronize them before the 74.25 MHz control/OSD domain uses them.
always @(posedge clk_pixel) begin
    if (!resetn) begin
        joy_usb1_meta <= 0;
        joy_usb1 <= 0;
        joy_usb2_meta <= 0;
        joy_usb2 <= 0;
        controller_status_meta <= 0;
        controller_status <= 0;
    end else begin
        joy_usb1_meta <= joy_usb1_raw;
        joy_usb1 <= joy_usb1_meta;
        joy_usb2_meta <= joy_usb2_raw;
        joy_usb2 <= joy_usb2_meta;
        controller_status_meta <= controller_status_raw;
        controller_status <= controller_status_meta;
    end
end

pll_12 controller_clock (
    .clkin(sys_clk),
    .clkout0(clk12),
    .lock(pll_lock_12)
);

usb_hid_host controller_usb1 (
    .usbclk(clk12),
    .usbrst_n(pll_lock_12),
    .usb_dm(usb1_dn),
    .usb_dp(usb1_dp),
    .game_snes(joy_usb1_raw),
    .typ(usb_type1_raw),
    .conerr(usb_error1_raw)
);

usb_hid_host controller_usb2 (
    .usbclk(clk12),
    .usbrst_n(pll_lock_12),
    .usb_dm(usb2_dn),
    .usb_dp(usb2_dp),
    .game_snes(joy_usb2_raw),
    .typ(usb_type2_raw),
    .conerr(usb_error2_raw)
);

wire debug_valid;
wire debug_write;
wire [31:0] debug_address;
wire [31:0] debug_wdata;
wire [31:0] debug_rdata;
wire [31:0] debug_crc_errors;
wire [31:0] debug_bad_requests;
wire stream_start;
wire stream_end;
wire stream_cancel;
wire [15:0] stream_id;
wire [31:0] stream_offset;
wire [7:0] stream_data;
wire stream_valid;
wire stream_ready;
wire [31:0] stream_sessions;
wire [31:0] stream_bytes;
wire [31:0] stream_ends;
wire [31:0] stream_cancels;
wire [31:0] stream_last_offset;
wire [31:0] stream_crc32;
wire [3:0] player_state;
wire wav_format_valid;
wire [31:0] wav_sample_rate;
wire [11:0] pcm_fifo_level;
wire [31:0] samples_played;
wire [31:0] audio_underruns;
wire [7:0] audio_error;
wire [2:0] detected_format;

// Remain at the proven 48 kHz rate until a supported WAV header is complete.
// The timebase latches and restarts on a change before FIFO prefill can finish.
assign requested_audio_rate_48k = !wav_format_valid ||
    wav_sample_rate == 32'd48_000;

audio_test_source audio_timebase (
    .clk_pixel(clk_pixel),
    .resetn(resetn),
    .rate_48k(requested_audio_rate_48k),
    .clk_audio(clk_audio),
    .sample_tick(sample_tick),
    .active_sample_rate(hdmi_audio_rate),
    .audio_sample_word(tone_sample_word)
);

assign audio_sample_word[0] = playback_active ? player_audio_left : tone_sample_word[0];
assign audio_sample_word[1] = playback_active ? player_audio_right : tone_sample_word[1];

phosphor_video video (
    .resetn(resetn),
    .clk_pixel(clk_pixel),
    .clk_pixel_x5(clk_pixel_x5),
    .clk_audio(clk_audio),
    .audio_rate_48k(hdmi_audio_rate_48k),
    .audio_sample_word(audio_sample_word),
    .overlay(overlay),
    .overlay_x(overlay_x),
    .overlay_y(overlay_y),
    .overlay_color(overlay_color),
    .frame_tick(frame_tick),
    .tmds_clk_p(tmds_clk_p),
    .tmds_clk_n(tmds_clk_n),
    .tmds_d_p(tmds_d_p),
    .tmds_d_n(tmds_d_n)
);

// Keep the proven TangCore control/OSD protocol for early bring-up. The ROM
// stream outputs are intentionally left unused until the transport milestone.
iosys_bl616 #(
    .CORE_ID(CORE_ID),
    .FREQ(LOGIC_FREQ),
    .COLOR_LOGO(15'b11111_01000_11111)
) tangcore_io (
    .clk(clk_pixel),
    .hclk(clk_pixel),
    .resetn(resetn),
    .overlay(overlay),
    .overlay_x(overlay_x),
    .overlay_y(overlay_y),
    .overlay_color(overlay_color),
    .joy1(joy_usb1),
    .joy2(joy_usb2),
    .hid1(hid1),
    .hid2(hid2),
    .debug_valid(debug_valid),
    .debug_write(debug_write),
    .debug_address(debug_address),
    .debug_wdata(debug_wdata),
    .debug_rdata(debug_rdata),
    .debug_crc_errors(debug_crc_errors),
    .debug_bad_requests(debug_bad_requests),
    .stream_start(stream_start),
    .stream_end(stream_end),
    .stream_cancel(stream_cancel),
    .stream_id(stream_id),
    .stream_offset(stream_offset),
    .stream_data(stream_data),
    .stream_valid(stream_valid),
    .stream_ready(stream_ready),
    .mgmt_readdata(16'b0),
    .fdd_request(2'b0),
    .uart_rx(UART_RXD),
    .uart_tx(UART_TXD)
);

wav_stream_player wav_player (
    .clk(clk_pixel), .resetn(resetn),
    .stream_start(stream_start), .stream_end(stream_end),
    .stream_cancel(stream_cancel), .stream_data(stream_data),
    .stream_valid(stream_valid), .stream_ready(stream_ready),
    .sample_tick(sample_tick), .audio_left(player_audio_left),
    .audio_right(player_audio_right), .playback_active(playback_active),
    .player_state(player_state), .format_valid(wav_format_valid),
    .sample_rate(wav_sample_rate), .fifo_level(pcm_fifo_level),
    .samples_played(samples_played), .underrun_count(audio_underruns),
    .error_code(audio_error), .detected_format(detected_format)
);

stream_debug_sink stream_monitor (
    .clk(clk_pixel), .resetn(resetn),
    .stream_start(stream_start), .stream_end(stream_end),
    .stream_cancel(stream_cancel), .stream_id(stream_id),
    .stream_offset(stream_offset), .stream_data(stream_data),
    .stream_valid(stream_valid), .stream_ready(stream_ready),
    .session_count(stream_sessions), .byte_count(stream_bytes),
    .end_count(stream_ends), .cancel_count(stream_cancels),
    .last_offset(stream_last_offset), .stream_crc32(stream_crc32)
);

debug_regs debug_registers (
    .clk(clk_pixel),
    .resetn(resetn),
    .frame_tick(frame_tick),
    .request_valid(debug_valid),
    .request_write(debug_write),
    .request_address(debug_address),
    .request_wdata(debug_wdata),
    .transport_crc_errors(debug_crc_errors),
    .transport_bad_requests(debug_bad_requests),
    .stream_sessions(stream_sessions),
    .stream_bytes(stream_bytes),
    .stream_ends(stream_ends),
    .stream_cancels(stream_cancels),
    .stream_last_offset(stream_last_offset),
    .stream_crc32(stream_crc32),
    .controller1(joy_usb1),
    .controller2(joy_usb2),
    .hid1(hid1),
    .hid2(hid2),
    .controller_status(controller_status),
    .player_state(player_state),
    .wav_format_valid(wav_format_valid),
    .playback_active(playback_active),
    .wav_sample_rate(wav_sample_rate),
    .pcm_fifo_level(pcm_fifo_level),
    .samples_played(samples_played),
    .audio_underruns(audio_underruns),
    .audio_error(audio_error),
    .hdmi_audio_rate(hdmi_audio_rate),
    .detected_format(detected_format),
    .request_rdata(debug_rdata)
);

endmodule
