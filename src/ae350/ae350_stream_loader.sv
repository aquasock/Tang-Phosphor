// SPDX-License-Identifier: GPL-3.0-only
//
// Tang-Control stream receiver for loading AE350 programs.
//
// A port of Tang-PSX gateware/stream_loader.py, which loaded every Tang-PSX
// program on hardware.  iosys_bl616 delivers a stream (tangctl.py stream
// <file>) as bytes with single-cycle start, end, and cancel strobes in its
// clock domain.  The bytes are packed into little-endian 32-bit words and
// passed, with the start/end/cancel events in stream order, through a
// dual-clock FIFO to the CPU domain.  Each entry is a tag and a word:
//
//     DATA   (0)  packed word
//     START  (1)  0
//     END    (2)  total byte count of the session
//     CANCEL (3)  0
//
// A session's final partial word is queued as DATA, zero-padded, before
// its END.  The stream is held while the FIFO cannot take the next word or
// an event is still waiting, so no byte is dropped.  Tang-Control sends a
// session's END only after its last byte is taken but may open the next
// session before that END has been queued, so END and CANCEL are latched
// when they arrive and queued ahead of the next START.  overflow is sticky
// and reports an event strobe that arrived while the previous one of the
// same kind was still pending, which the stop-and-wait protocol should never
// produce.  srst resets the stream side; the FIFO keeps its entries.

module ae350_stream_loader #(
    parameter int DEPTH_BITS = 9
) (
    // Stream side (iosys clock).
    input  logic        sclk,
    input  logic        srst,
    input  logic        start,
    input  logic        stop,
    input  logic        cancel,
    input  logic [7:0]  data,
    input  logic        valid,
    output logic        ready,
    output logic [31:0] sessions,
    output logic [31:0] bytes,
    output logic [31:0] ends,
    output logic [31:0] cancels,
    output logic        overflow,

    // CPU side.
    input  logic        cclk,
    output logic        entry_valid,
    output logic [1:0]  entry_tag,
    output logic [31:0] entry_data,
    input  logic        entry_pop
);

    localparam logic [1:0] TAG_DATA   = 2'd0;
    localparam logic [1:0] TAG_START  = 2'd1;
    localparam logic [1:0] TAG_END    = 2'd2;
    localparam logic [1:0] TAG_CANCEL = 2'd3;

    logic [31:0] word;
    logic [1:0]  byte_index;
    logic [31:0] byte_count;
    logic        start_p;
    logic        end_p;
    logic        cancel_p;
    logic        end_flush;
    logic [31:0] end_word;
    logic [31:0] end_count;

    logic        sink_valid;
    logic        sink_ready;
    logic [1:0]  sink_tag;
    logic [31:0] sink_data;
    logic [31:0] next_word;

    assign ready = sink_ready && !start_p && !end_p && !cancel_p;
    wire take      = valid && ready;
    wire word_done = take && byte_index == 2'd3;
    wire push      = !word_done && sink_ready;

    always_comb begin
        next_word = word;
        next_word[8 * byte_index +: 8] = data;
    end

    // FIFO priority: a completed word, the pending session's partial word,
    // END, CANCEL, then the next session's START.
    always_comb begin
        sink_valid = 1'b1;
        sink_tag   = TAG_DATA;
        sink_data  = '0;
        if (word_done) begin
            sink_data = next_word;
        end else if (end_p && end_flush) begin
            sink_data = end_word;
        end else if (end_p) begin
            sink_tag  = TAG_END;
            sink_data = end_count;
        end else if (cancel_p) begin
            sink_tag  = TAG_CANCEL;
        end else if (start_p) begin
            sink_tag  = TAG_START;
        end else begin
            sink_valid = 1'b0;
        end
    end

    always_ff @(posedge sclk) begin
        if (start)
            sessions <= sessions + 32'd1;
        if (take)
            bytes <= bytes + 32'd1;
        if (stop)
            ends <= ends + 32'd1;
        if (cancel)
            cancels <= cancels + 32'd1;

        if (take) begin
            word       <= byte_index == 2'd3 ? '0 : next_word;
            byte_index <= byte_index + 2'd1;
            byte_count <= byte_count + 32'd1;
        end
        if (push) begin
            if (end_p && end_flush) begin
                end_flush <= 1'b0;
            end else if (end_p) begin
                end_p <= 1'b0;
            end else if (cancel_p) begin
                cancel_p <= 1'b0;
            end else if (start_p) begin
                start_p    <= 1'b0;
                word       <= '0;
                byte_index <= '0;
                byte_count <= '0;
            end
        end
        if (stop) begin
            if (end_p)
                overflow <= 1'b1;
            end_p     <= 1'b1;
            end_flush <= byte_index != 2'd0;
            end_word  <= word;
            end_count <= byte_count;
        end
        if (cancel) begin
            if (cancel_p)
                overflow <= 1'b1;
            cancel_p   <= 1'b1;
            word       <= '0;
            byte_index <= '0;
        end
        if (start) begin
            if (start_p)
                overflow <= 1'b1;
            start_p <= 1'b1;
        end

        if (srst) begin
            word       <= '0;
            byte_index <= '0;
            byte_count <= '0;
            start_p    <= 1'b0;
            end_p      <= 1'b0;
            cancel_p   <= 1'b0;
            end_flush  <= 1'b0;
            sessions   <= '0;
            bytes      <= '0;
            ends       <= '0;
            cancels    <= '0;
            overflow   <= 1'b0;
        end
    end

    async_fifo #(
        .WIDTH      (34),
        .DEPTH_BITS (DEPTH_BITS)
    ) fifo (
        .wclk   (sclk),
        .wdata  ({sink_tag, sink_data}),
        .wvalid (sink_valid),
        .wready (sink_ready),
        .rclk   (cclk),
        .rdata  ({entry_tag, entry_data}),
        .rvalid (entry_valid),
        .rready (entry_pop)
    );

endmodule
