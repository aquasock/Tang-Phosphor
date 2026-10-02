// Basic check of the raw-PCM sink: rate capture at START, four-byte -> one
// stereo sample assembly, FIFO buffering, and sample_tick output.
`timescale 1ns/1ps

module pcm_sink_tb;

    logic clk = 1'b0;
    always #6.734 clk = !clk;   // 74.25 MHz-ish

    logic resetn = 1'b0;
    logic stream_start = 0, stream_end = 0, stream_cancel = 0;
    logic [15:0] stream_id = 0;
    logic [7:0]  stream_data = 0;
    logic        stream_valid = 0;
    logic        stream_ready;
    logic [31:0] play_rate = 0;
    logic        sample_tick = 0;
    logic        paused = 0;

    logic [15:0] audio_left, audio_right;
    logic        playback_active;
    logic [3:0]  player_state;
    logic        format_valid;
    logic [31:0] sample_rate;
    logic [12:0] fifo_level;
    logic [31:0] samples_played;
    logic [31:0] underrun_count;

    pcm_sink #(.FIFO_ADDRESS_WIDTH(4)) dut (
        .clk(clk), .resetn(resetn),
        .stream_start(stream_start), .stream_end(stream_end),
        .stream_cancel(stream_cancel), .stream_id(stream_id),
        .stream_data(stream_data), .stream_valid(stream_valid),
        .stream_ready(stream_ready), .play_rate(play_rate),
        .sample_tick(sample_tick), .paused(paused),
        .audio_left(audio_left), .audio_right(audio_right),
        .playback_active(playback_active), .player_state(player_state),
        .format_valid(format_valid), .sample_rate(sample_rate),
        .fifo_level(fifo_level), .samples_played(samples_played),
        .underrun_count(underrun_count),
        .total_samples(), .elapsed_seconds(), .duration_seconds(),
        .error_code(), .detected_format(), .playback_rate_valid(),
        .playback_rate(), .audible_stream_id(), .boundary_count(),
        .boundary_gap_samples()
    );

    int failures = 0;

    // Blocking drive: valid high for exactly one clock so the sink samples
    // each byte once (ready is always high here, FIFO depth 16 >> 2 samples).
    task automatic send_byte(input logic [7:0] b);
        stream_data  = b;
        stream_valid = 1'b1;
        @(posedge clk);
        stream_valid = 1'b0;
        @(posedge clk);
    endtask

    task automatic send_sample(input logic [15:0] l, input logic [15:0] r);
        send_byte(l[7:0]);
        send_byte(l[15:8]);
        send_byte(r[7:0]);
        send_byte(r[15:8]);
    endtask

    // Captured outputs, sampled on the pop cycle.
    logic [15:0] got_l [0:1];
    logic [15:0] got_r [0:1];
    int pops = 0;
    always @(posedge clk) begin
        if (sample_tick && !paused && (player_state == 4'd2 || player_state == 4'd1)) begin
            if (pops < 2) begin
                got_l[pops] <= audio_left;
                got_r[pops] <= audio_right;
                pops <= pops + 1;
            end
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        resetn <= 1'b1;
        repeat (2) @(posedge clk);

        play_rate = 32'd44100;
        stream_start = 1'b1;
        @(posedge clk);
        stream_start = 1'b0;
        @(posedge clk);

        if (sample_rate != 32'd44100) begin
            $display("FAIL: rate %0d expected 44100", sample_rate); failures++;
        end

        send_sample(16'h1234, 16'h5678);
        send_sample(16'hABCD, 16'hEF01);

        stream_end = 1'b1;
        @(posedge clk);
        stream_end = 1'b0;

        // Clock samples out (two real, then drain).
        for (int i = 0; i < 4; i++) begin
            sample_tick = 1'b1;
            @(posedge clk);
            sample_tick = 1'b0;
            @(posedge clk);
        end

        if (samples_played != 2) begin
            $display("FAIL: samples_played %0d expected 2", samples_played); failures++;
        end
        if (underrun_count != 0) begin
            $display("FAIL: underruns %0d expected 0", underrun_count); failures++;
        end
        if (got_l[0] != 16'h1234 || got_r[0] != 16'h5678) begin
            $display("FAIL: sample0 %04h/%04h expected 1234/5678", got_l[0], got_r[0]); failures++;
        end
        if (got_l[1] != 16'hABCD || got_r[1] != 16'hEF01) begin
            $display("FAIL: sample1 %04h/%04h expected ABCD/EF01", got_l[1], got_r[1]); failures++;
        end

        // Startup window: a tick between START and the first assembled sample
        // clears no data and must not be counted; a real starvation once
        // playback is underway (no stream end) still must be.
        stream_start = 1'b1;
        @(posedge clk);
        stream_start = 1'b0;
        @(posedge clk);
        sample_tick = 1'b1;      // RECEIVING, FIFO empty: prefill, not underrun
        @(posedge clk);
        sample_tick = 1'b0;
        @(posedge clk);
        if (underrun_count != 0 || samples_played != 0) begin
            $display("FAIL: prefill tick counted (underruns %0d played %0d)",
                     underrun_count, samples_played); failures++;
        end

        send_sample(16'h0011, 16'h0022);
        sample_tick = 1'b1;
        @(posedge clk);
        sample_tick = 1'b0;
        @(posedge clk);
        if (underrun_count != 0 || samples_played != 1) begin
            $display("FAIL: first sample (underruns %0d played %0d)",
                     underrun_count, samples_played); failures++;
        end

        sample_tick = 1'b1;      // FIFO drained, still PLAYING, no end: real
        @(posedge clk);
        sample_tick = 1'b0;
        @(posedge clk);
        if (underrun_count != 1) begin
            $display("FAIL: starvation not counted (underruns %0d)", underrun_count);
            failures++;
        end

        if (failures == 0)
            $display("PASS pcm_sink: rate capture, byte assembly, output, and startup window");
        else
            $fatal(1, "pcm_sink_tb: %0d failures", failures);
        $finish;
    end

    initial begin
        #2ms;
        $display("hang: pops=%0d state=%0d", pops, player_state);
        $fatal(1, "pcm_sink_tb timeout");
    end

endmodule
