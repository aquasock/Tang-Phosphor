// Tang-Phosphor bring-up top level for the Tang Console 138K.

module tang_phosphor_top (
    input        sys_clk,

    // PMOD sockets.  Driven by the display stack: what each socket does is a
    // runtime declaration, so these are the only pins the top owns for them.
    inout        [7:0] pmod0_io,
    inout        [7:0] pmod1_io,

    input        UART_RXD,
    output       UART_TXD,

    inout        usb1_dp,
    inout        usb1_dn,
    inout        usb2_dp,
    inout        usb2_dn,

    output       tmds_clk_p,
    output       tmds_clk_n,
    output [2:0] tmds_d_p,
    output [2:0] tmds_d_n,

    output logic [14:0] ddr_addr,
    output logic [2:0]  ddr_bank,
    output logic        ddr_cs,
    output logic        ddr_ras,
    output logic        ddr_cas,
    output logic        ddr_we,
    output logic        ddr_ck,
    output logic        ddr_ck_n,
    output logic        ddr_cke,
    output logic        ddr_odt,
    output logic        ddr_reset_n,
    output logic [3:0]  ddr_dm,
    inout  wire  [31:0] ddr_dq,
    inout  wire  [3:0]  ddr_dqs,
    inout  wire  [3:0]  ddr_dqs_n
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
// Replicated by synthesis: one register otherwise drives the synchronous
// reset of every player block across the die.
reg resetn /* synthesis syn_maxfan = 32 */ = 1'b0;

always @(posedge clk_pixel) begin
    if (reset_counter != 0)
        reset_counter <= reset_counter - 1'b1;
    else
        resetn <= 1'b1;
end

assign overlay_x = 8'd0;
assign overlay_y = 8'd0;

wire        display_tmds_clock;
wire [2:0]  display_tmds;
wire [31:0] mirror_src_signature, mirror_hdmi_signature, mirror_panel_signature;
wire [31:0] mirror_render_frames, mirror_oled_frames, mirror_hdmi_frames;
wire [2:0]  mirror_pattern;
wire        mirror_source_bank;

// Socket declaration, seating orientation and renderer hold, written by the
// debug register block and carried into the core; plus the encoder state the
// core hands back.  Declared explicitly rather than left implicit, because
// this tool gives an undeclared net connected to a module port a width of one,
// which silently truncated all of it: the 4-bit personality 4 became 0, so the
// encoder's socket was never declared, and the 32-bit count -- always a
// multiple of four, so always zero in bit 0 -- read back as zero no matter what
// the knob did.  The build log names every one of these wires; they were
// harmless only while they were dead ends.  The OLED worked throughout on luck:
// personality 1 happens to fit in one bit.
// (overlay_x/overlay_y are the same hazard and are left implicit: both are tied
// to a constant and never carry a value.)
wire [3:0]  display_pmod0_personality, display_pmod1_personality;
wire        display_pmod0_flipped, display_pmod1_flipped, display_hold;
wire [31:0] enc_count;
wire [3:0]  enc_raw;
wire        enc_button, enc_switch;

wire overlay;
wire [7:0] overlay_x;
wire [7:0] overlay_y;
wire [14:0] overlay_color;
// TinyTang desktop layer, from iosys to the HDMI compositor.
wire        wide_we;
wire [6:0]  wide_x;
wire [5:0]  wide_y;
wire [6:0]  wide_ch;
wire [14:0] wide_fg;
wire [14:0] wide_bg;
wire        wide_on;
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
// Keep both synchronizer stages in flip-flops. Revision-C synthesis otherwise
// folds each two-stage chain into an SSRAM shift register, which provides no
// metastability protection and escapes the first-stage false path.
reg [11:0] joy_usb1_meta /* synthesis syn_srlstyle = "registers" */;
reg [11:0] joy_usb1 /* synthesis syn_srlstyle = "registers" */;
reg [11:0] joy_usb2_meta /* synthesis syn_srlstyle = "registers" */;
reg [11:0] joy_usb2 /* synthesis syn_srlstyle = "registers" */;
reg [5:0] controller_status_meta /* synthesis syn_srlstyle = "registers" */;
reg [5:0] controller_status /* synthesis syn_srlstyle = "registers" */;

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

// TinyTang keyboard link.  The keyboard drives its own USB D+ line as a GPIO
// UART from Tang firmware, and this reads it.  Port 1's low-speed HID host is
// displaced because both need usb1_dp; the gamepad on port 2 is untouched.
wire [7:0]  link_mods;
wire [7:0]  link_keys [6];
wire        link_valid;
wire [31:0] link_frames;
wire [31:0] link_bad_checksum;
wire [31:0] link_truncated;

keylink_rx #(
    .CLK_HZ (74_250_000),
    .BAUD   (281_250)
) keyboard_link (
    .clk            (clk_pixel),
    .resetn         (resetn),
    .rx             (usb1_dp),
    .o_modifiers    (link_mods),
    .o_keys         (link_keys),
    .o_valid        (link_valid),
    .o_frames       (link_frames),
    .o_bad_checksum (link_bad_checksum),
    .o_truncated    (link_truncated)
);

