// SPDX-License-Identifier: GPL-3.0-only
//
// PMOD personality: Digilent PmodVGA.
//
// The module is a dual PMOD, so this personality drives one socket and the
// module's other half is driven by the matching personality on the other
// socket.  Which socket holds which half is the user's declaration, not a
// build-time decision:
//
//   J1  pins 1-4 red R0-R3, pins 7-10 blue B0-B3
//   J2  pins 1-4 green G0-G3, pin 7 horizontal sync, pin 8 vertical sync,
//       pins 9 and 10 not connected
//
// That gives the same two placement choices Tang-PSX exposes as its mode bits:
// swapping which socket carries J1 is choosing the other personality here, and
// swapping each socket's rows, as when the module is seated upside down, is the
// socket layer's `flipped` bit.  Both are runtime selections.
//
// Every module pin is a buffered input to the module -- two SN74ALVC245 buffers
// drive the resistor ladders -- so a wrong placement or a wrong orientation
// cannot damage anything, it only loses the picture.  That is what makes this
// module safe to declare either way round.

module pmod_vga #(
    // 1 when this socket carries J1, 0 when it carries J2.
    parameter bit J1 = 1'b1
) (
    input  logic [3:0] vga_r,
    input  logic [3:0] vga_g,
    input  logic [3:0] vga_b,
    input  logic       vga_hs,
    input  logic       vga_vs,
    output logic [7:0] lane_o,
    output logic [7:0] lane_oe
);
    always_comb begin
        if (J1) begin
            // Lanes 0-3 are pins 1-4 (red), lanes 4-7 are pins 7-10 (blue).
            lane_o  = {vga_b, vga_r};
            lane_oe = 8'hff;
        end else begin
            // Lanes 0-3 are pins 1-4 (green), lane 4 is pin 7 (HS), lane 5 is
            // pin 8 (VS), lanes 6 and 7 are pins 9 and 10, not connected.
            lane_o  = {2'b00, vga_vs, vga_hs, vga_g};
            lane_oe = 8'b0011_1111;
        end
    end
endmodule
