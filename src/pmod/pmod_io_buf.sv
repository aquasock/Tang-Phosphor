// SPDX-License-Identifier: GPL-3.0-only
//
// Tri-state buffer between a socket's eight pins and the socket layer.
//
// Kept separate from pmod_slot so that the pin permutation is plain
// combinational logic and can be tested without a testbench driving an inout
// wire.  A pin whose enable is low is released, which is the socket's idle
// state and the only safe condition when a module may be seated that the
// gateware has not been told about.

module pmod_io_buf (
    input  logic [7:0] o,
    input  logic [7:0] oe,
    output logic [7:0] i,
    inout  wire  [7:0] io
);
    assign io[0] = oe[0] ? o[0] : 1'bz;
    assign io[1] = oe[1] ? o[1] : 1'bz;
    assign io[2] = oe[2] ? o[2] : 1'bz;
    assign io[3] = oe[3] ? o[3] : 1'bz;
    assign io[4] = oe[4] ? o[4] : 1'bz;
    assign io[5] = oe[5] ? o[5] : 1'bz;
    assign io[6] = oe[6] ? o[6] : 1'bz;
    assign io[7] = oe[7] ? o[7] : 1'bz;

    assign i = io;
endmodule
