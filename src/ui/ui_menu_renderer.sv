// SPDX-License-Identifier: GPL-3.0-only
//
// Menu renderer, slice 1: a frame writer that proves the cell grid.
//
// The menu is not an overlay.  The raster does not hand this module a
// coordinate and a colour as the beam passes; it fills the back bank of the
// shared frame store, raises render_done when the bank is complete, and waits
// to be allowed to fill the other bank.  That is the contract
// `src/ui/ui_pattern_demo.sv` already meets, and it is deliberately the shape
// copied here rather than `phosphor_album_ui.sv`, which is a pixel-rate
// evaluator on a 16x20 grid that cannot tile this store.
//
// Slice 1 draws a fixed frame and nothing else.  Its pixel values are derived
// from cell indices alone, so the frame is its own address map: every one of
// the 6144 pixels carries the coordinates it was written at, and a reader can
// confirm that a pixel landed where it belongs without any glyph, font or
// state input existing yet.  The 6x8 cell tiles the 96x64 store exactly, 16
// columns by 8 rows with nothing over, which is the geometry later slices will
// place text into.  Later slices add the font and text grid, then content and
// layout from the state inputs that are already wired.
//
// Handshake.  The swap lowers render_enable while a swap is pending and raises
// it again once every output has crossed a frame boundary, at which point the
// back bank has changed.  render_enable is still high on the cycle render_done
// is raised, because the swap has not yet observed the pulse, so sampling it
// there would let the renderer start the next frame into the bank it just
// wrote -- behind the outputs' backs, since the bank has not flipped yet.  The
// demo avoids that with a dwell long enough for the swap to land.  A menu has
// no dwell to hide behind, so this module waits for the swap explicitly: it
// will not begin a frame until it has seen render_enable go low (the swap
// acknowledged render_done) and then high again (the swap completed).  `hold`
// freezes the renderer without tearing the frame in flight: it is consulted
// only between frames.

module ui_menu_renderer #(
    parameter integer W      = 96,
    parameter integer H      = 64,
    parameter integer CELL_W = 6,
    parameter integer CELL_H = 8
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        bank,           // the bank the outputs are reading
    input  logic        render_enable,  // the back bank may be filled
    input  logic        hold,           // freeze: do not begin another frame
    output logic        we,
    output logic        wr_bank,
    output logic [6:0]  wr_x,
    output logic [5:0]  wr_y,
    output logic [15:0] wr_px,
    output logic        render_done
);
    localparam [6:0] XLAST = 7'(W - 1);
    localparam [5:0] YLAST = 6'(H - 1);
    localparam integer COLS = W / CELL_W;    // 16
    localparam integer ROWS = H / CELL_H;    // 8

    typedef enum logic { S_IDLE, S_WRITE } state_t;

    state_t     state    = S_IDLE;
    logic       armed    = 1'b1;   // the swap is idle at power-on
    logic [6:0] x        = 7'd0;
    logic [5:0] y        = 6'd0;
    logic       wr_bank_r = 1'b0;

    assign we      = (state == S_WRITE);
    assign wr_x    = x;
    assign wr_y    = y;
    assign wr_bank = wr_bank_r;

    // The slice-1 proof frame.  Each 16-bit word names the pixel it is written
    // at, so the frame encodes its own addressing:
    //
    //   [15]     reserved, zero
    //   [14:12]  cell row      (0..7)     py / 8
    //   [11]     reserved, zero
    //   [10:7]   cell column   (0..15)    px / 6
    //   [6:4]    pixel in cell, column (0..5)  px % 6
    //   [3:1]    pixel in cell, row    (0..7)  py % 8
    //   [0]      reserved, zero
    //
    // Every pixel in the frame is therefore a distinct value, which is what
    // makes "the renderer wrote the right pixel at the right coordinate" a
    // check rather than an eyeball.
    function automatic logic [15:0] cell_pixel(
        input logic [6:0] px,
        input logic [5:0] py
    );
        logic [6:0] col;
        logic [2:0] in_col;
        logic [5:0] row;
        logic [2:0] in_row;
        begin
            col    = px / 7'd6;
            in_col = 3'(px % 7'd6);
            row    = py / 6'd8;
            in_row = 3'(py % 6'd8);
            cell_pixel = {1'b0, row[2:0], 1'b0, col[3:0], in_col[2:0], in_row[2:0], 1'b0};
        end
    endfunction

    always_comb wr_px = cell_pixel(x, y);

    always_ff @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            armed     <= 1'b1;
            x         <= 7'd0;
            y         <= 6'd0;
            wr_bank_r <= 1'b0;
            render_done <= 1'b0;
        end else begin
            render_done <= 1'b0;

            case (state)
                // Between frames.  Never begin one until the swap has both
                // acknowledged the last render_done and completed, so the back
                // bank is known to have changed underneath us.
                S_IDLE: begin
                    if (!render_enable) begin
                        armed <= 1'b1;      // swap pending: acknowledged
                    end else if (armed && !hold) begin
                        x         <= 7'd0;
                        y         <= 6'd0;
                        wr_bank_r <= ~bank;
                        armed     <= 1'b0;
                        state     <= S_WRITE;
                    end
                end

                // Raster order, one pixel per clock.  `we` is combinational
                // from the state so the store samples this cycle's address and
                // pixel on the same edge that x and y advance.
                S_WRITE: begin
                    if (x == XLAST && y == YLAST) begin
                        render_done <= 1'b1;
                        state       <= S_IDLE;
                    end else if (x == XLAST) begin
                        x <= 7'd0;
                        y <= y + 6'd1;
                    end else begin
                        x <= x + 7'd1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
