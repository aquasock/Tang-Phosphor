// Tang-Phosphor bring-up top level for the Tang Console 138K.

module tang_phosphor_top (
    input        sys_clk,

    input        UART_RXD,
    output       UART_TXD,

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
wire [15:0] hid1_unused;
wire [15:0] hid2_unused;

phosphor_video video (
    .resetn(resetn),
    .clk_pixel(clk_pixel),
    .clk_pixel_x5(clk_pixel_x5),
    .overlay(overlay),
    .overlay_x(overlay_x),
    .overlay_y(overlay_y),
    .overlay_color(overlay_color),
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
    .joy1(12'b0),
    .joy2(12'b0),
    .hid1(hid1_unused),
    .hid2(hid2_unused),
    .mgmt_readdata(16'b0),
    .fdd_request(2'b0),
    .uart_rx(UART_RXD),
    .uart_tx(UART_TXD)
);

endmodule
