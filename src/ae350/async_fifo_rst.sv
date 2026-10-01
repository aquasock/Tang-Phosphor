// SPDX-License-Identifier: GPL-3.0-only
//
// Dual-clock FIFO with a first-word-fall-through read side and per-domain
// resets.  Structure follows async_fifo.sv (and colibri's cc_ram_fifo):
// binary pointers are converted to registered Gray code, each Gray pointer
// crosses into the other domain through two flip-flop stages, and full and
// empty are computed from the synchronized pointers.
//
// Unlike async_fifo.sv, which keeps its entries across a reset of either
// side, this FIFO clears both pointer sets and the read-side head valid when
// wrst/rrst are asserted.  Both resets must be derived from the same slow
// reset and held together long enough for the Gray-pointer synchronizers to
// settle; after both release, each side observes an empty FIFO.  The memory
// itself is not cleared, which is harmless because the reset pointers make
// every stale entry unreachable.

module async_fifo_rst #(
    parameter int WIDTH      = 32,
    parameter int DEPTH_BITS = 9,
    parameter string RAMSTYLE = "block_ram"
) (
    input  logic             wclk,
    input  logic             wrst,
    input  logic [WIDTH-1:0] wdata,
    input  logic             wvalid,
    output logic             wready,

    input  logic             rclk,
    input  logic             rrst,
    output logic [WIDTH-1:0] rdata,
    output logic             rvalid,
    output logic             rempty,
    input  logic             rready
);

    localparam int PTR = DEPTH_BITS + 1;

    (* syn_ramstyle = RAMSTYLE *) logic [WIDTH-1:0] memory [0:(1 << DEPTH_BITS) - 1];

    logic [PTR-1:0] wptr       = '0;
    logic [PTR-1:0] wptr_gray  = '0;
    logic [PTR-1:0] rptr       = '0;
    logic [PTR-1:0] rptr_gray  = '0;

    logic [PTR-1:0] wptr_gray_meta /* synthesis syn_srlstyle = "registers" */ = '0;
    logic [PTR-1:0] wptr_gray_sync /* synthesis syn_srlstyle = "registers" */ = '0;
    logic [PTR-1:0] rptr_gray_meta /* synthesis syn_srlstyle = "registers" */ = '0;
    logic [PTR-1:0] rptr_gray_sync /* synthesis syn_srlstyle = "registers" */ = '0;

    function automatic logic [PTR-1:0] to_gray(input logic [PTR-1:0] value);
        return value ^ (value >> 1);
    endfunction

    // Write side.  wready is registered from the pointer the write leaves
    // behind, so the producer's handshake sees a flip-flop rather than the
    // pointer comparison, and it compares against the synchronized read
    // pointer of the current cycle (never optimistic).
    wire [PTR-1:0] rptr_gray_w = rptr_gray_sync;
    logic wready_q = 1'b1;
    assign wready = wready_q;
    wire write = wvalid && wready;
    wire [PTR-1:0] wptr_gray_next = write ? to_gray(wptr + 1'b1) : wptr_gray;

    always_ff @(posedge wclk) begin
        if (wrst) begin
            rptr_gray_meta <= '0;
            rptr_gray_sync <= '0;
            wptr           <= '0;
            wptr_gray      <= '0;
            wready_q       <= 1'b1;
        end else begin
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
    end

    // Read side: load the output register whenever it is empty or taken.
    logic head_valid = 1'b0;
    assign rvalid = head_valid;

    wire empty = rptr_gray == wptr_gray_sync;
    assign rempty = empty;
    wire load  = !empty && (!head_valid || rready);

    always_ff @(posedge rclk) begin
        if (rrst) begin
            wptr_gray_meta <= '0;
            wptr_gray_sync <= '0;
            rptr           <= '0;
            rptr_gray      <= '0;
            head_valid     <= 1'b0;
        end else begin
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
    end

endmodule
