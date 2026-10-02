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
    parameter [3:0] PMOD0_PERSONALITY = 4'd1,       // 0 = none, 1 = oledrgb
    parameter       PMOD0_FLIPPED     = 1'b0,
    parameter [3:0] PMOD1_PERSONALITY = 4'd0,
    parameter       PMOD1_FLIPPED     = 1'b0,
    // Set to 0 to build the core without the HDMI backend.  The transmitter is
    // third-party code that this project's simulator cannot elaborate, so the
    // integration test turns it off and checks the OLED and socket paths; the
    // HDMI composition has its own test that needs no transmitter.
    parameter bit   HDMI_BACKEND      = 1'b1
) (
    input  logic       clk_pixel,
    input  logic       clk_pixel_x5,
    input  logic       resetn,
    inout  wire [7:0]  pmod0_io,
    inout  wire [7:0]  pmod1_io,
    output logic       tmds_clock,
    output logic [2:0] tmds
);
    localparam [3:0] PERS_NONE    = 4'd0;
    localparam [3:0] PERS_OLEDRGB = 4'd1;

    localparam integer W = 96;
    localparam integer H = 64;
    localparam integer CLK_MHZ = 74;        // clk_pixel is 74.25 MHz

    wire rst = ~resetn;

    // ------------------------------------------------------------------
    // Audio: the project's deterministic test source, so the HDMI packet path
    // stays exercised in this core too.
    // ------------------------------------------------------------------
    wire        clk_audio;
    wire        sample_tick;
    wire [31:0] active_sample_rate;
    wire [15:0] tone_sample_word [1:0];

    audio_test_source #(.PIXEL_CLOCK_HZ(74_250_000)) audio_timebase (
        .clk_pixel         (clk_pixel),
        .resetn            (resetn),
        .rate_48k          (1'b1),
        .clk_audio         (clk_audio),
        .sample_tick       (sample_tick),
        .active_sample_rate(active_sample_rate),
        .audio_sample_word (tone_sample_word)
    );

    // ------------------------------------------------------------------
    // Bank swap, fed by both backends' frame ticks.
    // ------------------------------------------------------------------
    logic       bank;
    logic       render_enable;
    logic       render_done;
    logic       oled_frame_start;
    logic       hdmi_frame_tick;

    localparam integer SWAP_OUTPUTS = HDMI_BACKEND ? 2 : 1;

    logic [1:0] swap_ticks;
    assign swap_ticks = {hdmi_frame_tick, oled_frame_start};

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
    // ------------------------------------------------------------------
    logic        we;
    logic        wr_bank;
    logic [6:0]  wr_x;
    logic [5:0]  wr_y;
    logic [15:0] wr_px;

    ui_pattern_demo #(.W(W), .H(H), .CLK_MHZ(CLK_MHZ), .HOLD_MS(1000)) demo (
        .clk           (clk_pixel),
        .rst           (rst),
        .bank          (bank),
        .render_enable (render_enable),
        .we            (we),
        .wr_bank       (wr_bank),
        .wr_x          (wr_x),
        .wr_y          (wr_y),
        .wr_px         (wr_px),
        .render_done   (render_done)
    );

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

    ui_frame_store #(.W(W), .H(H)) store_oled (
        .clk     (clk_pixel),
        .we      (we),
        .wr_bank (wr_bank),
        .wr_x    (wr_x),
        .wr_y    (wr_y),
        .wr_px   (wr_px),
        .rd_bank (oled_bank),
        .rd_x    (oled_src_x),
        .rd_y    (oled_src_y),
        .rd_px   (panel_px)
    );

    // ------------------------------------------------------------------
    // HDMI backend: 11x, 1056x704 centred in 1280x720.
    // ------------------------------------------------------------------
    logic [6:0]  hdmi_src_x;
    logic [5:0]  hdmi_src_y;
    logic [15:0] hdmi_px;

    // The backend latches its own read bank at its frame boundary.
    generate
    if (HDMI_BACKEND) begin : g_hdmi
        ui_hdmi_backend hdmi_backend (
            .clk_pixel      (clk_pixel),
            .clk_pixel_x5   (clk_pixel_x5),
            .resetn         (resetn),
            .clk_audio      (clk_audio),
            .audio_rate_48k (1'b1),
            .audio_sample_word (tone_sample_word),
            .bank           (bank),
            .rd_x           (hdmi_src_x),
            .rd_y           (hdmi_src_y),
            .rd_px          (hdmi_px),
            .frame_tick     (hdmi_frame_tick),
            .tmds_clock     (tmds_clock),
            .tmds           (tmds)
        );
    end else begin : g_no_hdmi
        assign hdmi_src_x      = 7'd0;
        assign hdmi_px         = 16'h0000;
        assign hdmi_frame_tick = 1'b0;
        assign tmds_clock      = 1'b0;
        assign tmds            = 3'b000;
    end
    endgenerate

    ui_frame_store #(.W(W), .H(H)) store_hdmi (
        .clk     (clk_pixel),
        .we      (we),
        .wr_bank (wr_bank),
        .wr_x    (wr_x),
        .wr_y    (wr_y),
        .wr_px   (wr_px),
        .rd_bank (bank),
        .rd_x    (hdmi_src_x),
        .rd_y    (hdmi_src_y),
        .rd_px   (hdmi_px)
    );

    // ------------------------------------------------------------------
    // Personalities.
    // ------------------------------------------------------------------
    logic [7:0] oled_lane_o;
    logic [7:0] oled_lane_oe;
    logic [7:0] oled_lane_i;

    pmod_oledrgb #(.CLK_MHZ(CLK_MHZ), .SPI_DIV(6)) oled (
        .clk         (clk_pixel),
        .rst         (rst),
        .px_x        (panel_x),
        .px_y        (panel_y),
        .px_data     (panel_px),
        .lane_o      (oled_lane_o),
        .lane_oe     (oled_lane_oe),
        .lane_i      (oled_lane_i),
        .frame_start (oled_frame_start)
    );

    // ------------------------------------------------------------------
    // Socket layer.  An unselected socket drives nothing: every lane is
    // released, which is the only safe state when a module may be seated that
    // the gateware has not been told about.
    // ------------------------------------------------------------------
    logic [7:0] p0_lane_o;
    logic [7:0] p0_lane_oe;
    logic [7:0] p0_lane_i;
    logic [7:0] p1_lane_i;
    logic [7:0] p0_io_o, p0_io_oe, p0_io_i;
    logic [7:0] p1_io_o, p1_io_oe, p1_io_i;

    always_comb begin
        if (PMOD0_PERSONALITY == PERS_OLEDRGB) begin
            p0_lane_o  = oled_lane_o;
            p0_lane_oe = oled_lane_oe;
        end else begin
            p0_lane_o  = 8'h00;
            p0_lane_oe = 8'h00;
        end
    end

    pmod_slot p0_slot (
        .flipped (PMOD0_FLIPPED),
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
        .flipped (PMOD1_FLIPPED),
        .lane_o  (8'h00),
        .lane_oe (8'h00),
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

    logic unused_ok;
    always_comb unused_ok = oled_in_image ^ (^oled_lane_i) ^ (^p0_lane_i)
                          ^ (^p1_lane_i) ^ (^active_sample_rate) ^ sample_tick;
endmodule
