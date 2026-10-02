// SPDX-License-Identifier: GPL-3.0-only
//
// The single source of truth for what every screen shows.
//
// One 96x64 RGB565 plane, doubled so the renderer can fill one bank while the
// outputs read the other.  There is deliberately no other pixel storage in the
// design: mirroring is a property of the structure rather than of discipline,
// because every output reads this same store, and the only thing that can
// differ between outputs is their address mapping.
//
// Address order is bank-major, then row, then column.  The row multiply is
// written as shifts because 96 = 64 + 32, keeping a multiplier out of the
// address path.

module ui_frame_store #(
    parameter integer W = 96,
    parameter integer H = 64
) (
    input  logic        clk,

    // Write port: the renderer.
    input  logic        we,
    input  logic        wr_bank,
    input  logic [6:0]  wr_x,
    input  logic [5:0]  wr_y,
    input  logic [15:0] wr_px,

    // Read port: one presentation backend.
    input  logic        rd_bank,
    input  logic [6:0]  rd_x,
    input  logic [5:0]  rd_y,
    output logic [15:0] rd_px
);
    localparam integer PLANE = W * H;               // 6144 pixels per bank
    localparam integer DEPTH = PLANE * 2;

    localparam [13:0] PLANE_OFF = PLANE;            // bank 1 base address

    logic [15:0] mem [0:DEPTH-1];

    // y * W + x with W = 96 as (y << 6) + (y << 5): 13 bits either way.
    wire [12:0] wr_row = ({7'd0, wr_y} << 6) + ({7'd0, wr_y} << 5) + {6'd0, wr_x};
    wire [12:0] rd_row = ({7'd0, rd_y} << 6) + ({7'd0, rd_y} << 5) + {6'd0, rd_x};

    wire [13:0] wr_addr = (wr_bank ? PLANE_OFF : 14'd0) + {1'b0, wr_row};
    wire [13:0] rd_addr = (rd_bank ? PLANE_OFF : 14'd0) + {1'b0, rd_row};

    always_ff @(posedge clk) begin
        if (we)
            mem[wr_addr] <= wr_px;
        rd_px <= mem[rd_addr];
    end
endmodule
