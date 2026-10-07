// SPDX-License-Identifier: GPL-3.0-only
//
// The mirrored video demo's logic, without its clocks.
//
// Split from the top level so it can be simulated: the top level instantiates
// Gowin PLL primitives, which no simulator here can elaborate, while this
// module takes the pixel clock as an input.  The same split that put the panel
// protocol behind a port for the OLED core.
//
// One renderer fills a frame store; every presentation backend reads that store
// through its own scan mapper and differs only in its integer scale factor and
// its constraints.  Adding HDMI was therefore a backend and a constraint file,
// not a second copy of the image, and adding VGA will be the same again.
//
// Everything runs on clk_pixel: the renderer, both store read ports, the OLED
// engine and the HDMI transmitter.  Sharing one clock is deliberate -- it
// removes every clock-domain crossing between the backends, which is what makes
// the bank swap and the frame ticks trivially coherent.
//
// Socket configuration is a parameter for now.  Physical seating cannot be
// detected -- PMOD modules carry no identification pins -- so it has to be
// declared.  These two parameters are the seam a transport register will drive
// once the debug bus is in this core, at which point /tang.ini selects them at
// run time instead of at build time.
//
// Present wiring:
//   PMOD0  oledrgb, normal seating   -> 96x64 at 1x
//   PMOD1  none                      -> all eight pins released
//   HDMI   always                    -> 1056x704 at 11x, centred in 1280x720

