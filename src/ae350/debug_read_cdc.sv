// SPDX-License-Identifier: GPL-3.0-only
//
// Tang-Control debug reads of registers in another clock domain.
//
// A request/acknowledge toggle loop runs continuously.  Each round, the
// debug side launches the current debug address with a toggled request;
// the target side, after synchronizing the request, holds that address on
// taddr, waits TARGET_LATENCY cycles for the target's registered read data,
// captures it, and toggles the acknowledge; the debug side, after
// synchronizing the acknowledge, takes the captured word and starts the next
// round.  Every multi-bit value crosses only while it is held stable, so
// each word read is one the target register actually held.  A round takes
// about ten cycles of the slower clock, while iosys_bl616 samples
// debug_rdata six UART bytes after it sets debug_address.

module debug_read_cdc #(
    parameter int ADDR_BITS      = 8,
    parameter int TARGET_LATENCY = 2
) (
    input  logic                 dclk,
    input  logic [ADDR_BITS-1:0] daddr,
    output logic [31:0]          drdata,

    input  logic                 tclk,
    output logic [ADDR_BITS-1:0] taddr,
    input  logic [31:0]          trdata
);

    // Debug side.
    logic                 req = 1'b0;
    logic [ADDR_BITS-1:0] req_addr = '0;
    logic                 ack_meta /* synthesis syn_srlstyle = "registers" */ = 1'b0;
    logic                 ack_sync /* synthesis syn_srlstyle = "registers" */ = 1'b0;

    // Target side.
    logic                 ack = 1'b0;
    logic                 req_meta /* synthesis syn_srlstyle = "registers" */ = 1'b0;
    logic                 req_sync /* synthesis syn_srlstyle = "registers" */ = 1'b0;
    logic [3:0]           wait_count = '0;
    logic                 busy = 1'b0;
    logic [31:0]          held_data = '0;

    always_ff @(posedge dclk) begin
        ack_meta <= ack;
        ack_sync <= ack_meta;
        if (ack_sync == req) begin
            drdata   <= held_data;
            req_addr <= daddr;
            req      <= !req;
        end
    end

    always_ff @(posedge tclk) begin
        req_meta <= req;
        req_sync <= req_meta;
        if (!busy) begin
            if (req_sync != ack) begin
                taddr      <= req_addr;
                wait_count <= 4'(TARGET_LATENCY + 1);
                busy       <= 1'b1;
            end
        end else if (wait_count != 0) begin
            wait_count <= wait_count - 4'd1;
        end else begin
            held_data <= trdata;
            ack       <= req_sync;
            busy      <= 1'b0;
        end
    end

endmodule
