// SPDX-License-Identifier: GPL-3.0-only
//
// PMOD personality: Digilent Pmod ENC (Revision A).
//
// A rotary shaft encoder with an integral push button and one slide switch.  It
// is the first personality whose pins are all inputs, so it is the first the
// socket layer only ever reads -- and the first that needs its module present
// to mean anything, since a missing module leaves four pins floating.
//
// Lane order follows the module's J1 header, from the reference manual:
//
//   lane 0 = pin 1  A    quadrature, pulled high by the module, low when closed
//   lane 1 = pin 2  B    the other quadrature phase
//   lane 2 = pin 3  BTN  integral push button, native state low
//   lane 3 = pin 4  SWT  slide switch, off reads low
//
// A host that cares about the difference between released and pressed owns the
// polarity, so this exposes the raw levels as well as a decoded reading rather
// than forcing one interpretation.
//
// Debouncing is a saturating counter per channel: an input must hold a new
// value for DEBOUNCE_CYCLES before it is believed.  A hand-turned knob produces
// edges at a few hertz at most, so the filter can be generous at no cost in
// responsiveness -- and it is what makes the quadrature count trustworthy,
// because contact bounce on a mechanical encoder otherwise reads as extra
// clicks, which is precisely the failure a menu control cannot have.

module pmod_enc #(
    // At 74.25 MHz, 74_250 is one millisecond.
    parameter integer DEBOUNCE_CYCLES = 74_250
) (
    input  logic        clk,
    input  logic        rst,

    // Socket-facing lanes, in Digilent pin order.
    input  logic [7:0]  lane_i,
    output logic [7:0]  lane_o,
    output logic [7:0]  lane_oe,

    // Decoded state, for the register bank.
    output logic [31:0] count,      // offset by 2^31; four counts per detent
    output logic [3:0]  raw,        // the four pins as read
    output logic        button,     // debounced and normalised, 1 = pressed
    output logic        switch_on   // debounced and normalised, 1 = on
);
    // Nothing is driven: every module pin is an input to the host.
    assign lane_o  = 8'h00;
    assign lane_oe = 8'h00;

    logic [3:0] raw_q;
    assign raw = raw_q;
    always_ff @(posedge clk) raw_q <= lane_i[3:0];

    // ------------------------------------------------------------------
    // Per-channel debounce.
    // ------------------------------------------------------------------
    logic [3:0]  stable;
    logic [23:0] hold [0:3];

    genvar c;
    generate
        for (c = 0; c < 4; c = c + 1) begin : g_debounce
            always_ff @(posedge clk) begin
                if (rst) begin
                    stable[c] <= 1'b1;
                    hold[c]   <= 24'd0;
                end else if (lane_i[c] == stable[c]) begin
                    hold[c] <= 24'd0;
                end else if (hold[c] == DEBOUNCE_CYCLES[23:0]) begin
                    stable[c] <= lane_i[c];
                    hold[c]   <= 24'd0;
                end else begin
                    hold[c] <= hold[c] + 24'd1;
                end
            end
        end
    endgenerate

    // ------------------------------------------------------------------
    // Quadrature decode.
    //
    // Only single-step transitions move the count, so a contact that appears to
    // jump two states is ignored rather than counted as a click in an arbitrary
    // direction.
    // ------------------------------------------------------------------
    logic [1:0] quad;
    logic [1:0] quad_q;

    assign quad = {stable[0], stable[1]};   // {A, B}

    always_ff @(posedge clk) begin
        if (rst)
            quad_q <= 2'b11;
        else
            quad_q <= quad;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            count <= 32'h8000_0000;         // zero, expressed as an offset
        end else begin
            case ({quad_q, quad})
                4'b00_01, 4'b01_11, 4'b11_10, 4'b10_00:
                    count <= count + 32'd1;
                4'b00_10, 4'b10_11, 4'b11_01, 4'b01_00:
                    count <= count - 32'd1;
                default: ;
            endcase
        end
    end

    // The button reads low in its native state, which is the released state,
    // and the switch reads low when off.  Both are normalised to "active is
    // one" here.  The button was inverted in the first version; the hardware
    // said so, because a released button read as pressed.
    assign button    = stable[2];
    assign switch_on = stable[3];

    // Contract, not convenience: one detent is exactly four quadrature counts.
    // Measured twice on hardware, five clicks giving +20 and four clicks giving
    // +16, so a consumer divides by four and may treat any other delta as a
    // broken module rather than a condition to handle.  Deliberately no derived
    // register for this: dividing by four is a shift the consumer already gets
    // for free, and a register that does it for them is the first step towards a
    // convenience layer the hardware should not own.
    //
    // The count is incremental, not absolute: a reload resets it to centred, so
    // a consumer must treat a reset as "position unknown, counting from here".
    // Nothing here latches or queues either, so a momentary button press shorter
    // than the polling interval will be missed by design.

endmodule
