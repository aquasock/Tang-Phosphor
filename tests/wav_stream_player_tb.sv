`timescale 1ns/1ps

module wav_stream_player_tb;

logic clk = 1'b0;
logic resetn = 1'b0;
logic stream_start = 1'b0;
logic stream_end = 1'b0;
logic stream_cancel = 1'b0;
logic [15:0] stream_id = 0;
logic [7:0] stream_data = 0;
logic stream_valid = 1'b0;
logic stream_ready;
logic sample_tick = 1'b0;
logic paused = 1'b0;
logic [15:0] audio_left;
logic [15:0] audio_right;
logic playback_active;
logic [3:0] player_state;
logic format_valid;
logic [31:0] sample_rate;
logic [3:0] fifo_level;
logic [31:0] samples_played;
logic [35:0] total_samples;
logic [31:0] elapsed_seconds;
logic [31:0] duration_seconds;
logic [31:0] underrun_count;
logic [7:0] error_code;
logic [2:0] detected_format;
logic playback_rate_valid;
logic [31:0] playback_rate;
logic [15:0] audible_stream_id;
logic [31:0] boundary_count;
logic [31:0] boundary_gap_samples;
logic [7:0] flac_bytes [0:262143];
integer flac_size;
logic [7:0] flac_bytes_b [0:262143];
integer flac_size_b;
logic [7:0] raw_a [0:262143];
logic [7:0] raw_b [0:262143];
integer raw_size_a;
integer raw_size_b;
integer gap_before;
string vector_dir;

always #5 clk = ~clk;

wav_stream_player #(
    .FIFO_ADDRESS_WIDTH(3),
    .PREFILL_SAMPLES(4)
) dut (
    .clk(clk), .resetn(resetn),
    .stream_start(stream_start), .stream_end(stream_end),
    .stream_cancel(stream_cancel), .stream_id(stream_id),
    .stream_data(stream_data),
    .stream_valid(stream_valid), .stream_ready(stream_ready),
    .sample_tick(sample_tick), .paused(paused), .audio_left(audio_left),
    .audio_right(audio_right), .playback_active(playback_active),
    .player_state(player_state), .format_valid(format_valid),
    .sample_rate(sample_rate), .fifo_level(fifo_level),
    .samples_played(samples_played), .total_samples(total_samples),
    .elapsed_seconds(elapsed_seconds), .duration_seconds(duration_seconds),
    .underrun_count(underrun_count),
    .error_code(error_code), .detected_format(detected_format),
    .playback_rate_valid(playback_rate_valid), .playback_rate(playback_rate),
    .audible_stream_id(audible_stream_id), .boundary_count(boundary_count),
    .boundary_gap_samples(boundary_gap_samples)
);

task automatic pulse_start;
begin
    @(negedge clk);
    stream_start = 1'b1;
    @(negedge clk);
    stream_start = 1'b0;
end
endtask

task automatic pulse_end;
begin
    while (!stream_ready)
        @(posedge clk);
    @(negedge clk);
    stream_end = 1'b1;
    @(negedge clk);
    stream_end = 1'b0;
end
endtask

task automatic pulse_cancel;
begin
    @(negedge clk);
    stream_cancel = 1'b1;
    @(negedge clk);
    stream_cancel = 1'b0;
end
endtask

task automatic pulse_end_unconditional;
begin
    @(negedge clk);
    stream_end = 1'b1;
    @(negedge clk);
    stream_end = 1'b0;
end
endtask

task automatic send_byte(input logic [7:0] value);
begin
    @(negedge clk);
    stream_data = value;
    stream_valid = 1'b1;
    while (!stream_ready)
        @(negedge clk);
    @(negedge clk);
    stream_valid = 1'b0;
end
endtask

task automatic load_flac(input string path);
    integer descriptor;
begin
    descriptor = $fopen(path, "rb");
    if (descriptor == 0)
        $fatal(1, "cannot open %s", path);
    flac_size = $fread(flac_bytes, descriptor);
    $fclose(descriptor);
end
endtask

task automatic load_file(input string path, output logic [7:0] bytes [0:262143],
                        output integer size);
    integer descriptor;
begin
    descriptor = $fopen(path, "rb");
    if (descriptor == 0)
        $fatal(1, "cannot open %s", path);
    size = $fread(bytes, descriptor);
    $fclose(descriptor);
end
endtask

task automatic send_wav_ramp(input logic [31:0] rate, input integer count,
                             input logic [15:0] left_base,
                             input logic [15:0] right_base);
begin
    send_wave_header(rate, count);
    for (integer i = 0; i < count; i++) begin
        send_u16_le(16'(left_base + i));
        send_u16_le(16'(right_base + i));
    end
end
endtask

task automatic start_session(input logic [15:0] id);
begin
    @(negedge clk);
    stream_id = id;
    pulse_start();
end
endtask

task automatic send_loaded_flac;
begin
    for (integer i = 0; i < flac_size; i = i + 1)
        send_byte(flac_bytes[i]);
    pulse_end_unconditional();
end
endtask

task automatic send_fourcc(
    input logic [7:0] a,
    input logic [7:0] b,
    input logic [7:0] c,
    input logic [7:0] d
);
begin
    send_byte(a); send_byte(b); send_byte(c); send_byte(d);
end
endtask

task automatic send_u16_le(input logic [15:0] value);
begin
    send_byte(value[7:0]); send_byte(value[15:8]);
end
endtask

task automatic send_u32_le(input logic [31:0] value);
begin
    send_byte(value[7:0]); send_byte(value[15:8]);
    send_byte(value[23:16]); send_byte(value[31:24]);
end
endtask

task automatic send_wave_header(input logic [31:0] rate, input integer sample_count);
begin
    send_fourcc("R", "I", "F", "F");
    send_u32_le(32'd128);
    send_fourcc("W", "A", "V", "E");

    // Exercise an unknown odd-sized chunk and its mandatory pad byte.
    send_fourcc("J", "U", "N", "K");
    send_u32_le(32'd1);
    send_byte(8'ha5);
    send_byte(8'h00);

    send_fourcc("f", "m", "t", " ");
    send_u32_le(32'd16);
    send_u16_le(16'd1);
    send_u16_le(16'd2);
    send_u32_le(rate);
    send_u32_le(rate * 4);
    send_u16_le(16'd4);
    send_u16_le(16'd16);

    send_fourcc("d", "a", "t", "a");
    send_u32_le(sample_count * 4);
end
endtask

task automatic pulse_sample;
begin
    @(negedge clk);
    sample_tick = 1'b1;
    @(negedge clk);
    sample_tick = 1'b0;
    #1;
end
endtask

initial begin
    if (!$value$plusargs("VECTOR_DIR=%s", vector_dir))
        $fatal(1, "VECTOR_DIR plusarg is required");

    repeat (4) @(posedge clk);
    resetn = 1'b1;

    // A twelve-sample file exceeds the eight-entry test FIFO. Slow sample
    // consumption and the producer's ready wait jointly exercise backpressure.
    pulse_start();
    fork
        begin : valid_producer
            send_wave_header(32'd48000, 12);
            for (integer i = 0; i < 12; i++) begin
                send_u16_le(16'(16'h1000 + i));
                send_u16_le(16'(16'h9000 + i));
            end
            // Bytes after the data chunk must drain without creating PCM.
            send_fourcc("T", "A", "I", "L");
            pulse_end();
        end
        begin : valid_consumer
            wait (playback_active);
            paused = 1'b1;
            begin
                logic [3:0] held_level;
                logic [31:0] held_samples;
                held_level = fifo_level;
                held_samples = samples_played;
                pulse_sample();
                if (audio_left !== 0 || audio_right !== 0 ||
                        fifo_level !== held_level || samples_played !== held_samples ||
                        underrun_count !== 0)
                    $fatal(1, "pause did not hold PCM consumption silently");
            end
            paused = 1'b0;
            for (integer i = 0; i < 12; i++) begin
                repeat (8) @(posedge clk);
                pulse_sample();
                if (audio_left !== 16'(16'h1000 + i) ||
                        audio_right !== 16'(16'h9000 + i))
                    $fatal(1, "PCM sample %0d was %h/%h", i, audio_left, audio_right);
            end
            if (!playback_active)
                $fatal(1, "playback dropped before the final sample interval");
            pulse_sample();
        end
    join

    repeat (4) @(posedge clk);
    if (player_state !== 4'd4 || playback_active || samples_played !== 12 ||
            underrun_count !== 0 || error_code !== 0 || fifo_level !== 0) begin
        $display("valid status state=%0d active=%0b played=%0d underruns=%0d error=%0d level=%0d",
            player_state, playback_active, samples_played, underrun_count, error_code, fifo_level);
        $fatal(1, "valid WAV did not finish cleanly");
    end
    if (!format_valid || sample_rate !== 48000 || detected_format !== 3'd1)
        $fatal(1, "valid WAV metadata was not retained");

    // Duration comes from the exact container sample count through the
    // sequential divider, independent of playback progress.
    pulse_start();
    send_wave_header(32'd48000, 96000);
    wait (format_valid);
    // One further cycle publishes the decoder-side metadata as audible.
    repeat (48) @(posedge clk);
    if (total_samples !== 96000 || duration_seconds !== 2)
        $fatal(1, "exact duration metadata was %0d samples / %0d seconds",
            total_samples, duration_seconds);
    pulse_cancel();

    // Once playback has started, an empty FIFO must produce a counted silent
    // sample and then recover without losing the next decoded PCM pair.
    pulse_start();
    fork
        begin : underrun_producer
            send_wave_header(32'd48000, 6);
            for (integer i = 0; i < 4; i++) begin
                send_u16_le(16'(16'h2000 + i));
                send_u16_le(16'(16'ha000 + i));
            end
            wait (underrun_count == 1);
            for (integer i = 4; i < 6; i++) begin
                send_u16_le(16'(16'h2000 + i));
                send_u16_le(16'(16'ha000 + i));
            end
            pulse_end();
        end
        begin : underrun_consumer
            wait (playback_active);
            for (integer i = 0; i < 4; i++) begin
                pulse_sample();
                if (audio_left !== 16'(16'h2000 + i) ||
                        audio_right !== 16'(16'ha000 + i))
                    $fatal(1, "pre-underrun PCM sample %0d was incorrect", i);
            end
            pulse_sample();
            if (audio_left !== 0 || audio_right !== 0 || underrun_count !== 1)
                $fatal(1, "FIFO underrun did not emit and count silence");
            wait (fifo_level >= 2);
            for (integer i = 4; i < 6; i++) begin
                pulse_sample();
                if (audio_left !== 16'(16'h2000 + i) ||
                        audio_right !== 16'(16'ha000 + i))
                    $fatal(1, "post-underrun PCM sample %0d was incorrect", i);
            end
            pulse_sample();
        end
    join
    repeat (2) @(posedge clk);
    if (player_state !== 4'd4 || samples_played !== 6 || underrun_count !== 1)
        $fatal(1, "underrun recovery did not complete cleanly");

    // The native-rate path accepts a short 44.1 kHz file without changing the
    // parser, FIFO, or PCM boundary.
    pulse_start();
    send_wave_header(32'd44100, 1);
    send_u16_le(16'h1234);
    send_u16_le(16'h5678);
    pulse_end();
    wait (playback_active);
    pulse_sample();
    if (audio_left !== 16'h1234 || audio_right !== 16'h5678)
        $fatal(1, "44.1 kHz PCM sample was incorrect");
    pulse_sample();
    repeat (4) @(posedge clk);
    if (player_state !== 4'd4 || error_code !== 0 || playback_active ||
            !format_valid || sample_rate !== 32'd44100 || samples_played !== 1)
        $fatal(1, "44.1 kHz WAV did not complete cleanly");

    // Rates outside the bounded CD-quality WAV profile remain unsupported.
    pulse_start();
    send_wave_header(32'd32000, 1);
    send_u16_le(16'h1234);
    send_u16_le(16'h5678);
    pulse_end();
    repeat (4) @(posedge clk);
    if (player_state !== 4'd5 || error_code !== 8'h02 || playback_active)
        $fatal(1, "unsupported WAV format was not rejected");

    // A stream too short for content classification is explicitly unknown.
    pulse_start();
    send_fourcc("R", "I", "F", "F");
    pulse_end();
    repeat (4) @(posedge clk);
    if (player_state !== 4'd5 || error_code !== 8'h11 || detected_format !== 0)
        $fatal(1, "truncated signature was not reported");

    // A real encoder-generated FLAC passes through detection, frame admission,
    // the shared PCM FIFO, native-rate playback, and the EOF transition.
    load_flac({vector_dir, "/constant44.flac"});
    pulse_start();
    fork
        send_loaded_flac();
        begin : flac_consumer
            wait (playback_active);
            for (integer i = 0; i < 192; i++) begin
                repeat (8) @(posedge clk);
                pulse_sample();
                if (audio_left !== 16'h1234 || audio_right !== -16'sh2345)
                    $fatal(1, "FLAC PCM sample %0d was %h/%h", i,
                        audio_left, audio_right);
            end
            pulse_sample();
        end
    join
    repeat (4) @(posedge clk);
    if (player_state !== 4'd4 || error_code !== 0 ||
            detected_format !== 3'd2 || playback_active || !format_valid ||
            sample_rate !== 32'd44100 || samples_played !== 192)
        $fatal(1, "valid FLAC did not complete cleanly");

    pulse_start();
    send_fourcc("N", "O", "P", "E");
    send_byte(8'h55);
    pulse_end();
    repeat (4) @(posedge clk);
    if (player_state !== 4'd5 || error_code !== 8'h11 ||
            detected_format !== 0 || playback_active)
        $fatal(1, "unknown content was not drained and rejected");

    // Cancellation resets parsing and buffering without reporting corruption.
    pulse_start();
    send_fourcc("R", "I", "F", "F");
    pulse_cancel();
    repeat (2) @(posedge clk);
    if (player_state !== 4'd6 || playback_active || fifo_level !== 0 ||
            format_valid || error_code !== 0 || detected_format !== 0)
        $fatal(1, "cancel did not clear the active playback session");


    // Gapless append: the second session starts while the first session's
    // tail is still queued. Samples continue on consecutive ticks, and the
    // audible identity, length, and clocks switch exactly at the boundary.
    start_session(16'd11);
    fork
        begin : gapless_producer
            send_wav_ramp(32'd48000, 12, 16'h3000, 16'hb000);
            pulse_end();
            wait (player_state == 4'd7);
            if (audible_stream_id !== 16'd11 || boundary_count !== 0)
                $fatal(1, "draining session had the wrong audible identity");
            start_session(16'd12);
            @(posedge clk); #1;
            if (fifo_level == 0 || !playback_active || player_state !== 4'd3)
                $fatal(1, "append start disturbed the playing tail");
            send_wav_ramp(32'd48000, 10, 16'h4000, 16'hc000);
            pulse_end();
        end
        begin : gapless_consumer
            wait (playback_active);
            for (integer i = 0; i < 22; i++) begin
                repeat (64) @(posedge clk);
                pulse_sample();
                if (i < 12 ? (audio_left !== 16'(16'h3000 + i) ||
                                audio_right !== 16'(16'hb000 + i)) :
                             (audio_left !== 16'(16'h4000 + i - 12) ||
                                audio_right !== 16'(16'hc000 + i - 12)))
                    $fatal(1, "gapless sample %0d was %h/%h", i,
                        audio_left, audio_right);
                repeat (2) @(posedge clk);
                if (i < 11 && (audible_stream_id !== 16'd11 ||
                        total_samples !== 12 || samples_played !== i + 1))
                    $fatal(1, "first session identity changed early at %0d", i);
                if (i == 11 && (audible_stream_id !== 16'd12 ||
                        total_samples !== 10 || samples_played !== 0 ||
                        boundary_count !== 1))
                    $fatal(1, "boundary did not switch the audible session");
                if (i > 11 && samples_played !== i - 11)
                    $fatal(1, "appended session clock was %0d at %0d",
                        samples_played, i);
            end
            pulse_sample();
        end
    join
    repeat (4) @(posedge clk);
    if (player_state !== 4'd4 || samples_played !== 10 || underrun_count !== 0 ||
            boundary_count !== 1 || boundary_gap_samples !== 0 || playback_active)
        $fatal(1, "gapless WAV pair did not complete seamlessly");

    // A successor that cannot reach prefill before the boundary waits
    // silently. The inserted silence is counted as boundary gap, not underrun.
    start_session(16'd21);
    fork
        begin : late_producer
            send_wav_ramp(32'd48000, 6, 16'h5000, 16'hd000);
            pulse_end();
            wait (player_state == 4'd7);
            start_session(16'd22);
            wait (player_state == 4'd2);
            send_wav_ramp(32'd48000, 6, 16'h6000, 16'he000);
            pulse_end();
        end
        begin : late_consumer
            integer silent_ticks;
            silent_ticks = 0;
            wait (playback_active);
            for (integer i = 0; i < 6; i++) begin
                repeat (64) @(posedge clk);
                pulse_sample();
                if (audio_left !== 16'(16'h5000 + i))
                    $fatal(1, "late-boundary first sample %0d was incorrect", i);
            end
            // Tick through the silent wait; the first non-zero output must be
            // the successor's first sample.
            do begin
                repeat (16) @(posedge clk);
                pulse_sample();
                if (audio_left === 0 && audio_right === 0)
                    silent_ticks++;
            end while (audio_left === 0 && audio_right === 0);
            for (integer i = 0; i < 6; i++) begin
                if (i != 0) begin
                    repeat (64) @(posedge clk);
                    pulse_sample();
                end
                if (audio_left !== 16'(16'h6000 + i) ||
                        audio_right !== 16'(16'he000 + i))
                    $fatal(1, "late-boundary second sample %0d was incorrect", i);
            end
            pulse_sample();
            if (silent_ticks == 0 || boundary_gap_samples !== silent_ticks)
                $fatal(1, "boundary gap counted %0d of %0d silent ticks",
                    boundary_gap_samples, silent_ticks);
        end
    join
    repeat (4) @(posedge clk);
    if (player_state !== 4'd4 || samples_played !== 6 || underrun_count !== 0 ||
            boundary_count !== 2 || audible_stream_id !== 16'd22)
        $fatal(1, "late gapless boundary did not recover cleanly");

    // A different-rate successor is decoded early, but the HDMI-facing rate
    // stays with the audible session until its final sample is presented.
    gap_before = boundary_gap_samples;
    start_session(16'd31);
    fork
        begin : rate_producer
            send_wav_ramp(32'd48000, 8, 16'h7000, 16'hf000);
            pulse_end();
            wait (player_state == 4'd7);
            start_session(16'd32);
            send_wav_ramp(32'd44100, 3, 16'h0100, 16'h0200);
            pulse_end();
        end
        begin : rate_consumer
            wait (playback_active);
            wait (format_valid && sample_rate == 32'd44100);
            repeat (2) @(posedge clk);
            if (!playback_rate_valid || playback_rate !== 32'd48000 ||
                    audible_stream_id !== 16'd31)
                $fatal(1, "successor rate became audible before the boundary");
            while (audible_stream_id != 16'd32) begin
                repeat (64) @(posedge clk);
                pulse_sample();
                repeat (2) @(posedge clk);
            end
            if (audio_left !== 16'h7007 || playback_rate !== 32'd44100)
                $fatal(1, "rate did not switch at the final predecessor sample");
            for (integer i = 0; i < 3; i++) begin
                repeat (64) @(posedge clk);
                pulse_sample();
                if (audio_left !== 16'(16'h0100 + i))
                    $fatal(1, "44.1 kHz successor sample %0d was incorrect", i);
            end
            pulse_sample();
        end
    join
    repeat (4) @(posedge clk);
    if (player_state !== 4'd4 || boundary_gap_samples !== gap_before ||
            boundary_count !== 3)
        $fatal(1, "cross-rate boundary did not complete seamlessly");

    // A START on the same edge that presents the predecessor's final sample
    // crosses the boundary at once; the successor then prefills silently.
    start_session(16'd61);
    send_wav_ramp(32'd48000, 1, 16'h0a00, 16'h0b00);
    pulse_end();
    wait (player_state == 4'd7 && fifo_level == 1);
    gap_before = boundary_gap_samples;
    @(negedge clk);
    stream_id = 16'd62;
    stream_start = 1'b1;
    sample_tick = 1'b1;
    @(negedge clk);
    stream_start = 1'b0;
    sample_tick = 1'b0;
    #1;
    if (audio_left !== 16'h0a00 || boundary_count !== 4 || player_state !== 4'd2 ||
            !playback_active)
        $fatal(1, "same-edge append did not cross the boundary");
    repeat (2) @(posedge clk);
    if (audible_stream_id !== 16'd62 || samples_played !== 0)
        $fatal(1, "same-edge append did not publish the successor");
    fork
        begin
            send_wav_ramp(32'd48000, 4, 16'h0c00, 16'h0d00);
            pulse_end();
        end
        begin
            integer silent_ticks;
            silent_ticks = 0;
            do begin
                repeat (16) @(posedge clk);
                pulse_sample();
                if (audio_left === 0 && audio_right === 0)
                    silent_ticks++;
            end while (audio_left === 0 && audio_right === 0);
            for (integer i = 0; i < 4; i++) begin
                if (i != 0) begin
                    repeat (16) @(posedge clk);
                    pulse_sample();
                end
                if (audio_left !== 16'(16'h0c00 + i))
                    $fatal(1, "same-edge successor sample %0d was incorrect", i);
            end
            pulse_sample();
            if (boundary_gap_samples !== gap_before + silent_ticks)
                $fatal(1, "same-edge boundary gap was not counted");
        end
    join
    repeat (4) @(posedge clk);
    if (player_state !== 4'd4 || samples_played !== 4 || underrun_count !== 0)
        $fatal(1, "same-edge successor did not complete");
    gap_before = boundary_gap_samples;

    // Cancelling while a successor is queued flushes both sessions.
    start_session(16'd41);
    send_wav_ramp(32'd48000, 8, 16'h1100, 16'h2200);
    pulse_end();
    wait (player_state == 4'd7);
    start_session(16'd42);
    send_wave_header(32'd48000, 8);
    pulse_cancel();
    repeat (2) @(posedge clk);
    if (player_state !== 4'd6 || playback_active || fifo_level !== 0 ||
            format_valid)
        $fatal(1, "cancel did not flush a queued gapless successor");

    // Real FLAC streams split mid-frame reproduce the continuous source.
    load_file({vector_dir, "/gapless_a44.flac"}, flac_bytes, flac_size);
    load_file({vector_dir, "/gapless_b44.flac"}, flac_bytes_b, flac_size_b);
    load_file({vector_dir, "/gapless_a44.raw"}, raw_a, raw_size_a);
    load_file({vector_dir, "/gapless_b44.raw"}, raw_b, raw_size_b);
    start_session(16'd51);
    fork
        begin : flac_gapless_producer
            for (integer i = 0; i < flac_size; i++)
                send_byte(flac_bytes[i]);
            pulse_end_unconditional();
            wait (player_state == 4'd7);
            start_session(16'd52);
            for (integer i = 0; i < flac_size_b; i++)
                send_byte(flac_bytes_b[i]);
            pulse_end_unconditional();
        end
        begin : flac_gapless_consumer
            integer count_a;
            integer count_b;
            logic [15:0] expected_left;
            logic [15:0] expected_right;
            count_a = raw_size_a / 4;
            count_b = raw_size_b / 4;
            wait (playback_active);
            for (integer i = 0; i < count_a + count_b; i++) begin
                // The eight-entry test FIFO holds far less lead than the
                // hardware FIFO, so consume slowly while the successor starts.
                if (player_state == 4'd7 || dut.boundary_pending)
                    repeat (4096) @(posedge clk);
                else
                    repeat (64) @(posedge clk);
                pulse_sample();
                if (i < count_a) begin
                    expected_left = {raw_a[4 * i + 1], raw_a[4 * i]};
                    expected_right = {raw_a[4 * i + 3], raw_a[4 * i + 2]};
                end else begin
                    expected_left = {raw_b[4 * (i - count_a) + 1],
                                     raw_b[4 * (i - count_a)]};
                    expected_right = {raw_b[4 * (i - count_a) + 3],
                                      raw_b[4 * (i - count_a) + 2]};
                end
                if (audio_left !== expected_left || audio_right !== expected_right)
                    $fatal(1, "gapless FLAC sample %0d was %h/%h, expected %h/%h",
                        i, audio_left, audio_right, expected_left, expected_right);
            end
            pulse_sample();
        end
    join
    repeat (4) @(posedge clk);
    if (player_state !== 4'd4 || underrun_count !== 0 || boundary_count !== 5 ||
            boundary_gap_samples !== gap_before ||
            samples_played !== raw_size_b / 4 || audible_stream_id !== 16'd52)
        $fatal(1, "gapless FLAC pair did not complete seamlessly");

    $display("PASS detected WAV/FLAC playback, prefix replay, unknown rejection, EOF, cancellation, and gapless append");
    $finish;
end

initial begin
    #20_000_000;
    $fatal(1, "FAIL WAV stream player timeout");
end

endmodule
