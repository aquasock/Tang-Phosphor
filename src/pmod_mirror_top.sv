// SPDX-License-Identifier: GPL-3.0-only
//
// PMOD socket bring-up core: the mirrored video demo, top level.
//
// Only clocks and reset live here.  The 50 MHz board clock is the PLL
// reference and nothing else: 50 MHz to 27 MHz to 74.25 MHz and 371.25 MHz,
// after which every backend, the renderer and both frame-store ports run on the
// pixel clock.  The logic itself is in pmod_mirror_core so that it can be
// simulated without the vendor PLL primitives.

module pmod_mirror_top #(
    parameter [3:0] PMOD0_PERSONALITY = 4'd1,       // 0 = none, 1 = oledrgb
    parameter       PMOD0_FLIPPED     = 1'b0,
    parameter [3:0] PMOD1_PERSONALITY = 4'd0,
    parameter       PMOD1_FLIPPED     = 1'b0
) (
    input  logic       sys_clk,     // 50 MHz board clock, PLL reference only
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

    pmod_mirror_core #(
        .PMOD0_PERSONALITY (PMOD0_PERSONALITY),
        .PMOD0_FLIPPED     (PMOD0_FLIPPED),
        .PMOD1_PERSONALITY (PMOD1_PERSONALITY),
        .PMOD1_FLIPPED     (PMOD1_FLIPPED)
    ) core (
        .clk_pixel    (clk_pixel),
        .clk_pixel_x5 (clk_pixel_x5),
        .resetn       (resetn),
        .pmod0_io     (pmod0_io),
        .pmod1_io     (pmod1_io),
        .tmds_clock   (hdmi_tmds_clock),
        .tmds         (hdmi_tmds)
    );

    ELVDS_OBUF tmds_output [3:0] (
        .I  ({clk_pixel, hdmi_tmds}),
        .O  ({tmds_clk_p, tmds_d_p}),
        .OB ({tmds_clk_n, tmds_d_n})
    );
endmodule
