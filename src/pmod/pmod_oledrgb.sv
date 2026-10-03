// SPDX-License-Identifier: GPL-3.0-only
//
// PMOD personality: Digilent Pmod OLEDrgb (SSD1331), one socket.
//
// A personality owns the protocol for one module and presents only Digilent
// lanes to the socket layer, so nothing above it knows which socket the module
// is in or which way round it is seated.
//
// Lane assignments come from the module's reference manual J1 pinout:
//   lane 0 = pin 1  CS#        lane 4 = pin 7  D/C#
//   lane 1 = pin 2  MOSI       lane 5 = pin 8  RES#
//   lane 2 = pin 3  not connected
//   lane 3 = pin 4  SCK        lane 6 = pin 9  VCCEN
//                              lane 7 = pin 10 PMODEN
//
// The not-connected pin is left high-Z rather than driven, since the dock end
// of it is a real FPGA pin and the module simply ignores it.
//
// Every OLEDrgb signal is a host-driven input, so lane_i is unused: a
// mis-seated module cannot drive against these outputs.

module pmod_oledrgb #(
    parameter integer CLK_MHZ = 50,
    parameter integer SPI_DIV = 4
) (
    input  logic        clk,
    input  logic        rst,

    // Pixel source address, presented to the scan mapper.
    output logic [6:0]  px_x,
    output logic [5:0]  px_y,
    input  logic [15:0] px_data,

    // Socket-facing lanes, in Digilent pin order.
    output logic [7:0]  lane_o,
    output logic [7:0]  lane_oe,
    input  logic [7:0]  lane_i,

    // Frame boundary, for the bank swap.
    output logic        frame_start,

    // One pulse per pixel the panel is shown.
    output logic        px_strobe
);
    logic cs_n, mosi, sck, dc, res_n, vccen, pmoden;

    always_comb begin
        lane_o     = 8'h00;
        lane_o[0]  = cs_n;
        lane_o[1]  = mosi;
        lane_o[3]  = sck;
        lane_o[4]  = dc;
        lane_o[5]  = res_n;
        lane_o[6]  = vccen;
        lane_o[7]  = pmoden;

        // Every lane is driven except lane 2, the module's not-connected pin.
        lane_oe    = 8'b1111_1011;
    end

    oled_panel #(.CLK_MHZ(CLK_MHZ), .SPI_DIV(SPI_DIV)) panel (
        .clk         (clk),
        .rst         (rst),
        .px_x        (px_x),
        .px_y        (px_y),
        .px_data     (px_data),
        .cs_n        (cs_n),
        .mosi        (mosi),
        .sck         (sck),
        .dc          (dc),
        .res_n       (res_n),
        .vccen       (vccen),
        .pmoden      (pmoden),
        .frame_start (frame_start),
        .px_strobe   (px_strobe)
    );
endmodule
