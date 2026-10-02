// SPDX-License-Identifier: GPL-3.0-only
//
// PMOD socket bring-up core: the mirrored video demo.
//
// The point of this core is the shape, not the picture.  One frame store holds
// the only pixels in the design; a demo renderer fills it; each presentation
// backend reads it through its own scan mapper and differs only in its integer
// scale factor and its constraints.  Adding HDMI or VGA therefore adds a
// backend and a constraint file, never a second copy of the image.
//
// Socket configuration is a parameter for now.  Physical seating cannot be
// detected -- PMOD modules carry no identification pins -- so it has to be
// declared.  These two parameters are the seam a transport register will drive
// once the debug bus is in this core, at which point /tang.ini selects them at
// run time instead of at build time.
//
// Stage 0 wiring:
//   PMOD0  oledrgb, normal seating   -> the panel already verified by eye
//   PMOD1  none                      -> all eight pins high-Z
//
// HDMI is the next backend; its raster, its CPLD-free timing and its bars are
// deliberately absent here so that this build proves the store, the mapper and
// the socket layer on hardware that is already trusted.

module pmod_mirror_top #(
    parameter [3:0] PMOD0_PERSONALITY = 4'd1,       // 0 = none, 1 = oledrgb
    parameter       PMOD0_FLIPPED     = 1'b0,
    parameter [3:0] PMOD1_PERSONALITY = 4'd0,
    parameter       PMOD1_FLIPPED     = 1'b0
) (
    input  logic      sys_clk,      // 50 MHz board clock
    inout  wire [7:0] pmod0_io,
    inout  wire [7:0] pmod1_io
);
    localparam [3:0] PERS_NONE    = 4'd0;
    localparam [3:0] PERS_OLEDRGB = 4'd1;

    localparam integer W = 96;
    localparam integer H = 64;

    // ------------------------------------------------------------------
    // Power-on reset.
    // ------------------------------------------------------------------
    logic [15:0] por_cnt = 16'd0;
    logic        rst     = 1'b1;

    always_ff @(posedge sys_clk) begin
        if (por_cnt != 16'hFFFF)
            por_cnt <= por_cnt + 16'd1;
        else
            rst <= 1'b0;
    end

    // ------------------------------------------------------------------
    // Bank swap and renderer.
    // ------------------------------------------------------------------
    logic bank;
    logic render_enable;
    logic render_done;
    logic oled_frame_start;

    ui_swap #(.OUTPUTS(1)) swap (
        .clk           (sys_clk),
        .rst           (rst),
        .render_done   (render_done),
        .frame_tick    (oled_frame_start),
        .bank          (bank),
        .render_enable (render_enable)
    );

    logic        we;
    logic        wr_bank;
    logic [6:0]  wr_x;
    logic [5:0]  wr_y;
    logic [15:0] wr_px;

    ui_pattern_demo #(.W(W), .H(H), .CLK_MHZ(50), .HOLD_MS(1000)) demo (
        .clk           (sys_clk),
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
    // The single pixel store, and the OLED backend's scan mapper.
    // ------------------------------------------------------------------
    logic [6:0]  panel_x;
    logic [5:0]  panel_y;
    logic [15:0] panel_px;
    logic        in_image;
    logic [6:0]  src_x;
    logic [5:0]  src_y;

    // K = 1 here, so this mapper is an identity: the panel's own raster is the
    // image and in_image is always true.  It still goes through the mapper so
    // that the seam an HDMI or VGA backend needs is the one under test.
    ui_scanout #(
        .K(1), .W(W), .H(H), .X0(0), .Y0(0)
    ) scan (
        .clk      (sys_clk),
        .rst      (rst),
        .out_x    ({5'd0, panel_x}),
        .out_y    ({6'd0, panel_y}),
        .in_image (in_image),
        .src_x    (src_x),
        .src_y    (src_y)
    );

    ui_frame_store #(.W(W), .H(H)) store (
        .clk     (sys_clk),
        .we      (we),
        .wr_bank (wr_bank),
        .wr_x    (wr_x),
        .wr_y    (wr_y),
        .wr_px   (wr_px),
        .rd_bank (bank),
        .rd_x    (src_x),
        .rd_y    (src_y),
        .rd_px   (panel_px)
    );

    // ------------------------------------------------------------------
    // Personalities.
    // ------------------------------------------------------------------
    logic [7:0] oled_lane_o;
    logic [7:0] oled_lane_oe;
    logic [7:0] oled_lane_i;

    pmod_oledrgb #(.CLK_MHZ(50)) oled (
        .clk         (sys_clk),
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
    // high-Z, which is the only safe state when a module may be seated that
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

    // No PMOD1 personality exists yet, so the socket stays high-Z.  The
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

    // The OLED personality has no inputs, so the socket read buses and the
    // scan mapper's in_image go nowhere until a personality exists that reads
    // pins or that needs bars.  Fold them into one dummy so the intent is
    // explicit rather than leaving the tool to trim them silently.
    logic unused_ok;
    always_comb unused_ok = in_image ^ (^oled_lane_i) ^ (^p0_lane_i) ^ (^p1_lane_i);
endmodule
