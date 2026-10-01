// SPDX-License-Identifier: GPL-3.0-only
//
// Play stream from the AE350 to the FPGA player: entries the CPU writes
// through ae350_exts_regs (0x090-0x098) cross from the AE350 bus clock into
// the transport clock through async_fifo, and are unpacked into the same
// start/end/cancel pulses and valid/ready byte stream the player takes from
// the BL616 transport.
//
// Entry: {kind[1:0], count[1:0], data[31:0]}
//   kind 0  data: count + 1 bytes, least significant byte first
//   kind 1  start of a stream
//   kind 2  end of the stream (after its last byte has been taken)
//   kind 3  cancel
// Entries are handled strictly in order, so an end or cancel follows every
// byte written before it.

module ae350_play_stream (
    // AE350 bus side.
    input  logic        wclk,
    input  logic        wvalid,
    input  logic [1:0]  wkind,
    input  logic [1:0]  wcount,
    input  logic [31:0] wdata,
    output logic        wready,

    // Player side.
    input  logic        clk,
    input  logic        rst,
    output logic        start,
    output logic        stop,
    output logic        cancel,
    output logic [7:0]  data,
    output logic        valid,
    input  logic        ready,
    output logic [15:0] stream_id    // counts starts, for the player's session id
);

    logic [35:0] entry;
    logic        entry_valid;
    logic        entry_take;

    async_fifo #(
        .WIDTH      (36),
        .DEPTH_BITS (9)
    ) fifo (
        .wclk   (wclk),
        .wdata  ({wkind, wcount, wdata}),
        .wvalid (wvalid),
        .wready (wready),
        .rclk   (clk),
        .rdata  (entry),
        .rvalid (entry_valid),
        .rready (entry_take)
    );

    // Unpacker: a data entry occupies the byte shifter until its last byte is
    // taken; control entries become one-cycle pulses.
    logic [31:0] word;
    logic [1:0]  left;
    logic        busy;

    assign entry_take = entry_valid && !busy && !rst;
    assign data       = word[7:0];
    assign valid      = busy;

    always_ff @(posedge clk) begin
        start  <= 1'b0;
        stop   <= 1'b0;
        cancel <= 1'b0;

        if (busy && ready) begin
            word <= word >> 8;
            left <= left - 2'd1;
            if (left == 2'd0)
                busy <= 1'b0;
        end

        if (entry_take) begin
            unique case (entry[35:34])
                2'd0: begin
                    word <= entry[31:0];
                    left <= entry[33:32];
                    busy <= 1'b1;
                end
                2'd1: begin
                    start     <= 1'b1;
                    stream_id <= stream_id + 16'd1;
                end
                2'd2: stop   <= 1'b1;
                2'd3: cancel <= 1'b1;
            endcase
        end

        if (rst) begin
            busy      <= 1'b0;
            start     <= 1'b0;
            stop      <= 1'b0;
            cancel    <= 1'b0;
            stream_id <= 16'd0;
        end
    end

endmodule
