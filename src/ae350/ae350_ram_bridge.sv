// SPDX-License-Identifier: GPL-3.0-only
//
// AE350 RAM port (64-bit AHB-Lite, DDR_H*) to the Gowin DDR3 controller's
// native port (256-bit, one BL8 burst of the x32 array per command), through
// ae350_ram_link.  This module is the half that sits beside the AE350 macro;
// the link carries its line commands across the die to the controller.
//
// The bridge runs on bus_clk, the AE350 bus clock; ae350_ram_link carries its
// commands into the controller's user-clock domain and the read lines back.
// One 256-bit native word is exactly one 32-byte A25 cache line.
//
// Timing: the AE350 macro's AHB outputs arrive after about 4 ns of routing,
// and its inputs need about 5 ns of setup (Tang-PSX core-reference
// AE350-006), so every AHB output here is a register and every macro output
// feeds registers through at most one level of logic.  A transfer's address
// phase is captured as it is accepted and evaluated from registers in the
// next cycle, with HREADY low.  Beats that continue a burst are the
// exception: whether a SEQ beat can complete without waiting is predicted
// from registered burst state plus HTRANS, HWRITE and HADDR, so the rest of a
// cache-line burst runs with no wait states.  A beat is predicted only when
// its address is the next lane of the line the burst is on (p_line, p_beat +
// 1, which also covers a WRAP4 wrap).  The AE350's RAM port has been traced
// issuing a NONSEQ beat on one line followed by SEQ beats on another
// (core-log entry 77); predicting those from burst state alone served them
// from the wrong line, so a SEQ beat whose address does not follow is
// evaluated as a new transfer instead.
//
// Reads: a read that is not a predicted continuation issues one native read
// and waits for it; the line is kept in rbuf and the rest of the burst is
// served from it.  Continuation is decided from the burst state (HTRANS
// SEQ, the burst type, the previous beat's position in the line) and the
// beat's address, and rbuf is only used for beats on the line it holds, so
// it never serves stale or foreign data.
//
// Writes: beats are merged into wbuf with byte enables and written with one
// native command when the burst ends, is known to be complete, or leaves the
// line.  A write that starts a new line, and any read, first waits for wbuf
// to be issued; the controller executes commands in order, so a read issued
// after a write to the same line returns the new data.
//
// DDR3 is mapped at 0x40000000-0x7fffffff.  Any other address on the RAM
// port gets an AHB ERROR response, and an erroneous write is discarded.
// A command (one line read, or one masked line write from wbuf) is sent to
// the link whenever it holds a credit; the link lands it in a FIFO beside
// the controller, which issues it when the controller is ready, and returns
// read lines in order.

