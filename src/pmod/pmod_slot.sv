// SPDX-License-Identifier: GPL-3.0-only
//
// One PMOD socket, as seen by a personality.
//
// A personality works in Digilent pin order, lanes 0-7 being module pins
// 1, 2, 3, 4, 7, 8, 9 and 10.  This module converts that to the dock's IO
// numbering and applies the seating orientation, so no personality has to know
// about either.
//
// Two facts, both verified on this dock and recorded in core-reference.md:
//
//   * Sipeed interleaves the socket rows.  IO0/2/4/6 are module pins 1-4 and
//     IO1/3/5/7 are pins 7-10, which is what console138k_oled.cst already
//     encodes and what the OLED panel ran on.
//   * Turning a module over swaps pins 1-4 with pins 7-10 while leaving GND on
//     pins 5/11 and VCC on 6/12.  In lane terms that is a swap of the vector's
//     two halves, so orientation is one rotate with no remap table and no
//     second constraint file.
//
// The tri-state itself lives in pmod_io_buf so that this permutation stays
// plain combinational logic and can be tested directly, without a testbench
// having to drive an inout wire.
//
// `flipped` is a runtime bit rather than a parameter because physical seating
// is not detectable: PMOD modules carry no identification pins, so the gateware
// can only be told what is attached, never discover it.

module pmod_slot (
    input  logic       flipped,
    input  logic [7:0] lane_o,
    input  logic [7:0] lane_oe,
    output logic [7:0] lane_i,
    output logic [7:0] io_o,
    output logic [7:0] io_oe,
    input  logic [7:0] io_i
);
    // Driven value and enable for each lane position after orientation.
    logic [7:0] eff_o;
    logic [7:0] eff_oe;
    // Input value at each lane position before orientation.
    logic [7:0] eff_i;

    always_comb begin
        if (flipped) begin
            eff_o  = {lane_o[3:0],  lane_o[7:4]};
            eff_oe = {lane_oe[3:0], lane_oe[7:4]};
        end else begin
            eff_o  = lane_o;
            eff_oe = lane_oe;
        end
    end

    assign lane_i = flipped ? {eff_i[3:0], eff_i[7:4]} : eff_i;

    // Fixed interleave: lane k goes to IO 2k for lanes 0-3 and IO 2(k-4)+1 for
    // lanes 4-7.
    assign io_o[0]  = eff_o[0];
    assign io_o[2]  = eff_o[1];
    assign io_o[4]  = eff_o[2];
    assign io_o[6]  = eff_o[3];
    assign io_o[1]  = eff_o[4];
    assign io_o[3]  = eff_o[5];
    assign io_o[5]  = eff_o[6];
    assign io_o[7]  = eff_o[7];

    assign io_oe[0] = eff_oe[0];
    assign io_oe[2] = eff_oe[1];
    assign io_oe[4] = eff_oe[2];
    assign io_oe[6] = eff_oe[3];
    assign io_oe[1] = eff_oe[4];
    assign io_oe[3] = eff_oe[5];
    assign io_oe[5] = eff_oe[6];
    assign io_oe[7] = eff_oe[7];

    assign eff_i[0] = io_i[0];
    assign eff_i[1] = io_i[2];
    assign eff_i[2] = io_i[4];
    assign eff_i[3] = io_i[6];
    assign eff_i[4] = io_i[1];
    assign eff_i[5] = io_i[3];
    assign eff_i[6] = io_i[5];
    assign eff_i[7] = io_i[7];
endmodule
