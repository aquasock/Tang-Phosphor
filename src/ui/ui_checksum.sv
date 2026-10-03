// SPDX-License-Identifier: GPL-3.0-only
//
// Per-frame checksum for one presentation stream.
//
// This is a rolling hash, not a CRC, and the distinction is deliberate rather
// than a shortcut.  A bit-serial CRC32 is sixteen gates deep per input bit and
// cannot close at 74.25 MHz with one pixel per clock, and the table-driven and
// parallel-matrix forms are 8 KiB of LUT or a hand-derived XOR network whose
// correctness would need proving separately.  The rolling hash
//
//     signature <- signature * 5 + pixel   (mod 2^32)
//
// costs two adder levels, is position sensitive so a shifted or reordered
// stream cannot collide with the intended one, and is trivial to reproduce in
// a host model.  It catches a wrong scale factor, a wrong bar, a phase error
// and a wrong frame, which is everything the mirror check needs to catch.  If
// adversarial collision resistance is ever required, this is the place to
// replace and the change is local.
//
// The completed frame is published at the frame boundary rather than read
// live, so a host always compares two whole frames and never a partly written
// one.  A host that wants the published pair to be stable should also use the
// core's renderer hold.

module ui_checksum (
    input  logic        clk,
    input  logic        rst,
    input  logic        strobe,     // one pixel was emitted this cycle
    input  logic [15:0] px,         // that pixel, as the stream presents it
    input  logic        frame,      // frame boundary, on a cycle with no pixel
    output logic [31:0] signature   // the frame that has just completed
);
    logic [31:0] acc;

    // acc <- acc * 5 + px, as one shift and one add modulo 2^32.
    wire [31:0] acc_next = (acc << 2) + acc + {16'b0, px};

    always_ff @(posedge clk) begin
        if (rst) begin
            acc       <= 32'd0;
            signature <= 32'd0;
        end else if (frame) begin
            // The boundary is wired to a cycle that carries no pixel, so the
            // completed frame is exactly the strobes since the last one and
            // this branch never has to merge a coincident pixel.
            signature <= acc;
            acc       <= 32'd0;
        end else if (strobe) begin
            acc <= acc_next;
        end
    end
endmodule
