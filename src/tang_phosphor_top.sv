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

phosphor_video video (
    .resetn(resetn),
    .clk_pixel(clk_pixel),
    .clk_pixel_x5(clk_pixel_x5),
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

stream_debug_sink stream_sink (
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
    .request_rdata(debug_rdata)
);

endmodule
