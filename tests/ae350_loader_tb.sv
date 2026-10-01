// SPDX-License-Identifier: GPL-3.0-only
//
// Program-load path of the AE350 + DDR3 image: Tang-Control stream sessions
// (50 MHz) through ae350_stream_loader and async_fifo to ae350_exts_regs,
// drained by an AHB master on an unrelated ~97 MHz clock the way the boot
// ROM does, plus log writes and Tang-Control reads through debug_read_cdc.
// Sessions have lengths that are not whole words, back-to-back sessions
// open before the previous END is queued, and some sessions are cancelled.
`timescale 1ns/1ps

module ae350_loader_tb;

    logic sclk = 1'b0;
    logic cclk = 1'b0;
    always #10 sclk = !sclk;
    always #5.17 cclk = !cclk;

    logic srst = 1'b1;
    logic crst = 1'b1;

    // Stream side.
    logic       start = 1'b0, stop = 1'b0, cancel = 1'b0;
    logic [7:0] data = '0;
    logic       valid = 1'b0;
    logic       ready;
    logic [31:0] sessions, bytes, ends, cancels;
    logic        overflow;

    logic        entry_valid, entry_pop;
    logic [1:0]  entry_tag;
    logic [31:0] entry_data;

    ae350_stream_loader #(.DEPTH_BITS(4)) loader (
        .sclk(sclk), .srst(srst), .start(start), .stop(stop), .cancel(cancel),
        .data(data), .valid(valid), .ready(ready), .sessions(sessions),
        .bytes(bytes), .ends(ends), .cancels(cancels), .overflow(overflow),
        .cclk(cclk), .entry_valid(entry_valid), .entry_tag(entry_tag),
        .entry_data(entry_data), .entry_pop(entry_pop)
    );

    // CPU side.
    logic [31:0] haddr = '0, hwdata = '0, hrdata;
    logic        hsel = 1'b0, hwrite = 1'b0, hready;
    logic [1:0]  htrans = 2'b00;
    logic [2:0]  hsize = 3'd2;
    logic [7:0]  dbg_addr;
    logic [31:0] dbg_rdata;
    logic [31:0] trace_addr [16] = '{default: 32'd0};
    logic [15:0] trace_info [16] = '{default: 16'd0};

    ae350_exts_regs regs (
        .clk(cclk), .rst(crst), .haddr(haddr), .hsel(hsel), .htrans(htrans),
        .hwrite(hwrite), .hsize(hsize), .hwdata(hwdata), .hrdata(hrdata),
        .hready(hready), .entry_valid(entry_valid), .entry_tag(entry_tag),
        .entry_data(entry_data), .entry_pop(entry_pop), .stream_overflow(overflow),
        .bridge_reads(32'd11), .bridge_writes(32'd22), .bridge_latency_sum(32'd33),
        .bridge_latency_max(32'd44), .bridge_buffer_hits(32'd55), .bridge_errors(32'd66),
        .bridge_trace_addr(trace_addr), .bridge_trace_info(trace_info),
        .bridge_trace_status(8'd0), .bridge_first_error(32'd0), .bridge_state(32'd0),
        .dbg_addr(dbg_addr), .dbg_rdata(dbg_rdata)
    );

    logic [7:0]  daddr = '0;
    logic [31:0] drdata;

    debug_read_cdc #(.ADDR_BITS(8), .TARGET_LATENCY(3)) dbg (
        .dclk(sclk), .daddr(daddr), .drdata(drdata),
        .tclk(cclk), .taddr(dbg_addr), .trdata(dbg_rdata)
    );

    int failures = 0;

    // ------------------------------------------------------------------
    // AHB master (one transfer at a time, as the uncached CPU does).
    //
    // The master drives and samples on falling edges and the slave works on
    // rising edges, so no value is ever read in the timestep that writes it.
    // HREADY changes only on rising edges: its value at a falling edge is the
    // one the slave presents at the next rising edge.
    // ------------------------------------------------------------------
    task automatic ahb(input logic write, input logic [31:0] address,
                       input logic [31:0] value, input logic [2:0] size,
                       output logic [31:0] result);
        @(negedge cclk);
        while (!hready) @(negedge cclk);
        haddr  = address;
        hsel   = 1'b1;
        htrans = 2'b10;
        hwrite = write;
        hsize  = size;
        @(negedge cclk);                    // accepted at the rising edge just passed
        htrans = 2'b00;
        hsel   = 1'b0;
        hwdata = value;
        while (!hready) @(negedge cclk);    // completes at the next rising edge
        @(posedge cclk);
        @(negedge cclk);
        result = hrdata;
    endtask

    task automatic ahb_write(input logic [31:0] address, input logic [31:0] value,
                             input logic [2:0] size = 3'd2);
        logic [31:0] unused;
        ahb(1'b1, address, value, size, unused);
    endtask

    task automatic ahb_read(input logic [31:0] address, output logic [31:0] value);
        ahb(1'b0, address, 32'h0, 3'd2, value);
    endtask

    // ------------------------------------------------------------------
    // Stream sessions and the expected entry sequence.
    // ------------------------------------------------------------------
    typedef struct packed { logic [1:0] tag; logic [31:0] data; } entry_t;
    entry_t expected [$];

    // One-cycle event strobe: 0 start, 1 end, 2 cancel.  Stream-side
    // signals are driven on falling edges, like the AHB master below.
    task automatic pulse(input int which);
        @(negedge sclk);
        start  = which == 0;
        stop   = which == 1;
        cancel = which == 2;
        @(negedge sclk);
        start  = 1'b0;
        stop   = 1'b0;
        cancel = 1'b0;
    endtask

    task automatic session(input int length, input int cancel_at);
        logic [31:0] word = '0;
        int taken = 0;
        pulse(0);
        expected.push_back({2'd1, 32'd0});
        while (taken < length && taken != cancel_at) begin
            logic [7:0] b = 8'($urandom);
            @(negedge sclk);
            data  = b;
            valid = 1'b1;
            // READY changes only on rising edges, so its value here is the
            // one at the next rising edge, which takes the byte.
            while (!ready) @(negedge sclk);
            @(negedge sclk);
            valid = 1'b0;
            word[8 * (taken % 4) +: 8] = b;
            taken++;
            if (taken % 4 == 0) begin
                expected.push_back({2'd0, word});
                word = '0;
            end
            if (($urandom % 5) == 0)
                repeat ($urandom % 4) @(posedge sclk);
        end
        if (taken == cancel_at) begin
            pulse(2);
            expected.push_back({2'd3, 32'd0});
        end else begin
            pulse(1);
            if (taken % 4 != 0)
                expected.push_back({2'd0, word});
            expected.push_back({2'd2, 32'(taken)});
        end
    endtask

    // ------------------------------------------------------------------
    // CPU: drain entries as the boot ROM does.
    // ------------------------------------------------------------------
    int received = 0;
    logic stop_cpu = 1'b0;
    logic drain_done = 1'b0;

    task automatic drain();
        logic [31:0] status, value;
        forever begin
            ahb_read(32'he800_0080, status);
            if (status[0]) begin
                entry_t want;
                ahb_read(32'he800_0084, value);
                ahb_write(32'he800_0088, 32'h0);
                if (expected.size() == 0) begin
                    $display("FAIL: unexpected entry %0d %h", status[2:1], value);
                    failures++;
                end else begin
                    want = expected.pop_front();
                    if (want.tag != status[2:1] || want.data != value) begin
                        if (failures < 10)
                            $display("FAIL: entry %0d got tag %0d data %h, expected tag %0d data %h",
                                     received, status[2:1], value, want.tag, want.data);
                        failures++;
                    end
                end
                received++;
            end else if (stop_cpu) begin
                break;
            end
        end
    endtask

    task automatic debug_read(input logic [7:0] word, output logic [31:0] value);
        @(posedge sclk);
        daddr <= word;
        repeat (60) @(posedge sclk);     // about six UART bytes at 2 Mbaud is far longer
        value = drdata;
    endtask

    initial begin
        logic [31:0] value;
        string text = "ae350 log\n";

        repeat (5) @(posedge sclk);
        srst <= 1'b0;
        crst <= 1'b0;

        // Register access and debug reads.
        ahb_write(32'he800_0044, 32'hcafe_f00d);
        ahb_read(32'he800_0000, value);
        if (value != 32'h5450_4133) begin $display("FAIL: magic %h", value); failures++; end
        ahb_read(32'he800_00b4, value);
        if (value != 32'd66) begin $display("FAIL: bridge errors %0d", value); failures++; end
        for (int i = 0; i < text.len(); i++) begin
            ahb_write(32'he800_0100 + i, 32'(8'(text[i])) << (8 * (i % 4)), 3'd0);
        end
        ahb_write(32'he800_0030, text.len());
        debug_read(8'h00, value);
        if (value != 32'h5450_4133) begin $display("FAIL: debug magic %h", value); failures++; end
        debug_read(8'h11, value);
        if (value != 32'hcafe_f00d) begin $display("FAIL: debug user %h", value); failures++; end
        debug_read(8'h0c, value);
        if (value != text.len()) begin $display("FAIL: debug log head %0d", value); failures++; end
        for (int w = 0; w < 3; w++) begin
            debug_read(8'h40 + 8'(w), value);
            for (int b = 0; b < 4 && 4 * w + b < text.len(); b++)
                if (value[8 * b +: 8] != text[4 * w + b]) begin
                    $display("FAIL: log byte %0d got %h", 4 * w + b, value[8 * b +: 8]);
                    failures++;
                end
        end

        // Stream sessions, drained concurrently.  join_none and an explicit
        // completion flag: fork/join aborts in Verilator 5.032's
        // VlForkSync::join for this pair of branches.
        fork
            begin
                drain();
                drain_done = 1'b1;
            end
        join_none
        for (int s = 0; s < 60; s++) begin
            int length = 1 + $urandom % 70;
            session(length, ($urandom % 6) == 0 ? int'($urandom % length) : -1);
        end
        repeat (400) @(posedge sclk);
        stop_cpu = 1'b1;
        wait (drain_done);

        if (expected.size() != 0) begin
            $display("FAIL: %0d entries never arrived", expected.size());
            failures++;
        end
        if (overflow) begin $display("FAIL: overflow"); failures++; end
        $display("ae350_loader_tb: %0d entries, %0d sessions, %0d bytes, %0d ends, %0d cancels",
                 received, sessions, bytes, ends, cancels);
        if (failures == 0)
            $display("PASS");
        else
            $fatal(1, "ae350_loader_tb: %0d failures", failures);
        $finish;
    end

    initial begin
        #20ms;
        $fatal(1, "ae350_loader_tb: timeout");
    end

endmodule
