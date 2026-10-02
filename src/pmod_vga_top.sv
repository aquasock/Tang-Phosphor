// SPDX-License-Identifier: GPL-3.0-only
//
// Configuration B: the PmodVGA occupying both sockets, no panel.
//
// The socket personalities are compile-time parameters until the debug
// transport lands and /tang.ini can select them at run time, so configuration B
// needs its own top.  It exists for a reason beyond testing: with no socket
// selecting the VGA backend the whole backend is dead logic and the
// synthesiser removes it, so an OLED-only build says nothing at all about
// whether a third backend still fits.
//
// This is a sibling of pmod_mirror_top rather than a wrapper around it.  A
// wrapper would put the PLL outputs one level down, and this tool version
// cannot name those nets hierarchically from the SDC, so each variant owns its
// clocks and both keep the same root-level names.  That is cheaper than it
// looks: the clock block is the same twenty lines in both.
//
// The socket assignment matches Tang-PSX's verified default, J1 on PMOD1 and
// J2 on PMOD0.

module pmod_vga_top (
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
        .PMOD0_PERSONALITY (4'd3),      // VGA J2 on PMOD0
        .PMOD0_FLIPPED     (1'b0),
        .PMOD1_PERSONALITY (4'd2),      // VGA J1 on PMOD1
        .PMOD1_FLIPPED     (1'b0)
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