module pmod_mirror_core #(
    // Set to 0 to build the core without the HDMI backend.  The transmitter is
    // third-party code that this project's simulator cannot elaborate, so the
    // integration test turns it off and checks the OLED and socket paths; the
    // HDMI composition has its own test that needs no transmitter.
    parameter bit   HDMI_BACKEND      = 1'b1,
    // Set to 0 to build without the BL616 transport.  It instantiates a vendor
    // block-RAM primitive that this project's simulator cannot elaborate, so
    // the integration test turns it off and the socket layer keeps its
    // power-on personalities.
    parameter bit   TRANSPORT         = 1'b1,
    // The player owns its own transport and its own audio: the register bank
    // stays inside for the bring-up core, and the state comes out here so a
    // host that already has a map can place it.  Audio follows the same split.
    parameter bit   EXTERNAL_AUDIO    = 1'b0,
    parameter bit   EXPOSE_STATE      = 1'b0,
    parameter bit   I2S2_BACKEND       = 1'b0,
    parameter bit   I2S2_PLAYBACK      = 1'b0
) (
    input  logic       clk_pixel,
    input  logic       clk_pixel_x5,
    input  logic       clk_i2s2_mclk,
    input  logic       i2s2_clock_locked,
    input  logic [7:0] i2s2_play_lane_o,
    input  logic [7:0] i2s2_play_lane_oe,
    input  logic       resetn,
    input  logic       uart_rx,
    output logic       uart_tx,
    // Stand-in for the transmitter's frame boundary when HDMI_BACKEND is off.
    // Without it the swap would wait forever on a tick that never comes, which
    // is exactly the path the integration test needs to exercise.
    input  logic       frame_tick_in,

    // Player-supplied audio, used when EXTERNAL_AUDIO is set.
    input  logic       clk_audio_in,
    input  logic       audio_rate_48k_in,
    input  logic [15:0] audio_sample_word_in [1:0],

    input logic [3:0] i_scope_control,
    input logic i_scope_flush, i_sample_present,
    output logic [31:0] o_scope_dropped, o_scope_status, o_scope_sweeps,

    // Socket declaration and renderer hold, used when EXPOSE_STATE is set.  A
    // host that keeps its own register map owns the bank, so the bank in here
    // never sees a write and these ports carry the configuration instead.  It
    // is the same split EXTERNAL_AUDIO makes for the audio.  Without them a
    // folded host could write a socket declaration and a hold bit that reached
    // nothing, which is what it did: both sockets then ran on this core's
    // power-on defaults and the hold was inert.
    input  logic [3:0]  i_pmod0_personality,
    input  logic [3:0]  i_pmod1_personality,
    input  logic        i_pmod0_flipped,
    input  logic        i_pmod1_flipped,
    input  logic        i_render_hold,

    // TinyTang desktop layer, composited over the HDMI picture.  Driven by a
    // host that carries iosys (the player); the bring-up core ties it off.
    input  logic        i_desk_we,
    input  logic [6:0]  i_desk_x,
    input  logic [5:0]  i_desk_y,
    input  logic [6:0]  i_desk_ch,
    input  logic [14:0] i_desk_fg,
    input  logic [14:0] i_desk_bg,
    input  logic        i_desk_overlay,
    input  logic        i_desk_on,
    // Mirror state, for a host that keeps its own register map.
    output logic [31:0] o_src_signature,
    output logic [31:0] o_hdmi_signature,
    output logic [31:0] o_panel_signature,
    output logic [31:0] o_render_frames,
    output logic [31:0] o_oled_frames,
    output logic [31:0] o_hdmi_frames,
    output logic [2:0]  o_pattern,
    output logic        o_frame_tick,
    output logic        o_source_bank,
    // Encoder state, so a host with its own map can place it.  Raw by design:
    // a consumer polls these and does its own arithmetic.
    output logic [31:0] o_enc_count,
    output logic [3:0]  o_enc_raw,
    output logic        o_enc_button,
    output logic        o_enc_switch,
    inout  wire [7:0]  pmod0_io,
    inout  wire [7:0]  pmod1_io,
    output logic       tmds_clock,
    output logic [2:0] tmds
);
    // Declared configuration.  The bring-up core owns its register bank, so
    // these come from the registers inside it; a host that owns the bank sets
    // them over the ports above instead.  EXPOSE_STATE picks which, and the
    // register bank's copies are kept separate so the mux is explicit rather
    // than a second driver on a port.
    logic [3:0] pmod0_personality_r;
    logic [3:0] pmod1_personality_r;
    logic       pmod0_flipped_r;
    logic       pmod1_flipped_r;
    logic       hold_r;
    logic [3:0] pmod0_personality;
    logic [3:0] pmod1_personality;
    logic       pmod0_flipped;
    logic       pmod1_flipped;
    logic       hold;
    // The renderer's frame selector, reported to the host at 18:16 of the
    // control register.  The demo reported which of eight test patterns it was
    // drawing; a menu frame writer draws one published frame at a time, so
    // slice 1 fixes this at zero.  The field keeps its position and width so the
    // host map does not move -- the menu is held to the existing protocol.
    logic [2:0] frame_sel;

    assign pmod0_personality = EXPOSE_STATE ? i_pmod0_personality : pmod0_personality_r;
    assign pmod1_personality = EXPOSE_STATE ? i_pmod1_personality : pmod1_personality_r;
    assign pmod0_flipped     = EXPOSE_STATE ? i_pmod0_flipped     : pmod0_flipped_r;
    assign pmod1_flipped     = EXPOSE_STATE ? i_pmod1_flipped     : pmod1_flipped_r;
    assign hold              = EXPOSE_STATE ? i_render_hold       : hold_r;

    // An undeclared socket is not an output.  The panel engine below is held in
    // reset until this socket is declared as OLEDRGB, because that module's
    // power-up and its 44-byte initialisation list are a one-shot conversation
    // that has to land on a connected device.  At configuration every socket is
    // released -- the safe state, and the one an absent /tang.ini produces -- so
    // an init issued then goes out on a high-impedance pin and is lost, and a
    // later declaration can only feed pixels to a panel that was never
    // initialised or switched on, which stays dark however long you wait.
    // Gating the engine on the declaration is what makes the released power-on
    // state safe rather than merely quiet.
    wire oled_declared = (pmod0_personality == PERS_OLEDRGB) ||
                         (pmod1_personality == PERS_OLEDRGB);

    localparam [3:0] PERS_NONE    = 4'd0;
    localparam [3:0] PERS_OLEDRGB = 4'd1;
    localparam [3:0] PERS_VGA_J1  = 4'd2;
    localparam [3:0] PERS_VGA_J2  = 4'd3;
    localparam [3:0] PERS_ENC     = 4'd4;   // rotary encoder, either socket
    localparam [3:0] PERS_I2S2    = 4'd5;   // output-only stereo test tone

    localparam integer W = 96;
    localparam integer H = 64;
    localparam integer CLK_MHZ = 74;        // clk_pixel is 74.25 MHz

    // The raster the HDMI transmitter produces, which the PmodVGA observes.
    logic [11:0] raster_x;
    logic [11:0] raster_y;
    logic [23:0] raster_rgb;
    logic [15:0] hdmi_emitted_px;
    logic        hdmi_emitted_strobe;
    logic        hdmi_emitted_frame_end;
    logic        render_done_d;
    logic [31:0] source_signature;
    logic [31:0] hdmi_signature;
    logic [31:0] panel_signature;
    logic        oled_px_strobe;

    wire rst = ~resetn;

    // ------------------------------------------------------------------
    // Audio: the project's deterministic test source, so the HDMI packet path
    // stays exercised in this core too.
    // ------------------------------------------------------------------
    wire        clk_audio;
    wire        sample_tick;
    wire [31:0] active_sample_rate;
    wire [15:0] tone_sample_word [1:0];

    logic [15:0] hdmi_audio [1:0];
    logic        hdmi_audio_rate_48k;

    generate
    if (EXTERNAL_AUDIO) begin : g_external_audio
        assign clk_audio           = clk_audio_in;
        assign hdmi_audio          = audio_sample_word_in;
        assign hdmi_audio_rate_48k = audio_rate_48k_in;
    end else begin : g_test_audio
        audio_test_source #(.PIXEL_CLOCK_HZ(74_250_000)) audio_timebase (
            .clk_pixel         (clk_pixel),
            .resetn            (resetn),
            .rate_48k          (1'b1),
            .clk_audio         (clk_audio),
            .sample_tick       (sample_tick),
            .active_sample_rate(active_sample_rate),
            .audio_sample_word (tone_sample_word)
        );
        assign hdmi_audio          = tone_sample_word;
        assign hdmi_audio_rate_48k = 1'b1;
    end
    endgenerate

    // ------------------------------------------------------------------
    // Bank swap, fed by both backends' frame ticks.
    // ------------------------------------------------------------------
    logic       bank;
    logic       render_enable;
    logic       render_done;
    logic       oled_frame_start;
    logic       hdmi_frame_tick;

    // Two outputs always: with the transmitter present it supplies the second
    // tick, and without it the test does.  A one-output swap would not
    // exercise the logic that actually runs in hardware.
    localparam integer SWAP_OUTPUTS = 2;

    logic [1:0] swap_ticks;
    // Wait only for the outputs that exist: an undeclared socket is not one, so
    // it must not be able to hold the swap open.  Without this an unconfigured
    // card would freeze the renderer, and the HDMI -- which needs no socket
    // declaration at all -- would show nothing because a PMOD was absent.
    assign swap_ticks = {HDMI_BACKEND ? hdmi_frame_tick : frame_tick_in,
                         oled_frame_start | ~oled_declared};

    ui_swap #(.OUTPUTS(SWAP_OUTPUTS)) swap (
        .clk           (clk_pixel),
        .rst           (rst),
        .render_done   (render_done),
        .frame_tick    (swap_ticks[SWAP_OUTPUTS-1:0]),
        .bank          (bank),
        .render_enable (render_enable)
    );

    // ------------------------------------------------------------------
    // Renderer and the shared pixel stores.
    //
    // One frame writer fills the back bank and raises render_done; the swap
    // decides when that bank becomes the displayed one.  That was the demo's
    // job while the architecture was being proven and is the menu renderer's
    // now, so the demo's test patterns are no longer part of the design.
    // ------------------------------------------------------------------
    logic        we;
    logic        wr_bank;
    logic [6:0]  wr_x;
    logic [5:0]  wr_y;
    logic [15:0] wr_px;

    ui_menu_renderer #(.W(W), .H(H)) renderer (
        .clk           (clk_pixel),
        .rst           (rst),
        .bank          (bank),
        .render_enable (render_enable),
        .hold          (hold),
        .we            (we),
        .wr_bank       (wr_bank),
        .wr_x          (wr_x),
        .wr_y          (wr_y),
        .wr_px         (wr_px),
        .render_done   (render_done)
    );

    // Slice 1 draws exactly one frame, so the selector the host reads at 18:16
    // is zero.  It is tied here rather than driven by the renderer because a
    // menu has no pattern index to report; the field is kept at its position so
    // the host map does not move.
    assign frame_sel = 3'd0;

    // ------------------------------------------------------------------
    // OLED backend: 1:1, so its raster is the image and nothing is a bar.
    // ------------------------------------------------------------------
    logic [6:0]  panel_x;
    logic [5:0]  panel_y;
    logic [15:0] panel_px;
    logic        oled_in_image;
    logic [6:0]  oled_src_x;
    logic [5:0]  oled_src_y;
    logic        oled_bank;

    // The panel's own read bank, latched where its frame begins so that a swap
    // cannot change it mid-frame.
    always_ff @(posedge clk_pixel) begin
        if (rst)
            oled_bank <= 1'b0;
        else if (oled_frame_start)
            oled_bank <= bank;
    end

    ui_scanout #(.K(1), .W(W), .H(H), .X0(0), .Y0(0)) scan_oled (
        .clk      (clk_pixel),
        .rst      (rst),
        .out_x    ({5'd0, panel_x}),
        .out_y    ({6'd0, panel_y}),
        .in_image (oled_in_image),
        .src_x    (oled_src_x),
        .src_y    (oled_src_y)
    );

    ui_frame_bank #(.W(W), .H(H), .OUTPUTS(2)) stores (
        .clk     (clk_pixel),
        .we      (we),
        .wr_bank (wr_bank),
        .wr_x    (wr_x),
        .wr_y    (wr_y),
        .wr_px   (wr_px),
        .rd_bank ({hdmi_read_bank, oled_bank}),
        .rd_x    ({hdmi_src_x, oled_src_x}),
        .rd_y    ({hdmi_src_y, oled_src_y}),
        .rd_px   (bank_rd_px)
    );

    // Port order follows the bank's: index 0 the panel, index 1 the transmitter.
    assign panel_px = bank_rd_px[0];
    assign hdmi_px  = bank_rd_px[1];

    // ------------------------------------------------------------------
    // HDMI backend: 11x, 1056x704 centred in 1280x720.
    // ------------------------------------------------------------------
    logic [6:0]  hdmi_src_x;
    logic [5:0]  hdmi_src_y;
    logic [15:0] hdmi_px;
    logic        hdmi_read_bank;
    logic [1:0][15:0] bank_rd_px;

    // The backend latches its own read bank at its frame boundary.
    generate
    if (HDMI_BACKEND) begin : g_hdmi
        ui_hdmi_backend #(.SCOPE_BACKEND(I2S2_PLAYBACK)) hdmi_backend (
            .scope_control(i_scope_control), .scope_flush(i_scope_flush),
            .sample_present(i_sample_present), .scope_dropped(o_scope_dropped),
            .scope_status(o_scope_status), .scope_sweeps(o_scope_sweeps),
            .clk_pixel      (clk_pixel),
            .clk_pixel_x5   (clk_pixel_x5),
            .resetn         (resetn),
            .clk_audio      (clk_audio),
            .audio_rate_48k (hdmi_audio_rate_48k),
            .audio_sample_word (hdmi_audio),
            .bank           (bank),
            .read_bank      (hdmi_read_bank),
            .rd_x           (hdmi_src_x),
            .rd_y           (hdmi_src_y),
            .rd_px          (hdmi_px),
            .emitted_px        (hdmi_emitted_px),
            .emitted_strobe    (hdmi_emitted_strobe),
            .emitted_frame_end (hdmi_emitted_frame_end),
            .desk_we        (i_desk_we),
            .desk_x         (i_desk_x),
            .desk_y         (i_desk_y),
            .desk_ch        (i_desk_ch),
            .desk_fg        (i_desk_fg),
            .desk_bg        (i_desk_bg),
            .desk_overlay   (i_desk_overlay),
            .desk_on        (i_desk_on),
            .raster_x       (raster_x),
            .raster_y       (raster_y),
            .raster_rgb     (raster_rgb),
            .frame_tick     (hdmi_frame_tick),
            .tmds_clock     (tmds_clock),
            .tmds           (tmds)
        );
    end else begin : g_no_hdmi
        assign o_scope_dropped=0; assign o_scope_status=0; assign o_scope_sweeps=0;
        assign hdmi_src_x      = 7'd0;
        assign hdmi_px         = 16'h0000;
        assign hdmi_frame_tick = 1'b0;
        assign raster_x        = 12'd0;
        assign raster_y        = 12'd0;
        assign raster_rgb      = 24'h000000;
        assign hdmi_emitted_px     = 16'h0000;
        assign hdmi_emitted_strobe    = 1'b0;
        assign hdmi_emitted_frame_end = 1'b0;
        assign tmds_clock      = 1'b0;
        assign tmds            = 3'b000;
    end
    endgenerate


    // ------------------------------------------------------------------
    // Debug transport.
    //
    // The same BL616 protocol the player uses, so the project's existing host
    // tools can already reach this core.  The core id is the player's, because
    // the firmware gates the extended debug protocol on id 0x50 and 0x51 is
    // Tang-PSX's; a dedicated id belongs with the /tang.ini parser, which is a
    // firmware rebuild and reflash rather than a host change.
    //
    // The OSD, controller, ROM-loading and stream interfaces are all tied off:
    // this core has no OSD and plays nothing.  Only the debug bus matters here.
    // ------------------------------------------------------------------
    logic        debug_valid, debug_write;
    logic [31:0] debug_address, debug_wdata, debug_rdata;
    logic [31:0] debug_crc_errors, debug_bad_requests;
    logic        overlay;
    logic [7:0]  overlay_x, overlay_y;
    logic [14:0] overlay_color;
    logic [15:0] hid1, hid2;
    logic [7:0]  rom_loading, rom_do, rom_do_valid;
    logic [15:0] mgmt_address, mgmt_writedata;
    logic        mgmt_read, mgmt_write;
    logic [7:0]  kbd_data;
    logic        kbd_data_valid;
    logic [31:0] core_config;
    logic        stream_start, stream_end, stream_cancel;
    logic [15:0] stream_id;
    logic [31:0] stream_offset;
    logic [7:0]  stream_data;
    logic        stream_valid;

    generate
    if (TRANSPORT) begin : g_transport
    iosys_bl616 #(
        .CORE_ID    (16'h0050),
        .FREQ       (74_250_000),
        .COLOR_LOGO (15'b11111_01000_11111)
    ) transport (
        .clk                (clk_pixel),
        .hclk               (clk_pixel),
        .resetn             (resetn),
        .overlay            (overlay),
        .overlay_x          (overlay_x),
        .overlay_y          (overlay_y),
        .overlay_color      (overlay_color),
        .joy1               (12'd0),
        .joy2               (12'd0),
        .link_mods(8'd0),
        .link_keys(48'd0),
        .hid1               (hid1),
        .hid2               (hid2),
        .rom_loading        (rom_loading),
        .rom_do             (rom_do),
        .rom_do_valid       (rom_do_valid),
        .mgmt_address       (mgmt_address),
        .mgmt_read          (mgmt_read),
        .mgmt_readdata      (16'd0),
        .mgmt_write         (mgmt_write),
        .mgmt_writedata     (mgmt_writedata),
        .fdd_request        (2'd0),
        .kbd_data           (kbd_data),
        .kbd_data_valid     (kbd_data_valid),
        .core_config        (core_config),
        .debug_valid        (debug_valid),
        .debug_write        (debug_write),
        .debug_address      (debug_address),
        .debug_wdata        (debug_wdata),
        .debug_rdata        (debug_rdata),
        .debug_crc_errors   (debug_crc_errors),
        .debug_bad_requests (debug_bad_requests),
        .stream_start       (stream_start),
        .stream_end         (stream_end),
        .stream_cancel      (stream_cancel),
        .stream_id          (stream_id),
        .stream_offset      (stream_offset),
        .stream_data        (stream_data),
        .stream_valid       (stream_valid),
        .stream_ready       (1'b0),
        .uart_rx            (uart_rx),
        .uart_tx            (uart_tx)
    );

    // The OSD raster position is an input to the transport; this core shows no
    // OSD, so the transmitter's raster is passed through and ignored.
    assign overlay_x = raster_x[7:0];
    assign overlay_y = raster_y[7:0];

    end else begin : g_no_transport
        assign debug_valid = 1'b0;
        assign debug_write = 1'b0;
        assign debug_address = 32'd0;
        assign debug_wdata = 32'd0;
        assign uart_tx = 1'b1;
    end
    endgenerate

    // ------------------------------------------------------------------
    // Counters the checker reads.
    // ------------------------------------------------------------------
    logic [31:0] uptime_cycles;
    logic [31:0] render_frames;
    logic [31:0] oled_frames;
    logic [31:0] hdmi_frames;
    logic [31:0] vga_frames;

    always_ff @(posedge clk_pixel) begin
        if (rst) begin
            uptime_cycles <= 32'd0;
            render_frames <= 32'd0;
            oled_frames   <= 32'd0;
            hdmi_frames   <= 32'd0;
        end else begin
            uptime_cycles <= uptime_cycles + 32'd1;
            if (render_done)      render_frames <= render_frames + 32'd1;
            if (oled_frame_start) oled_frames   <= oled_frames + 32'd1;
            if (hdmi_frame_tick)  hdmi_frames   <= hdmi_frames + 32'd1;
        end
    end

    // The VGA observes the transmitter's raster, so its frame count is the
    // transmitter's.  It becomes its own number when it has its own timing.
    assign vga_frames = hdmi_frames;

    // ------------------------------------------------------------------
    // Checksums.
    //
    // Two independent streams can be checked: the frame as it was written into
    // the store, and what the transmitter put on the wire.  The PmodVGA is not
    // a third: it observes the transmitter's raster and cannot disagree with
    // it, so a separate checksum there would be a tautology dressed as
    // evidence.  The panel's own stream is the third genuinely independent
    // one and needs a per-pixel strobe out of the panel engine, which is not
    // wired yet.
    // ------------------------------------------------------------------
    // The source boundary is delayed one cycle because the writer's last write
    // and its render_done coincide, and the checksum wants a pixel-free cycle.
    always_ff @(posedge clk_pixel) begin
        if (rst) render_done_d <= 1'b0;
        else     render_done_d <= render_done;
    end

    ui_checksum source_checksum (
        .clk       (clk_pixel),
        .rst       (rst),
        .strobe    (we),
        .px        (wr_px),
        .frame     (render_done_d),
        .signature (source_signature)
    );

    // The panel is the only genuinely independent third stream: the PmodVGA
    // observes the transmitter's raster and cannot disagree with it, whereas
    // the panel has its own mapper, its own rate and its own physical path.
    // Its expected fold equals the source's, because 1:1 scaling with no bars
    // emits exactly the store contents in the same order.
    ui_checksum panel_checksum (
        .clk       (clk_pixel),
        .rst       (rst),
        .strobe    (oled_px_strobe),
        .px        (panel_px),
        .frame     (oled_frame_start),
        .signature (panel_signature)
    );

    ui_checksum hdmi_checksum (
        .clk       (clk_pixel),
        .rst       (rst),
        .strobe    (hdmi_emitted_strobe),
        .px        (hdmi_emitted_px),
        .frame     (hdmi_emitted_frame_end),
        .signature (hdmi_signature)
    );

    // ------------------------------------------------------------------
    // Rotary encoder.  One instance per socket because the module can sit on
    // either, and it drives nothing on any of them, so only its decoded state
    // needs selecting rather than its lanes.
    // ------------------------------------------------------------------
    logic [31:0] enc0_count, enc1_count;
    logic [3:0]  enc0_raw,   enc1_raw;
    logic        enc0_button, enc0_switch, enc1_button, enc1_switch;

    pmod_enc enc_on_pmod0 (
        .clk (clk_pixel), .rst (rst),
        .lane_i (p0_lane_i), .lane_o (), .lane_oe (),
        .count (enc0_count), .raw (enc0_raw),
        .button (enc0_button), .switch_on (enc0_switch)
    );

    pmod_enc enc_on_pmod1 (
        .clk (clk_pixel), .rst (rst),
        .lane_i (p1_lane_i), .lane_o (), .lane_oe (),
        .count (enc1_count), .raw (enc1_raw),
        .button (enc1_button), .switch_on (enc1_switch)
    );

    logic [31:0] enc_count_sel;
    logic [3:0]  enc_raw_sel;
    logic        enc_button_sel, enc_switch_sel;

    always_comb begin
        if (pmod0_personality == PERS_ENC) begin
            enc_count_sel  = enc0_count;
            enc_raw_sel    = enc0_raw;
            enc_button_sel = enc0_button;
            enc_switch_sel = enc0_switch;
        end else if (pmod1_personality == PERS_ENC) begin
            enc_count_sel  = enc1_count;
            enc_raw_sel    = enc1_raw;
            enc_button_sel = enc1_button;
            enc_switch_sel = enc1_switch;
        end else begin
            enc_count_sel  = 32'h8000_0000;   // centred, as at reset
            enc_raw_sel    = 4'hf;
            enc_button_sel = 1'b0;
            enc_switch_sel = 1'b0;
        end
    end

    ui_debug_regs debug_registers (
        .clk                (clk_pixel),
        .resetn             (resetn),
        .request_valid      (debug_valid),
        .request_write      (debug_write),
        .request_address    (debug_address),
        .request_wdata      (debug_wdata),
        .request_rdata      (debug_rdata),
        .uptime_cycles      (uptime_cycles),
        .render_frames      (render_frames),
        .pattern            (frame_sel),
        .source_bank        (bank),
        .source_crc         (source_signature),
        .oled_frames        (oled_frames),
        .oled_crc           (panel_signature),
        .hdmi_frames        (hdmi_frames),
        .hdmi_crc           (hdmi_signature),
        .vga_frames         (vga_frames),
        .vga_crc            (32'd0),
        .pmod0_personality  (pmod0_personality_r),
        .pmod1_personality  (pmod1_personality_r),
        .pmod0_flipped      (pmod0_flipped_r),
        .pmod1_flipped      (pmod1_flipped_r),
        .hold               (hold_r),
        .enc_count          (enc_count_sel),
        .enc_raw            (enc_raw_sel),
        .enc_button         (enc_button_sel),
        .enc_switch         (enc_switch_sel)
    );

    // ------------------------------------------------------------------
    // Personalities.
    // ------------------------------------------------------------------
    logic [7:0] oled_lane_o;
    logic [7:0] oled_lane_oe;
    logic [7:0] oled_lane_i;

    pmod_oledrgb #(.CLK_MHZ(CLK_MHZ), .SPI_DIV(6)) oled (
        .clk         (clk_pixel),
        // Held off until the socket is declared: see oled_declared above.
        .rst         (rst | ~oled_declared),
        .px_x        (panel_x),
        .px_y        (panel_y),
        .px_data     (panel_px),
        .lane_o      (oled_lane_o),
        .lane_oe     (oled_lane_oe),
        .lane_i      (oled_lane_i),
        .frame_start (oled_frame_start),
        .px_strobe   (oled_px_strobe)
    );

    // ------------------------------------------------------------------
    // Socket layer.  An unselected socket drives nothing: every lane is
    // released, which is the only safe state when a module may be seated that
    // the gateware has not been told about.
    // ------------------------------------------------------------------
    logic [7:0] p0_lane_o;
    logic [7:0] p0_lane_oe;
    logic [7:0] p0_lane_i;
    logic [7:0] p1_lane_o;
    logic [7:0] p1_lane_oe;
    logic [7:0] p1_lane_i;
    logic [7:0] p0_io_o, p0_io_oe, p0_io_i;
    logic [7:0] p1_io_o, p1_io_oe, p1_io_i;

    wire [7:0] i2s2_lane_o, i2s2_lane_oe;
    generate
        if (I2S2_BACKEND && I2S2_PLAYBACK) begin : g_i2s2_playback
            assign i2s2_lane_o = i2s2_play_lane_o;
            assign i2s2_lane_oe = i2s2_play_lane_oe;
        end else if (I2S2_BACKEND) begin : g_i2s2
            wire declared = pmod0_personality == PERS_I2S2 ||
                            pmod1_personality == PERS_I2S2;
            pmod_i2s2_tone tone (
                .clk_mclk(clk_i2s2_mclk),
                .enable(resetn && i2s2_clock_locked && declared),
                .lane_o(i2s2_lane_o), .lane_oe(i2s2_lane_oe)
            );
        end else begin : g_no_i2s2
            assign i2s2_lane_o = 8'h00;
            assign i2s2_lane_oe = 8'h00;
        end
    endgenerate

    logic [7:0] vga_j1_o, vga_j1_oe, vga_j2_o, vga_j2_oe;
    logic [3:0] vga_r, vga_g, vga_b;
    logic       vga_hs, vga_vs;

    ui_vga_backend vga_timing (
        .cx     (raster_x),
        .cy     (raster_y),
        .rgb    (raster_rgb),
        .vga_r  (vga_r),
        .vga_g  (vga_g),
        .vga_b  (vga_b),
        .vga_hs (vga_hs),
        .vga_vs (vga_vs)
    );

    // The module is a dual PMOD: one socket carries J1, the other J2.  Which is
    // which, and whether either is seated upside down, are runtime declarations.
    pmod_vga #(.J1(1'b1)) vga_half_j1 (
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs),
        .lane_o(vga_j1_o), .lane_oe(vga_j1_oe)
    );

    pmod_vga #(.J1(1'b0)) vga_half_j2 (
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hs(vga_hs), .vga_vs(vga_vs),
        .lane_o(vga_j2_o), .lane_oe(vga_j2_oe)
    );

    always_comb begin
        case (pmod0_personality)
            PERS_OLEDRGB: begin p0_lane_o = oled_lane_o; p0_lane_oe = oled_lane_oe; end
            PERS_VGA_J1:  begin p0_lane_o = vga_j1_o;   p0_lane_oe = vga_j1_oe;   end
            PERS_VGA_J2:  begin p0_lane_o = vga_j2_o;   p0_lane_oe = vga_j2_oe;   end
            PERS_I2S2:    begin p0_lane_o = i2s2_lane_o; p0_lane_oe = i2s2_lane_oe; end
            default:      begin p0_lane_o = 8'h00;      p0_lane_oe = 8'h00;       end
        endcase

        case (pmod1_personality)
            PERS_OLEDRGB: begin p1_lane_o = oled_lane_o; p1_lane_oe = oled_lane_oe; end
            PERS_VGA_J1:  begin p1_lane_o = vga_j1_o;   p1_lane_oe = vga_j1_oe;   end
            PERS_VGA_J2:  begin p1_lane_o = vga_j2_o;   p1_lane_oe = vga_j2_oe;   end
            PERS_I2S2:    begin p1_lane_o = i2s2_lane_o; p1_lane_oe = i2s2_lane_oe; end
            default:      begin p1_lane_o = 8'h00;      p1_lane_oe = 8'h00;       end
        endcase
    end

    pmod_slot p0_slot (
        .flipped (pmod0_flipped),
        .lane_o  (p0_lane_o),
        .lane_oe (p0_lane_oe),
        .lane_i  (p0_lane_i),
        .io_o    (p0_io_o),
        .io_oe   (p0_io_oe),
        .io_i    (p0_io_i)
    );

    pmod_io_buf p0_buf (
        .o  (p0_io_o),
        .oe (p0_io_oe),
        .i  (p0_io_i),
        .io (pmod0_io)
    );

    // No PMOD1 personality exists yet, so the socket stays released.  The
    // parameter is kept so a future personality slots in here unchanged.
    pmod_slot p1_slot (
        .flipped (pmod1_flipped),
        .lane_o  (p1_lane_o),
        .lane_oe (p1_lane_oe),
        .lane_i  (p1_lane_i),
        .io_o    (p1_io_o),
        .io_oe   (p1_io_oe),
        .io_i    (p1_io_i)
    );

    pmod_io_buf p1_buf (
        .o  (p1_io_o),
        .oe (p1_io_oe),
        .i  (p1_io_i),
        .io (pmod1_io)
    );

    assign o_src_signature   = source_signature;
    assign o_hdmi_signature  = hdmi_signature;
    assign o_panel_signature = panel_signature;
    assign o_render_frames   = render_frames;
    assign o_oled_frames     = oled_frames;
    assign o_hdmi_frames     = hdmi_frames;
    assign o_pattern         = frame_sel;
    assign o_frame_tick      = oled_frame_start;
    assign o_source_bank     = bank;
    assign o_enc_count       = enc_count_sel;
    assign o_enc_raw         = enc_raw_sel;
    assign o_enc_button      = enc_button_sel;
    assign o_enc_switch      = enc_switch_sel;

    logic unused_ok;
    always_comb unused_ok = oled_in_image ^ (^oled_lane_i) ^ (^p0_lane_i)
                          ^ (^p1_lane_i) ^ (^active_sample_rate) ^ sample_tick;
endmodule