// Pointer mode, as in the NES core: while left-alt (HID modifier bit 2) is
// held, the arrows, Enter and Esc become the desktop pointer's pad bits and
// are withheld from the typed report; released, the keyboard only types.
// Both halves are needed because these keycodes reach the BL616 twice, once
// in the pad word and once in the keyboard report.
wire link_pointer_mode = link_mods[2];

function [11:0] link_key_to_pad;
    input [7:0] k;
    begin
        case (k)
            8'h52:   link_key_to_pad = 12'b0000_0001_0000;  // Up    -> bit 4
            8'h51:   link_key_to_pad = 12'b0000_0010_0000;  // Down  -> bit 5
            8'h50:   link_key_to_pad = 12'b0000_0100_0000;  // Left  -> bit 6
            8'h4F:   link_key_to_pad = 12'b0000_1000_0000;  // Right -> bit 7
            8'h28:   link_key_to_pad = 12'b0001_0000_0000;  // Enter -> A, left click
            8'h29:   link_key_to_pad = 12'b0000_0000_0001;  // Esc   -> B, right click
            default: link_key_to_pad = 12'b0000_0000_0000;
        endcase
    end
endfunction

function [7:0] link_withhold_if_pointer;
    input [7:0] k;
    begin
        if (link_pointer_mode &&
            (k == 8'h52 || k == 8'h51 || k == 8'h50 || k == 8'h4F ||
             k == 8'h28 || k == 8'h29))
            link_withhold_if_pointer = 8'd0;
        else
            link_withhold_if_pointer = k;
    end
endfunction

// The report relayed to the BL616 as response 0x08, key 0 in the low byte.
wire [47:0] link_report_keys = {
    link_withhold_if_pointer(link_keys[5]), link_withhold_if_pointer(link_keys[4]),
    link_withhold_if_pointer(link_keys[3]), link_withhold_if_pointer(link_keys[2]),
    link_withhold_if_pointer(link_keys[1]), link_withhold_if_pointer(link_keys[0])
};

// Registered before iosys: unregistered, the six keycode compares above fed
// iosys's 56-bit change compare and the bottom of its transmit arbiter in one
// clk_pixel cycle, which failed timing at three placements of four (entry 71).
// One pixel clock is nothing to a report sent at most every 20 ms.
reg [7:0]  link_report_mods_q = 8'd0;
reg [47:0] link_report_keys_q = 48'd0;
always @(posedge clk_pixel) begin
    link_report_mods_q <= link_mods;
    link_report_keys_q <= link_report_keys;
end

// The pad word still passes through the clk_pixel synchroniser below: leaving
// it driven by the link keeps joy_usb1_meta from being swept, which
// console138k_merged.sdc needs to bind its first-stage false path.
assign joy_usb1_raw   = link_pointer_mode
                      ? (link_key_to_pad(link_keys[0]) | link_key_to_pad(link_keys[1])
                       | link_key_to_pad(link_keys[2]) | link_key_to_pad(link_keys[3])
                       | link_key_to_pad(link_keys[4]) | link_key_to_pad(link_keys[5]))
                      : 12'b0;
