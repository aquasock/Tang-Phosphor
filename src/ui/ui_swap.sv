// SPDX-License-Identifier: GPL-3.0-only
//
// Bank swap for the frame store.
//
// The renderer fills the bank nobody is reading, then asks for a swap.  The
// swap happens only after every registered output has crossed a frame
// boundary, so no output can be half way through a frame when its bank
// changes, and all outputs move to the new frame together.  Until the swap
// completes the renderer is held off, so it cannot overwrite the bank still
// being displayed.
//
// This is the mechanism that makes "all screens show the same frame" a
// property of the design instead of a hope.  A backend that stops ticking
// therefore stalls the swap rather than tearing: the frame simply stays up
// longer, which is visible and harmless where tearing is not.

module ui_swap #(
    parameter integer OUTPUTS = 1
) (
    input  logic               clk,
    input  logic               rst,
    input  logic               render_done,    // the back bank is complete
    input  logic [OUTPUTS-1:0] frame_tick,     // one pulse per output per frame
    output logic               bank,           // the bank the outputs read
    output logic               render_enable   // the renderer may fill the other
);
    logic               pending;
    logic [OUTPUTS-1:0] acked;

    always_ff @(posedge clk) begin
        if (rst) begin
            bank    <= 1'b0;
            pending <= 1'b0;
            acked   <= {OUTPUTS{1'b0}};
        end else begin
            if (render_done && !pending) begin
                pending <= 1'b1;
                acked   <= {OUTPUTS{1'b0}};
            end

            if (pending) begin
                acked <= acked | frame_tick;
                if ((acked | frame_tick) == {OUTPUTS{1'b1}}) begin
                    bank    <= ~bank;
                    pending <= 1'b0;
                end
            end
        end
    end

    assign render_enable = ~pending;
endmodule
