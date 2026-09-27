`timescale 1ns/1ps

module wav_stream_player_tb;

logic clk = 1'b0;
logic resetn = 1'b0;
logic stream_start = 1'b0;
logic stream_end = 1'b0;
logic stream_cancel = 1'b0;
logic [7:0] stream_data = 0;
logic stream_valid = 1'b0;
logic stream_ready;
logic sample_tick = 1'b0;
logic [15:0] audio_left;
logic [15:0] audio_right;
logic playback_active;
logic [3:0] player_state;
logic format_valid;
logic [31:0] sample_rate;
logic [3:0] fifo_level;
logic [31:0] samples_played;
logic [31:0] underrun_count;
logic [7:0] error_code;
logic [2:0] detected_format;
logic [7:0] flac_bytes [0:262143];
integer flac_size;
string vector_dir;

always #5 clk = ~clk;

wav_stream_player #(
    .FIFO_ADDRESS_WIDTH(3),
    .PREFILL_SAMPLES(4)
) dut (
    .clk(clk), .resetn(resetn),
    .stream_start(stream_start), .stream_end(stream_end),
    .stream_cancel(stream_cancel), .stream_data(stream_data),
    .stream_valid(stream_valid), .stream_ready(stream_ready),
    .sample_tick(sample_tick), .audio_left(audio_left),
    .audio_right(audio_right), .playback_active(playback_active),
    .player_state(player_state), .format_valid(format_valid),
    .sample_rate(sample_rate), .fifo_level(fifo_level),
    .samples_played(samples_played), .underrun_count(underrun_count),
    .error_code(error_code), .detected_format(detected_format)
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

    $display("PASS detected WAV/FLAC playback, prefix replay, unknown rejection, EOF, and cancellation");
    $finish;
end

initial begin
    #2_000_000;
    $fatal(1, "FAIL WAV stream player timeout");
end

endmodule