assign usb_type1_raw  = {link_valid, link_mods[7]};
assign usb_error1_raw = |link_bad_checksum;

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
wire [31:0] player_debug_rdata;
wire [31:0] ae350_debug_rdata;
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
wire player_stream_start;
wire player_stream_end;
wire player_stream_cancel;
wire player_stream_valid;
wire player_stream_ready;
wire [7:0] player_stream_data;
wire [15:0] player_stream_id;
wire cpu_play_start;
wire cpu_play_end;
wire cpu_play_cancel;
wire [7:0] cpu_play_data;
wire cpu_play_valid;
wire [15:0] cpu_play_id;
wire [31:0] cpu_play_rate;
wire cpu_stream_start;
wire cpu_stream_end;
wire cpu_stream_cancel;
wire cpu_stream_valid;
wire cpu_stream_ready;
wire [31:0] stream_sessions;
wire [31:0] stream_bytes;
wire [31:0] stream_ends;
wire [31:0] stream_cancels;
wire [31:0] stream_last_offset;
wire [31:0] stream_crc32;
wire [3:0] player_state;
wire audio_format_valid;
wire [31:0] audio_sample_rate;
wire [14:0] pcm_fifo_level;
wire [31:0] samples_played;
wire [31:0] audio_underruns;
wire [7:0] audio_error;
wire [2:0] detected_format;
wire pause_requested;
wire ui_visible;
wire ui_playlist;
wire [7:0] ui_current_track;
wire [7:0] ui_track_count;
wire [7:0] ui_window_start;
wire [31:0] ui_lengths_0_3;
wire [31:0] ui_lengths_4_7;
wire [7:0] ui_length_8;
wire [8:0] ui_text_address;
wire [7:0] ui_text_data;
wire ui_artwork_valid;
wire [13:0] ui_artwork_address;
wire [7:0] ui_artwork_data;
wire [35:0] total_samples;
wire [31:0] elapsed_seconds;
wire [31:0] duration_seconds;
wire playback_rate_valid;
wire [31:0] playback_rate;
wire [15:0] audible_stream_id;
wire [31:0] boundary_count;
wire [31:0] boundary_gap_samples;

audio_output_policy output_policy (
    .clk(clk_pixel),
    .resetn(resetn),
    .stream_start(stream_start),
    .format_valid(playback_rate_valid),
    .sample_rate(playback_rate),
    .playback_active(playback_active),
    .player_left(player_audio_left),
    .player_right(player_audio_right),
    .diagnostic_left(tone_sample_word[0]),
    .diagnostic_right(tone_sample_word[1]),
    .rate_48k(requested_audio_rate_48k),
    .output_left(audio_sample_word[0]),
    .output_right(audio_sample_word[1])
);

audio_test_source audio_timebase (
    .clk_pixel(clk_pixel),
    .resetn(resetn),
    .rate_48k(requested_audio_rate_48k),
    .clk_audio(clk_audio),
    .sample_tick(sample_tick),
    .active_sample_rate(hdmi_audio_rate),
    .audio_sample_word(tone_sample_word)
);

