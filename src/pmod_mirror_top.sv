// SPDX-License-Identifier: GPL-3.0-only
//
// PMOD socket bring-up core: the mirrored video demo, top level.
//
// Only clocks and reset live here.  The 50 MHz board clock is the PLL
// reference and nothing else: 50 MHz to 27 MHz to 74.25 MHz and 371.25 MHz,
// after which every backend, the renderer and both frame-store ports run on the
// pixel clock.  The logic itself is in pmod_mirror_core so that it can be
// simulated without the vendor PLL primitives.

module pmod_mirror_top (
    input  logic       sys_clk,     // 50 MHz board clock, PLL reference only
    input  logic       uart_rx,
    output logic       uart_tx,
    inout  wire [7:0]  pmod0_io,
    inout  wire [7:0]  pmod1_io,
    output logic       tmds_clk_p,
    output logic       tmds_clk_n,
    output logic [2:0] tmds_d_p,
    output logic [2:0] tmds_d_n
);
    wire clk27;
    wire clk_pixel;
    wire clk_pixel_x5;

    pll_27 clock_27mhz (
        .clkin   (sys_clk),
        .clkout0 (clk27)
    );

    pll_74 clock_hdmi (
        .clkin   (clk27),
        .clkout0 (clk_pixel),
        .clkout1 (clk_pixel_x5)
    );

    logic [15:0] reset_counter = 16'hffff;
    logic        resetn = 1'b0;

    always_ff @(posedge clk_pixel) begin
        if (reset_counter != 16'd0)
            reset_counter <= reset_counter - 16'd1;
        else
            resetn <= 1'b1;
    end

    wire        hdmi_tmds_clock;
    wire [2:0]  hdmi_tmds;

    pmod_mirror_core core (
        .clk_pixel    (clk_pixel),
        .clk_pixel_x5 (clk_pixel_x5),
        .clk_i2s2_mclk (1'b0),
        .i2s2_clock_locked (1'b0),
        .resetn       (resetn),
        .uart_rx      (uart_rx),
        .uart_tx      (uart_tx),
        .frame_tick_in(1'b0),
        .pmod0_io     (pmod0_io),
        .pmod1_io     (pmod1_io),
        .tmds_clock   (hdmi_tmds_clock),
        .tmds         (hdmi_tmds),
        // The bring-up core owns its register bank, so its socket declaration
        // and hold come from the registers inside it and these are unused.
        .i_pmod0_personality (4'd0),
        .i_pmod1_personality (4'd0),
        .i_pmod0_flipped     (1'b0),
        .i_pmod1_flipped     (1'b0),
        .i_render_hold       (1'b0),
        // No iosys here, so no desktop layer.
        .i_desk_we           (1'b0),
        .i_desk_x            (7'd0),
        .i_desk_y            (6'd0),
        .i_desk_ch           (7'd0),
        .i_desk_fg           (15'd0),
        .i_desk_bg           (15'd0),
        .i_desk_overlay      (1'b0),
        .i_desk_on           (1'b0)
    );

    ELVDS_OBUF tmds_output [3:0] (
        .I  ({clk_pixel, hdmi_tmds}),
        .O  ({tmds_clk_p, tmds_d_p}),
        .OB ({tmds_clk_n, tmds_d_n})
    );
endmodule
