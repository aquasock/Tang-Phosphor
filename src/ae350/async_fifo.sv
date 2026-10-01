// SPDX-License-Identifier: GPL-3.0-only
//
// Dual-clock FIFO with a first-word-fall-through read side.
//
// Structure follows colibri's cc_ram_fifo (CERN-OHL-W-2.0, reference only):
// binary pointers are converted to registered Gray code, each Gray pointer
// crosses into the other domain through two flip-flop stages, and full and
// empty are computed from the synchronized pointers.  The memory is a simple
// dual-port RAM with independent clocks; the read side keeps the head entry
// in the RAM's output register, so rdata is valid whenever rvalid is high.
//
// The pointers start at zero from configuration; the FIFO has no reset and
// must only be used by logic that tolerates entries across a reset of
// either side.

module async_fifo #(
    parameter int WIDTH      = 32,
    parameter int DEPTH_BITS = 9
) (
    input  logic             wclk,
    input  logic [WIDTH-1:0] wdata,
    input  logic             wvalid,
    output logic             wready,

    input  logic             rclk,
    output logic [WIDTH-1:0] rdata,
    output logic             rvalid,
    input  logic             rready
);

    localparam int PTR = DEPTH_BITS + 1;

    (* syn_ramstyle = "block_ram" *) logic [WIDTH-1:0] memory [0:(1 << DEPTH_BITS) - 1];

    logic [PTR-1:0] wptr = '0;
    logic [PTR-1:0] wptr_gray = '0;
    logic [PTR-1:0] rptr = '0;
    logic [PTR-1:0] rptr_gray = '0;

    logic [PTR-1:0] wptr_gray_meta /* synthesis syn_srlstyle = "registers" */ = '0;
    logic [PTR-1:0] wptr_gray_sync /* synthesis syn_srlstyle = "registers" */ = '0;
    logic [PTR-1:0] rptr_gray_meta /* synthesis syn_srlstyle = "registers" */ = '0;
    logic [PTR-1:0] rptr_gray_sync /* synthesis syn_srlstyle = "registers" */ = '0;

    function automatic logic [PTR-1:0] to_gray(input logic [PTR-1:0] value);
        return value ^ (value >> 1);
    endfunction

    // Write side.  wready is registered from the pointer the write leaves
    // behind, so the producer's handshake sees a flip-flop rather than the
    // pointer comparison.  It compares against the synchronized read pointer
    // of the current cycle, so space the reader frees appears one cycle
    // later than with a combinational flag; it is never optimistic.
    wire [PTR-1:0] rptr_gray_w = rptr_gray_sync;
    logic wready_q = 1'b1;
    assign wready = wready_q;
    wire write = wvalid && wready;
    wire [PTR-1:0] wptr_gray_next = write ? to_gray(wptr + 1'b1) : wptr_gray;

    always_ff @(posedge wclk) begin
        rptr_gray_meta <= rptr_gray;
        rptr_gray_sync <= rptr_gray_meta;
        wready_q <= wptr_gray_next !=
                    {~rptr_gray_w[PTR-1:PTR-2], rptr_gray_w[PTR-3:0]};
        if (write) begin
            memory[wptr[DEPTH_BITS-1:0]] <= wdata;
            wptr      <= wptr + 1'b1;
            wptr_gray <= to_gray(wptr + 1'b1);
        end
    end

    // Read side: load the output register whenever it is empty or taken.
    logic head_valid = 1'b0;
    assign rvalid = head_valid;

    wire empty = rptr_gray == wptr_gray_sync;
    wire load  = !empty && (!head_valid || rready);

    always_ff @(posedge rclk) begin
        wptr_gray_meta <= wptr_gray;
        wptr_gray_sync <= wptr_gray_meta;
        if (load) begin
            rdata     <= memory[rptr[DEPTH_BITS-1:0]];
            rptr      <= rptr + 1'b1;
            rptr_gray <= to_gray(rptr + 1'b1);
        end
        if (load)
            head_valid <= 1'b1;
        else if (rready)
            head_valid <= 1'b0;
    end

endmodule
