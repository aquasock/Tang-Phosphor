`timescale 1ns/1ps
// Decode the physical I2S pins and compare every frame with HDMI's delivered
// pair. Unique samples also detect losses, repeats and mixed stereo channels.
module i2s_playback_tb;
    logic clk = 0;
    always #6.734007 clk = ~clk;
    logic resetn = 0, requested_48k = 1;
    wire pll_reset, active_48k, running, ready;
    wire [6:0] mdsel, odsel;
    wire [2:0] mdfrac, odfrac;
    logic [1:0] locked = 0;
    logic force_lock_loss = 0;
    integer lock_count = 0;
    always @(posedge clk) begin
        if (!resetn || pll_reset) begin
            locked <= {resetn, 1'b0};
            lock_count <= 0;
        end else if (force_lock_loss) locked <= 2'b01;
        else if (lock_count >= 20) locked <= 2'b11;
        else lock_count <= lock_count + 1;
    end
    i2s_clock_control #(.SETTLE_CYCLES(74_250)) control (
        .clk(clk), .resetn(resetn), .requested_48k(requested_48k),
        .pll_locked(locked), .pll_reset(pll_reset),
        .mdsel(mdsel), .mdsel_frac(mdfrac), .odsel(odsel), .odsel_frac(odfrac),
        .active_48k(active_48k), .running(running), .ready(ready)
    );
    logic mclk = 0;
    // Vendor PLLs are not simulated: model each requested physical frequency.
    // Their actual output is separately measured by the hardware clock probe.
    initial forever begin
        #(active_48k ? 40.690104 : 44.288549);
        if (pll_reset) mclk = 0;
        else mclk = ~mclk;
    end

    logic start = 0, cancel = 0, finish_stream = 0, paused = 0;
    logic [7:0] data = 0;
    logic valid = 0;
    wire stream_ready, pcm_valid, sample_tick;
    always @(posedge clk) begin
        if (!ready && sample_tick) $fatal(1, "FIFO popped before clock settling");
    end
    wire [15:0] pcm_left, pcm_right;
    wire [31:0] samples, underruns;
    pcm_sink #(.FIFO_ADDRESS_WIDTH(4)) sink (
        .clk(clk), .resetn(resetn), .stream_start(start), .stream_end(finish_stream),
        .stream_cancel(cancel), .stream_id(16'd1), .stream_data(data),
        .stream_valid(valid), .stream_ready(stream_ready),
        .play_rate(requested_48k ? 32'd48000 : 32'd44100),
        .sample_tick(sample_tick), .paused(paused), .audio_left(pcm_left),
        .audio_right(pcm_right), .audio_valid(pcm_valid),
        .samples_played(samples), .underrun_count(underruns),
        .playback_active(), .player_state(), .format_valid(), .sample_rate(),
        .fifo_level(), .total_samples(), .elapsed_seconds(), .duration_seconds(),
        .error_code(), .detected_format(), .playback_rate_valid(), .playback_rate(),
        .audible_stream_id(), .boundary_count(), .boundary_gap_samples()
    );
    wire clk_audio, emitted_present;
    wire [31:0] visual_drops, visual_status, visual_sweeps;
    logic zero_test=0; integer tagged_zeros=0;
    wire [15:0] hdmi_left, hdmi_right;
    wire [7:0] lane_o, lane_oe;
    i2s_playback bridge (
        .clk_pixel(clk), .clk_mclk(mclk), .resetn(resetn),
        .running(running), .ready(ready), .flush(start || cancel),
        .paused(paused), .pcm_valid(pcm_valid), .pcm_left(pcm_left), .pcm_right(pcm_right),
        .sample_tick(sample_tick), .clk_audio(clk_audio), .sample_present(emitted_present),
        .hdmi_left(hdmi_left), .hdmi_right(hdmi_right), .lane_o(lane_o), .lane_oe(lane_oe)
    );
    // The observer runs alongside the physical output checks; its FIFO and
    // drawing workload have no path back into PCM consumption.
    scope_xy observer (
        .clk(clk), .resetn(resetn), .control(4'hb), .flush(start || cancel || !ready),
        .audio_tick(clk_audio), .audio_present(emitted_present),
        .audio_left(hdmi_left), .audio_right(hdmi_right), .cx(11'd0), .cy(10'd0),
        .enabled(), .rgb(), .dropped(visual_drops), .status(visual_status), .sweeps(visual_sweeps)
    );
    integer received = 0, frames = 0, base_value = 16'h8000;
    wire acr_wrap;
    wire [23:0] acr_header;
    wire [55:0] acr_sub [3:0];
    audio_clock_regeneration_packet acr (
        .clk_pixel(clk), .clk_audio(clk_audio), .audio_rate_48k(active_48k),
        .reset(!resetn), .clk_audio_counter_wrap(acr_wrap),
        .header(acr_header), .sub(acr_sub)
    );
    integer acr_checks_44 = 0, acr_checks_48 = 0, wraps_since_restart = 0;
    logic old_wrap = 0, old_rate = 1;
    always @(posedge clk) begin
        if (!running || active_48k != old_rate) wraps_since_restart = 0;
        else if (acr_wrap != old_wrap) begin
            // The first interval includes PLL reset/settling time. Subsequent
            // packets must measure the actual I2S-owned native cadence.
            if (wraps_since_restart >= 1) begin
                integer cts, n;
                cts = {acr_sub[0][11:8], acr_sub[0][23:16], acr_sub[0][31:24]};
                n = {acr_sub[0][35:32], acr_sub[0][47:40], acr_sub[0][55:48]};
                if (n != (active_48k ? 6144 : 6272) ||
                    cts < (active_48k ? 74248 : 82498) ||
                    cts > (active_48k ? 74252 : 82502))
                    $fatal(1, "I2S-driven HDMI ACR mismatch: N=%0d CTS=%0d", n, cts);
                if (active_48k) acr_checks_48++;
                else acr_checks_44++;
            end
            wraps_since_restart++;
        end
        old_wrap = acr_wrap;
        old_rate = active_48k;
    end
    logic [31:0] hdmi_pair = 0;
    always @(posedge clk_audio) begin
        hdmi_pair = {hdmi_right, hdmi_left};
        if (!zero_test && emitted_present != (hdmi_pair!=0))
            $fatal(1,"emitted sample tag mismatches actual PCM/synthetic silence");
        if (zero_test && emitted_present && hdmi_pair==0) tagged_zeros++;
    end
    integer slot = -1;
    logic last_lrck = 0;
    logic [31:0] left_word = 0, right_word = 0;
    time last_frame_time = 0;
    always @(negedge running) begin
        slot = -1;
        last_lrck = 0;
        left_word = 0;
        right_word = 0;
        hdmi_pair = 0;
        last_frame_time = 0;
    end
    always @(posedge lane_o[2]) begin
        if (lane_o[1] != last_lrck) begin
            if (slot != 31) $fatal(1, "bad channel length");
            slot = 0;
        end else slot++;
        last_lrck = lane_o[1];
        if (slot > 31) $fatal(1, "bad LRCK framing");
        if (!lane_o[1]) left_word = {left_word[30:0], lane_o[3]};
        else right_word = {right_word[30:0], lane_o[3]};
        if (lane_o[1] && slot == 31) begin
            if (left_word !== {1'b0, hdmi_pair[15:0], 15'b0} ||
                right_word !== {1'b0, hdmi_pair[31:16], 15'b0})
                $fatal(1, "HDMI/I2S mismatch: I2S L=%h R=%h HDMI=%h",
                       left_word, right_word, hdmi_pair);
            if (last_frame_time != 0 &&
                (active_48k ? ($time-last_frame_time < 20830 || $time-last_frame_time > 20837)
                            : ($time-last_frame_time < 22672 || $time-last_frame_time > 22680)))
                $fatal(1, "wrong native frame cadence");
            last_frame_time = $time;
            frames++;
            if (left_word != 0) begin
                if (left_word[30:15] !== 16'(base_value + received) ||
                    right_word[30:15] !== 16'(16'h7000 + received * 7))
                    $fatal(1, "sample %0d skipped/repeated/mixed: L=%h R=%h",
                           received, left_word[30:15], right_word[30:15]);
                received++;
            end
        end
    end

    task automatic byte_send(input logic [7:0] value);
        @(negedge clk); data = value; valid = 1;
        do @(posedge clk); while (!stream_ready);
        @(negedge clk); valid = 0;
    endtask
    task automatic track(input logic rate, input integer n, input integer base);
        logic [15:0] l, r;
        @(negedge clk);
        received = 0; base_value = base; requested_48k = rate;
        start = 1; finish_stream = 0;
        @(negedge clk); start = 0;
        for (integer i = 0; i < n; i++) begin
            l = 16'(base+i); r = 16'(16'h7000+i*7);
            byte_send(l[7:0]); byte_send(l[15:8]);
            byte_send(r[7:0]); byte_send(r[15:8]);
        end
        repeat (5) @(negedge clk);
        finish_stream = 1;
        @(negedge clk); finish_stream = 0;
        wait (received == n);
        repeat (800) @(negedge mclk);
        if (samples != n || pcm_valid) $fatal(1, "track drain/count mismatch");
        if (!ready || active_48k != rate) $fatal(1, "rate did not settle");
        if (rate && {mdsel,mdfrac,odsel,odfrac} != {7'd96,3'd7,7'd66,3'd3})
            $fatal(1, "wrong 48k divider encoding");
        if (!rate && {mdsel,mdfrac,odsel,odfrac} != {7'd92,3'd1,7'd50,3'd6})
            $fatal(1, "wrong 44.1k divider encoding");
    endtask
    initial begin
        repeat (5) @(negedge clk); resetn = 1;
        fork
            track(0,96,16'h8000);
            begin
                wait (received == 12);
                @(negedge clk); paused = 1;
                repeat (1000) @(negedge mclk);
                begin
                    integer held_samples = samples;
                    repeat (2000) @(negedge mclk);
                    if (samples != held_samples) $fatal(1, "FIFO popped during pause");
                    if (hdmi_pair != 0) $fatal(1, "pause is not silent");
                end
                @(negedge clk); paused = 0;
            end
        join
        track(1,80,16'h9000);
        track(0,80,16'ha000);
        // Cancel with queued and prefetched nonzero data, then refill a new
        // session at the same rate. Stale prefetched data must not survive.
        @(negedge clk);
        received = 0; base_value = 16'hb000; start = 1;
        @(negedge clk); start = 0;
        for (integer i = 0; i < 8; i++) begin
            byte_send(8'(16'hb000+i)); byte_send(8'((16'hb000+i)>>8));
            byte_send(8'(16'h7000+i*7)); byte_send(8'((16'h7000+i*7)>>8));
        end
        wait (received == 1);
        @(negedge clk); cancel = 1;
        @(negedge clk); cancel = 0;
        repeat (5000) @(negedge mclk);
        if (hdmi_pair != 0) $fatal(1, "cancel is not silent");
        track(0,32,16'hc000);
        force_lock_loss = 1;
        wait (!running);
        repeat (100) @(negedge clk);
        if (ready || hdmi_pair != 0) $fatal(1, "lock loss did not mute");
        force_lock_loss = 0;
        wait (ready);
        repeat (1000) @(negedge mclk);
        if (hdmi_pair != 0) $fatal(1, "lock recovery replayed old data");
        // Genuine zero PCM must retain presence; pause/idle zero frames did
        // not. The observer can distinguish them without altering audio.
        zero_test=1;
        @(negedge clk); start=1;
        @(negedge clk); start=0;
        for(integer i=0;i<32;i++) byte_send(0);
        @(negedge clk); finish_stream=1;
        @(negedge clk); finish_stream=0;
        wait(samples==8);
        repeat(1000) @(negedge mclk);
        if(tagged_zeros!=8) $fatal(1,"genuine zero sample presence: %0d",tagged_zeros);
        if (frames < 256) $fatal(1, "insufficient frame coverage");
        if (acr_checks_44 < 2 || acr_checks_48 < 1) $fatal(1, "insufficient ACR coverage");
        $display("PASS i2s_playback: coherent PCM on both outputs, HDMI ACR, pause, cancellation, lock recovery and native rates both ways");
        $finish;
    end
    initial begin
        #30000000;
        $fatal(1, "playback timeout: samples=%0d received=%0d ready=%b",samples,received,ready);
    end
endmodule
