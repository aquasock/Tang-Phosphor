// SPDX-License-Identifier: GPL-3.0-only
//
// ae350_play_stream across unrelated clocks: random sessions of word and
// byte entries with start, end, and cancel, against a player that stalls
// ready at random.  Checks byte order, that every byte of a session arrives
// between its start and end pulses, and the session count.
`timescale 1ns/1ps

module ae350_play_stream_tb;

    logic wclk = 1'b0;
    logic clk = 1'b0;
    always #5 wclk = !wclk;        // 100 MHz AE350 bus
    always #6.734 clk = !clk;      // 74.25 MHz player

    logic        rst = 1'b1;
    logic        wvalid = 1'b0;
    logic [1:0]  wkind = '0, wcount = '0;
    logic [31:0] wdata = '0;
    logic        wready;
    logic        start, stop, cancel, valid, ready;
    logic [7:0]  data;
    logic [15:0] stream_id;

    ae350_play_stream dut (
        .wclk(wclk), .wvalid(wvalid), .wkind(wkind), .wcount(wcount),
        .wdata(wdata), .wready(wready), .clk(clk), .rst(rst), .start(start),
        .stop(stop), .cancel(cancel), .data(data), .valid(valid),
        .ready(ready), .stream_id(stream_id)
    );

    int failures = 0;
    logic [8:0] expected [$];   // {marker, byte}: marker 1 = start/end/cancel event
    int sessions = 0;

    task automatic push(input logic [1:0] kind, input logic [1:0] count,
                        input logic [31:0] value);
        @(posedge wclk);
        while (!wready) @(posedge wclk);
        wvalid <= 1'b1;
        wkind  <= kind;
        wcount <= count;
        wdata  <= value;
        @(posedge wclk);
        wvalid <= 1'b0;
        repeat ($urandom % 3) @(posedge wclk);
    endtask

    // Player model.
    always_ff @(posedge clk) begin
        ready <= ($urandom % 4) != 0;
        if (!rst) begin
            if (start || stop || cancel) begin
                logic [8:0] e;
                e = {1'b1, 8'(start ? 1 : stop ? 2 : 3)};
                if (expected.size() == 0 || expected[0] != e) begin
                    $display("FAIL: event %0d unexpected", e[7:0]); failures++;
                end else void'(expected.pop_front());
            end
            if (valid && ready) begin
                if (expected.size() == 0 || expected[0] != {1'b0, data}) begin
                    if (failures < 10) $display("FAIL: byte %h, expected %h", data,
                        expected.size() ? expected[0] : 9'h0);
                    failures++;
                end else void'(expected.pop_front());
            end
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        rst <= 1'b0;
        repeat (4) @(posedge clk);
        for (int s = 0; s < 40; s++) begin
            int words = $urandom % 300;
            bit drop = ($urandom % 5) == 0;
            expected.push_back({1'b1, 8'd1});
            sessions++;
            push(2'd1, 2'd0, 32'd0);
            for (int w = 0; w < words; w++) begin
                logic [31:0] v = $urandom;
                logic [1:0] count = ($urandom % 6) == 0 ? 2'($urandom % 4) : 2'd3;
                for (int b = 0; b <= count; b++)
                    expected.push_back({1'b0, v[8 * b +: 8]});
                push(2'd0, count, v);
            end
            expected.push_back({1'b1, drop ? 8'd3 : 8'd2});
            push(drop ? 2'd3 : 2'd2, 2'd0, 32'd0);
        end
        for (int i = 0; i < 20000 && expected.size() != 0; i++) @(posedge clk);
        if (expected.size() != 0) begin
            $display("FAIL: %0d items never arrived", expected.size()); failures++;
        end
        if (stream_id != 16'(sessions)) begin
            $display("FAIL: stream_id %0d after %0d sessions", stream_id, sessions); failures++;
        end
        $display("ae350_play_stream_tb: %0d sessions", sessions);
        if (failures == 0) $display("PASS");
        else $fatal(1, "ae350_play_stream_tb: %0d failures", failures);
        $finish;
    end

    initial begin
        #20ms;
        $fatal(1, "ae350_play_stream_tb: timeout");
    end

endmodule