// The display stack, folded in whole.  This is the same module the socket
// bring-up core runs, with its transport off because this design already has
// one, and its audio taken from the player's decoder rather than an internal
// test tone.  Everything else -- one frame store, a scan mapper per backend,
// the socket layer, the personalities, the checksums and the bank swap --
// comes with it, which is why the fold is an instantiation rather than a port.
pmod_mirror_core #(
    .HDMI_BACKEND   (1'b1),
    .TRANSPORT      (1'b0),
    .EXTERNAL_AUDIO (1'b1),
    .EXPOSE_STATE   (1'b1)
) display (
    .clk_pixel          (clk_pixel),
    .clk_pixel_x5       (clk_pixel_x5),
    .resetn             (resetn),
    .uart_rx            (1'b1),
    .uart_tx            (),
    .frame_tick_in      (1'b0),
    .clk_audio_in       (clk_audio),
    .audio_rate_48k_in  (hdmi_audio_rate_48k),
    .audio_sample_word_in (audio_sample_word),
    .pmod0_io           (pmod0_io),
    .pmod1_io           (pmod1_io),
    .tmds_clock         (display_tmds_clock),
    .tmds               (display_tmds),
    .o_src_signature    (mirror_src_signature),
    .o_hdmi_signature   (mirror_hdmi_signature),
    .o_panel_signature  (mirror_panel_signature),
    .o_render_frames    (mirror_render_frames),
    .o_oled_frames      (mirror_oled_frames),
    .o_hdmi_frames      (mirror_hdmi_frames),
    .o_pattern          (mirror_pattern),
    .o_frame_tick       (frame_tick),
    .o_source_bank      (mirror_source_bank),
    // The player owns the register bank, so the socket declaration, the seating
    // orientation and the renderer hold are written here and carried in; the
    // mirror state and the encoder state come back out to be read here.
    .i_pmod0_personality(display_pmod0_personality),
    .i_pmod1_personality(display_pmod1_personality),
    .i_pmod0_flipped    (display_pmod0_flipped),
    .i_pmod1_flipped    (display_pmod1_flipped),
    .i_render_hold      (display_hold),
    .i_desk_we          (wide_we),
    .i_desk_x           (wide_x),
    .i_desk_y           (wide_y),
    .i_desk_ch          (wide_ch),
    .i_desk_fg          (wide_fg),
    .i_desk_bg          (wide_bg),
    .i_desk_overlay     (overlay),
    .i_desk_on          (wide_on),
    .o_enc_count        (enc_count),
    .o_enc_raw          (enc_raw),
    .o_enc_button       (enc_button),
    .o_enc_switch       (enc_switch)
);

ELVDS_OBUF display_tmds_output [3:0] (
    .I  ({clk_pixel, display_tmds}),
    .O  ({tmds_clk_p, tmds_d_p}),
    .OB ({tmds_clk_n, tmds_d_n})
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
    .wide_x(wide_x),
    .wide_y(wide_y),
    .wide_ch(wide_ch),
    .wide_fg(wide_fg),
    .wide_bg(wide_bg),
    .wide_we(wide_we),
    .wide_on(wide_on),
    .link_mods(link_report_mods_q),
    .link_keys(link_report_keys_q),
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

pcm_sink audio_player (
    .clk(clk_pixel), .resetn(resetn),
    .stream_start(player_stream_start), .stream_end(player_stream_end),
    .stream_cancel(player_stream_cancel), .stream_id(player_stream_id),
    .stream_data(player_stream_data),
    .stream_valid(player_stream_valid), .stream_ready(player_stream_ready),
    .play_rate(cpu_play_rate),
    .sample_tick(sample_tick), .paused(pause_requested),
    .audio_left(player_audio_left),
    .audio_right(player_audio_right), .playback_active(playback_active),
    .player_state(player_state), .format_valid(audio_format_valid),
    .sample_rate(audio_sample_rate), .fifo_level(pcm_fifo_level),
    .samples_played(samples_played), .total_samples(total_samples),
    .elapsed_seconds(elapsed_seconds), .duration_seconds(duration_seconds),
    .underrun_count(audio_underruns),
    .error_code(audio_error), .detected_format(detected_format),
    .playback_rate_valid(playback_rate_valid), .playback_rate(playback_rate),
    .audible_stream_id(audible_stream_id),
    .boundary_count(boundary_count),
    .boundary_gap_samples(boundary_gap_samples)
);

phosphor_ui_control ui_control (
    .clk(clk_pixel), .resetn(resetn),
    .request_valid(debug_valid), .request_write(debug_write),
    .request_address(debug_address), .request_wdata(debug_wdata),
    .pause_requested(pause_requested), .ui_visible(ui_visible),
    .playlist(ui_playlist), .current_track(ui_current_track),
    .track_count(ui_track_count), .window_start(ui_window_start),
    .lengths_0_3(ui_lengths_0_3), .lengths_4_7(ui_lengths_4_7),
    .length_8(ui_length_8), .text_address(ui_text_address),
    .text_data(ui_text_data), .artwork_valid(ui_artwork_valid),
    .artwork_address(ui_artwork_address), .artwork_data(ui_artwork_data)
);

stream_debug_sink stream_monitor (
    .clk(clk_pixel), .resetn(resetn),
    .stream_start(player_stream_start), .stream_end(player_stream_end),
    .stream_cancel(player_stream_cancel), .stream_id(player_stream_id),
    .stream_offset(stream_offset), .stream_data(player_stream_data),
    .stream_valid(player_stream_valid), .stream_ready(player_stream_ready),
    .session_count(stream_sessions), .byte_count(stream_bytes),
    .end_count(stream_ends), .cancel_count(stream_cancels),
    .last_offset(stream_last_offset), .stream_crc32(stream_crc32)
);

// Stream routing, owned by debug_regs at 0xa8 and declared before use: an
// implicit net here would be one bit wide by accident rather than by design.
wire cpu_mode;

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
    .audio_format_valid(audio_format_valid),
    .playback_active(playback_active),
    .audio_sample_rate(audio_sample_rate),
    .pcm_fifo_level(pcm_fifo_level),
    .samples_played(samples_played),
    .audio_underruns(audio_underruns),
    .audio_error(audio_error),
    .hdmi_audio_rate(hdmi_audio_rate),
    .detected_format(detected_format),
    .pause_requested(pause_requested),
    .ui_visible(ui_visible),
    .ui_playlist(ui_playlist),
    .ui_current_track(ui_current_track),
    .ui_track_count(ui_track_count),
    .ui_window_start(ui_window_start),
    .elapsed_seconds(elapsed_seconds),
    .duration_seconds(duration_seconds),
    .boundary_count(boundary_count),
    .boundary_gap_samples(boundary_gap_samples),
    .audible_stream_id(audible_stream_id),
    .src_signature(mirror_src_signature),
    .hdmi_signature(mirror_hdmi_signature),
    .oled_signature(mirror_panel_signature),
    .render_frames(mirror_render_frames),
    .oled_frames(mirror_oled_frames),
    .hdmi_frames(mirror_hdmi_frames),
    .render_pattern(mirror_pattern),
    .source_bank(mirror_source_bank),
    .enc_count(enc_count),
    .enc_raw(enc_raw),
    .enc_button(enc_button),
    .enc_switch(enc_switch),
    .link_frames(link_frames),
    .link_bad_checksum(link_bad_checksum),
    .link_truncated(link_truncated),
    .link_mods(link_mods),
    .link_key0(link_keys[0]),
    .link_key1(link_keys[1]),
    .pmod0_personality(display_pmod0_personality),
    .pmod1_personality(display_pmod1_personality),
    .pmod0_flipped(display_pmod0_flipped),
    .pmod1_flipped(display_pmod1_flipped),
    .render_hold(display_hold),
    .cpu_mode(cpu_mode),
    .request_rdata(player_debug_rdata)
);

// ---------------------------------------------------------------------------
// AE350 + DDR3 subsystem and single-transport sharing.
//
// The BL616 transport feeds the FPGA player by default (cpu_mode = 0).
// Writing bit 0 of debug register 0x00a8 selects the CPU: the stream then
// goes to the AE350 program loader, the player takes the AE350's play
// stream instead, and the AE350 debug view appears at 0x4000-0x43ff (the
// subsystem's 1 KiB view aliases every 1 KiB; this window gates it away from
// the player's 0x0000-0x3fff registers).
// ---------------------------------------------------------------------------
wire in_ae350_window = debug_address[15:10] == 6'b01_0000;
wire cpu_debug_valid = debug_valid && in_ae350_window;

assign player_stream_start  = cpu_mode ? cpu_play_start  : stream_start;
assign player_stream_end    = cpu_mode ? cpu_play_end    : stream_end;
assign player_stream_cancel = cpu_mode ? cpu_play_cancel : stream_cancel;
assign player_stream_valid  = cpu_mode ? cpu_play_valid  : stream_valid;
assign player_stream_data   = cpu_mode ? cpu_play_data   : stream_data;
assign player_stream_id     = cpu_mode ? cpu_play_id     : stream_id;

assign cpu_stream_start  = cpu_mode ? stream_start  : 1'b0;
assign cpu_stream_end    = cpu_mode ? stream_end    : 1'b0;
assign cpu_stream_cancel = cpu_mode ? stream_cancel : 1'b0;
assign cpu_stream_valid  = cpu_mode ? stream_valid  : 1'b0;

assign stream_ready = cpu_mode ? cpu_stream_ready : player_stream_ready;

// Registered for timing: iosys_bl616 samples debug_rdata six UART bytes after
// it sets debug_address.
reg [31:0] debug_rdata_q = 32'd0;
always @(posedge clk_pixel)
    debug_rdata_q <= in_ae350_window ? ae350_debug_rdata : player_debug_rdata;
assign debug_rdata = debug_rdata_q;

ae350_subsystem cpu_subsystem (
    .clk           (sys_clk),
    .tclk          (clk_pixel),
    .ddr_addr      (ddr_addr),
    .ddr_bank      (ddr_bank),
    .ddr_cs        (ddr_cs),
    .ddr_ras       (ddr_ras),
    .ddr_cas       (ddr_cas),
    .ddr_we        (ddr_we),
    .ddr_ck        (ddr_ck),
    .ddr_ck_n      (ddr_ck_n),
    .ddr_cke       (ddr_cke),
    .ddr_odt       (ddr_odt),
    .ddr_reset_n   (ddr_reset_n),
    .ddr_dm        (ddr_dm),
    .ddr_dq        (ddr_dq),
    .ddr_dqs       (ddr_dqs),
    .ddr_dqs_n     (ddr_dqs_n),
    .stream_start  (cpu_stream_start),
    .stream_end    (cpu_stream_end),
    .stream_cancel (cpu_stream_cancel),
    .stream_data   (stream_data),
    .stream_valid  (cpu_stream_valid),
    .stream_ready  (cpu_stream_ready),
    .play_start    (cpu_play_start),
    .play_end      (cpu_play_end),
    .play_cancel   (cpu_play_cancel),
    .play_data     (cpu_play_data),
    .play_valid    (cpu_play_valid),
    .play_ready    (player_stream_ready && cpu_mode),
    .play_id       (cpu_play_id),
    .play_rate     (cpu_play_rate),
    .debug_valid   (cpu_debug_valid),
    .debug_write   (debug_write),
    .debug_address (debug_address),
    .debug_wdata   (debug_wdata),
    .debug_rdata   (ae350_debug_rdata)
);

endmodule
