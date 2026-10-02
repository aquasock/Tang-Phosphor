// SPDX-License-Identifier: GPL-3.0-only
//
// Demo raster writer: the stand-in renderer for the frame store.
//
// It exists to prove the architecture before any real menu work, so it keeps
// the contract a menu renderer will have to meet -- fill the back bank, raise
// render_done, and wait to be allowed to fill the other bank.  It knows
// nothing about panels, sockets, or scan rates.
//
// Patterns, in order, each held about a second:
//   0 red   1 green   2 blue   3 white   4 black
//   5 eight vertical colour bars
//   6 red/green ramp
//   7 test card: border, one corner block, a diagonal and an anti-diagonal
//
// Pattern 7 is the orientation and scaling check.  A border that comes out
// uneven, a corner block in the wrong corner, or a diagonal that runs the
// wrong way identifies a flipped module, a wrong scale factor, or a shifted
// active rectangle in one glance rather than by reasoning about colours.
//
// `we` is combinational from the state so that the store samples the address
// and the pixel on the same edge that the raster advances; registering it
// would drop the first pixel of every frame.

module ui_pattern_demo #(
    parameter integer W       = 96,
    parameter integer H       = 64,
    parameter integer CLK_MHZ = 50,
    parameter integer HOLD_MS = 1000
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        bank,           // the bank the outputs are reading
    input  logic        render_enable,
    input  logic        hold,           // freeze on the current pattern
    output logic [2:0]  pattern,        // the pattern currently being written
    output logic        we,
    output logic        wr_bank,
    output logic [6:0]  wr_x,
    output logic [5:0]  wr_y,
    output logic [15:0] wr_px,
    output logic        render_done
);
    localparam [31:0] HOLD_TICKS = HOLD_MS * CLK_MHZ * 1000;
    localparam [6:0]  XLAST      = W - 1;
    localparam [5:0]  YLAST      = H - 1;
    localparam [2:0]  LAST_PAT   = 3'd7;
    localparam [7:0]  ANTI_LAST  = W - 1;

    typedef enum logic [1:0] { S_IDLE, S_WRITE, S_HOLD } state_t;

    state_t      state = S_IDLE;
    logic [6:0]  wr_x_r = 7'd0;
    logic [5:0]  wr_y_r = 6'd0;
    logic        wr_bank_r = 1'b0;
    logic [2:0]  pat = 3'd0;
    logic [31:0] hold_cnt = 32'd0;

    assign pattern = pat;
    assign we      = (state == S_WRITE);
    assign wr_x    = wr_x_r;
    assign wr_y    = wr_y_r;
    assign wr_bank = wr_bank_r;

    // ------------------------------------------------------------------
    // Patterns, RGB565.
    // ------------------------------------------------------------------
    function automatic logic [15:0] pattern_pixel(
        input logic [6:0] px,
        input logic [5:0] py,
        input logic [2:0] p
    );
        case (p)
            3'd0: pattern_pixel = 16'hF800;                 // red
            3'd1: pattern_pixel = 16'h07E0;                 // green
            3'd2: pattern_pixel = 16'h001F;                 // blue
            3'd3: pattern_pixel = 16'hFFFF;                 // white
            3'd4: pattern_pixel = 16'h0000;                 // black
            3'd5: begin                                     // eight 12 px bars
                case (px / 7'd12)
                    7'd0: pattern_pixel = 16'hF800;         // red
                    7'd1: pattern_pixel = 16'h07E0;         // green
                    7'd2: pattern_pixel = 16'h001F;         // blue
                    7'd3: pattern_pixel = 16'h07FF;         // cyan
                    7'd4: pattern_pixel = 16'hF81F;         // magenta
                    7'd5: pattern_pixel = 16'hFFE0;         // yellow
                    7'd6: pattern_pixel = 16'hFFFF;         // white
                    default: pattern_pixel = 16'h0000;      // black
                endcase
            end
            3'd6: pattern_pixel = {px[6:2], py[5:0], py[5:1]};
            3'd7: begin                                     // orientation card
                if (px == 7'd0 || px == XLAST || py == 6'd0 || py == YLAST)
                    pattern_pixel = 16'hFFFF;               // border
                else if (px < 7'd8 && py < 6'd8)
                    pattern_pixel = 16'hFFFF;               // corner marker
                else if (px == {1'b0, py})
                    pattern_pixel = 16'h07E0;               // main diagonal
                else if (({1'b0, px} + {2'b0, py}) == ANTI_LAST)
                    pattern_pixel = 16'hF800;               // anti-diagonal
                else
                    pattern_pixel = 16'h0000;
            end
            default: pattern_pixel = 16'h0000;
        endcase
    endfunction

    always_comb wr_px = pattern_pixel(wr_x_r, wr_y_r, pat);

    always_ff @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            wr_x_r     <= 7'd0;
            wr_y_r     <= 6'd0;
            wr_bank_r  <= 1'b0;
            pat        <= 3'd0;
            hold_cnt   <= 32'd0;
            render_done <= 1'b0;
        end else begin
            render_done <= 1'b0;

            case (state)
                // Wait until no swap is outstanding, then fill the back bank.
                S_IDLE: begin
                    if (render_enable) begin
                        wr_x_r    <= 7'd0;
                        wr_y_r    <= 6'd0;
                        wr_bank_r <= ~bank;
                        state     <= S_WRITE;
                    end
                end

                S_WRITE: begin
                    if (wr_x_r == XLAST && wr_y_r == YLAST) begin
                        render_done <= 1'b1;
                        hold_cnt    <= HOLD_TICKS;
                        state       <= S_HOLD;
                    end else if (wr_x_r == XLAST) begin
                        wr_x_r <= 7'd0;
                        wr_y_r <= wr_y_r + 6'd1;
                    end else begin
                        wr_x_r <= wr_x_r + 7'd1;
                    end
                end

                // Let the completed frame stay up before drawing the next one.
                S_HOLD: begin
                    // While held, stay on this pattern and keep counting
                    // nothing: a host comparing CRCs needs a frame it can
                    // predict, and the pattern must stop changing under it.
                    if (hold) begin
                        hold_cnt <= hold_cnt;
                    end else if (hold_cnt == 32'd0) begin
                        pat   <= (pat == LAST_PAT) ? 3'd0 : pat + 3'd1;
                        state <= S_IDLE;
                    end else begin
                        hold_cnt <= hold_cnt - 32'd1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