module ae350_ram_bridge (
    input  logic         clk,
    input  logic         rst,

    // AE350 RAM port.
    input  logic [31:0]  haddr,
    input  logic [1:0]   htrans,
    input  logic         hwrite,
    input  logic [2:0]   hsize,
    input  logic [2:0]   hburst,
    input  logic [63:0]  hwdata,
    output logic [63:0]  hrdata,
    output logic         hready,
    output logic         hresp,

    // Line commands and read responses, through ae350_ram_link.
    output logic         mem_cmd_valid,
    output logic         mem_cmd_write,
    output logic [24:0]  mem_cmd_line,
    output logic [255:0] mem_cmd_data,
    output logic [31:0]  mem_cmd_mask,   // 1 = byte written
    input  logic         mem_cmd_ready,
    input  logic         mem_idle,
    input  logic         mem_rsp_valid,
    input  logic [255:0] mem_rsp_data,
    output logic         rsp_ready,    // bridge accepts a response (rd_wait)

    // Diagnostics: native reads and writes, read latency from issue to data
    // in clk cycles (sum, maximum), read beats served from rbuf, and ERROR
    // responses.
    output logic [31:0]  reads,
    output logic [31:0]  writes,
    output logic [31:0]  latency_sum,
    output logic [31:0]  latency_max,
    output logic [31:0]  buffer_hits,
    output logic [31:0]  errors,

    // Debug trace of accepted transfers: address, and {predicted, HTRANS,
    // HWRITE, HSIZE, HBURST} in bits 9:0, 16 entries in a ring.  Recording
    // stops eight transfers after the first ERROR response.  trace_status
    // is {frozen, next entry}; state holds the bridge's flags and the
    // link's ready and idle outputs, sampled every cycle.
    output logic [31:0]  trace_addr [16],
    output logic [15:0]  trace_info [16],
    output logic [7:0]   trace_status,
    output logic [31:0]  first_error_addr,
    output logic [31:0]  state
);

    localparam logic [1:0] HTRANS_IDLE   = 2'b00;
    localparam logic [1:0] HTRANS_SEQ    = 2'b11;
    localparam logic [2:0] HBURST_SINGLE = 3'b000;
    localparam logic [2:0] HBURST_WRAP4  = 3'b010;

    // Beats in a fixed-length burst; 0 for SINGLE and INCR, whose end is
    // seen from the next transfer.
    function automatic logic [4:0] burst_beats(input logic [2:0] burst);
        unique case (burst)
            3'b010, 3'b011: return 5'd4;
            3'b100, 3'b101: return 5'd8;
            3'b110, 3'b111: return 5'd16;
            default:        return 5'd0;
        endcase
    endfunction

    // Transfer in its data phase, captured at its address phase.
    logic        c_valid;   // data phase not yet complete
    logic        c_eval;    // not predicted: evaluate in the next cycle
    logic        c_merge;   // write data merges into wbuf on completion
    logic        c_write;
    logic        c_error;
    logic [1:0]  c_beat;
    logic [24:0] c_line;
    logic [7:0]  c_bytes;   // byte lanes of the beat
    logic [2:0]  c_burst;
    logic [4:0]  c_count;

    // Last accepted transfer, for burst continuation.
    logic        p_write;
    logic        p_error;
    logic [24:0] p_line;
    logic [1:0]  p_beat;
    logic [2:0]  p_burst;
    logic [4:0]  p_count;

    // Read line buffer and the read waiting for DDR3.
    logic [255:0] rbuf;
    logic         rbuf_ok;
    logic         rd_pend;
    logic         rd_wait;

    // The bridge is the only response consumer and always accepts a read
    // response while rd_wait is set, so rd_wait doubles as the response
    // FIFO's pop (ae350_ram_link.rsp_ready).
    assign rsp_ready = rd_wait;
    logic [24:0]  rd_line;

    // Write-combining buffer.
    logic [255:0] wbuf;
    logic [31:0]  wmask;
    logic [24:0]  wline;
    logic         wbuf_valid;
    logic         wbuf_open;
    logic         wr_wait;

    logic         error_first;
    logic         hit;

    logic [31:0]  rd_cycles;
    logic         rd_done;

    logic [31:0]  t_addr;
    logic [9:0]   t_info;
    logic         t_record;
    logic [3:0]   t_index;
    logic [3:0]   t_left;
    logic         t_armed;
    logic         t_frozen;

    // Prediction for a SEQ beat, from registered state and the beat's
    // address: the next lane of the same line.
    wire p_next   = haddr[29:5] == p_line && haddr[4:3] == p_beat + 2'd1;
    wire p_cont   = !p_error && (p_burst == HBURST_WRAP4 || p_beat != 2'd3);
    wire p_last   = p_burst == HBURST_SINGLE || p_count + 5'd1 == burst_beats(p_burst);
    wire rd_ok    = p_cont && !p_write && rbuf_ok;
    wire wr_ok    = p_cont && p_write && wbuf_open;
    wire accept   = hready && htrans[1];
    wire predict  = htrans == HTRANS_SEQ && p_next && (hwrite ? wr_ok : rd_ok);
    wire complete = hready && c_valid;
    wire c_last   = c_burst == HBURST_SINGLE || c_count == burst_beats(c_burst);

    // wbuf is issued once no more beats can join it, or at once when a read
    // or a new-line write is waiting; never while a beat that belongs to it
    // is still in its data phase.
    wire merge_pending = c_valid && c_merge;
    wire flush_ready   = wbuf_valid && (!wbuf_open || wr_wait || rd_pend) && !merge_pending;
    wire issue_write   = flush_ready && mem_cmd_ready;
    wire issue_read    = rd_pend && !wbuf_valid && !merge_pending && mem_cmd_ready;

    assign mem_cmd_valid = issue_write || issue_read;
    assign mem_cmd_write = wbuf_valid;
    assign mem_cmd_line  = wbuf_valid ? wline : rd_line;
    assign mem_cmd_data  = wbuf;
    assign mem_cmd_mask  = wmask;

    always_ff @(posedge clk) begin
        if (rd_wait)
            rd_cycles <= rd_cycles + 32'd1;
        rd_done <= 1'b0;
        if (rd_done) begin
            latency_sum <= latency_sum + rd_cycles;
            if (rd_cycles > latency_max)
                latency_max <= rd_cycles;
        end
        if (hit)
            buffer_hits <= buffer_hits + 32'd1;

        // Debug trace, recorded the cycle after each accepted transfer.
        state <= {12'b0, htrans, hwrite, mem_idle, mem_cmd_ready,
                  rd_done, error_first, wr_wait, wbuf_open, wbuf_valid, rd_wait,
                  rd_pend, rbuf_ok, c_merge, c_eval, c_valid, hresp, hready};
        if (hready) begin
            t_addr <= haddr;
            t_info <= {predict, htrans, hwrite, hsize, hburst};
        end
        t_record <= accept;
        if (t_record && !t_frozen) begin
            trace_addr[t_index] <= t_addr;
            trace_info[t_index] <= {6'b0, t_info};
            t_index <= t_index + 4'd1;
            if (t_armed) begin
                t_left <= t_left - 4'd1;
                if (t_left == 4'd1)
                    t_frozen <= 1'b1;
            end
        end
        trace_status <= {t_frozen, 3'b0, t_index};

        // Data phase completes.
        if (complete && c_merge) begin
            for (int b = 0; b < 8; b++) begin
                if (c_bytes[b]) begin
                    wbuf[64 * c_beat + 8 * b +: 8] <= hwdata[8 * b +: 8];
                    wmask[8 * c_beat + b] <= 1'b1;
                end
            end
            wline      <= c_line;
            wbuf_valid <= 1'b1;
        end

        // Address phase.  While HREADY is high the transfer registers load
        // every cycle, so HTRANS only reaches single-register decisions.
        if (hready) begin
            c_valid  <= htrans[1];
            c_merge  <= htrans[1] && predict && hwrite;
            c_eval   <= htrans[1] && !predict;
            c_write  <= hwrite;
            c_error  <= haddr[31:30] != 2'b01;
            c_beat   <= haddr[4:3];
            c_line   <= haddr[29:5];
            c_bytes  <= 8'((16'h00ff >> (4'd8 - (4'd1 << hsize))) << haddr[2:0]);
            c_burst  <= hburst;
            c_count  <= htrans == HTRANS_SEQ ? p_count + 5'd1 : 5'd1;
            hrdata   <= rbuf[64 * (p_beat + 2'd1) +: 64];
            hresp    <= 1'b0;
            hit      <= htrans[1] && predict && !hwrite;
            if (htrans[1] && !predict)
                hready <= 1'b0;
            if (htrans[1])
                wbuf_open <= predict && hwrite && !p_last;
            else if (htrans == HTRANS_IDLE)
                wbuf_open <= 1'b0;
        end
        if (accept) begin
            p_write <= hwrite;
            p_error <= haddr[31:30] != 2'b01;
            p_line  <= haddr[29:5];
            p_beat  <= haddr[4:3];
            p_burst <= hburst;
            p_count <= htrans == HTRANS_SEQ ? p_count + 5'd1 : 5'd1;
        end

        // Evaluate a transfer that was not predicted.
        if (c_eval) begin
            c_eval <= 1'b0;
            if (c_error) begin
                hresp       <= 1'b1;
                error_first <= 1'b1;
                errors      <= errors + 32'd1;
                if (!t_armed) begin
                    t_armed          <= 1'b1;
                    t_left           <= 4'd8;
                    first_error_addr <= t_addr;   // held since the accept: HREADY is low
                end
            end else if (!c_write) begin
                rd_pend <= 1'b1;
                rd_line <= c_line;
                rbuf_ok <= 1'b0;
            end else begin
                wbuf_open <= !c_last;
                if (wbuf_valid && !issue_write) begin
                    wr_wait <= 1'b1;
                end else begin
                    c_merge <= 1'b1;
                    hready  <= 1'b1;
                end
            end
        end

        if (error_first) begin
            error_first <= 1'b0;
            hready      <= 1'b1;
        end

        if (issue_write) begin
            wbuf_valid <= 1'b0;
            wmask      <= '0;
            writes     <= writes + 32'd1;
            if (wr_wait) begin
                wr_wait <= 1'b0;
                c_merge <= 1'b1;
                hready  <= 1'b1;
            end
        end

        if (issue_read) begin
            rd_pend   <= 1'b0;
            rd_wait   <= 1'b1;
            rd_cycles <= 32'd1;
            reads     <= reads + 32'd1;
        end

        if (mem_rsp_valid && rd_wait) begin
            rd_wait     <= 1'b0;
            rbuf        <= mem_rsp_data;
            rbuf_ok     <= 1'b1;
            hrdata      <= mem_rsp_data[64 * c_beat +: 64];
            hready      <= 1'b1;
            rd_done     <= 1'b1;
        end

        if (rst) begin
            hready      <= 1'b1;
            hresp       <= 1'b0;
            hit         <= 1'b0;
            c_valid     <= 1'b0;
            c_eval      <= 1'b0;
            c_merge     <= 1'b0;
            p_write     <= 1'b0;
            p_error     <= 1'b1;
            p_line      <= '0;
            p_beat      <= 2'd0;
            p_burst     <= HBURST_SINGLE;
            p_count     <= 5'd0;
            rbuf_ok     <= 1'b0;
            rd_pend     <= 1'b0;
            rd_wait     <= 1'b0;
            wmask       <= '0;
            wbuf_valid  <= 1'b0;
            wbuf_open   <= 1'b0;
            wr_wait     <= 1'b0;
            error_first <= 1'b0;
            rd_done     <= 1'b0;
            t_record    <= 1'b0;
            t_index     <= '0;
            t_armed     <= 1'b0;
            t_frozen    <= 1'b0;
            first_error_addr <= '0;
            reads       <= '0;
            writes      <= '0;
            latency_sum <= '0;
            latency_max <= '0;
            buffer_hits <= '0;
            errors      <= '0;
        end
    end

endmodule
