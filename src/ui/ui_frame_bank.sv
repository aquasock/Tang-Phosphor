// SPDX-License-Identifier: GPL-3.0-only
//
// The frame store, as one thing rather than several that happen to agree.
//
// Until now the top level instantiated one ui_frame_store per output and wired
// the same write signals to each.  That works, and it is why the outputs have
// never diverged, but it is a convention rather than a guarantee: an edit could
// give one copy a different write source and nothing would fail loudly, because
// each copy would stay internally consistent and simply show a different frame.
//
// This module owns the write port and instantiates the copies itself, so one
// source of truth is enforced by the structure instead of by whoever last
// touched the top level.  Callers can only read.
//
// It costs no logic and no timing: the same stores, the same write signals, one
// level of hierarchy deeper.

module ui_frame_bank #(
    parameter integer W       = 96,
    parameter integer H       = 64,
    parameter integer OUTPUTS = 2
) (
    input  logic clk,

    // One write port, fanned internally.  Not reachable per copy by design.
    input  logic        we,
    input  logic        wr_bank,
    input  logic [6:0]  wr_x,
    input  logic [5:0]  wr_y,
    input  logic [15:0] wr_px,

    // One read port per output.
    input  logic [OUTPUTS-1:0]       rd_bank,
    input  logic [OUTPUTS-1:0][6:0]  rd_x,
    input  logic [OUTPUTS-1:0][5:0]  rd_y,
    output logic [OUTPUTS-1:0][15:0] rd_px
);
    genvar i;
    generate
        for (i = 0; i < OUTPUTS; i = i + 1) begin : g_copy
            ui_frame_store #(.W(W), .H(H)) copy (
                .clk     (clk),
                .we      (we),
                .wr_bank (wr_bank),
                .wr_x    (wr_x),
                .wr_y    (wr_y),
                .wr_px   (wr_px),
                .rd_bank (rd_bank[i]),
                .rd_x    (rd_x[i]),
                .rd_y    (rd_y[i]),
                .rd_px   (rd_px[i])
            );
        end
    endgenerate
endmodule
