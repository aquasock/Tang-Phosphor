`timescale 1ns/1ps

module audio_test_source_tb;

logic clk_pixel = 1'b0;
logic resetn = 1'b0;
logic rate_48k = 1'b1;
logic clk_audio;
logic sample_tick;
logic [31:0] active_sample_rate;
logic [15:0] audio_sample_word [1:0];

audio_test_source dut (
    .clk_pixel(clk_pixel),
    .resetn(resetn),
    .rate_48k(rate_48k),
    .clk_audio(clk_audio),
    .sample_tick(sample_tick),
    .active_sample_rate(active_sample_rate),
    .audio_sample_word(audio_sample_word)
);

always #5 clk_pixel = ~clk_pixel;

initial begin
    integer sample_count;
    integer last_sample_cycle;
    integer interval;
    integer restart_cycles;
    integer left_phase_model;
    integer right_phase_model;
    logic previous_audio;
    logic restart_sample_seen;
    logic [15:0] expected_left;
    logic [15:0] expected_right;

    repeat (4) @(posedge clk_pixel);
    #1;
    if (clk_audio !== 1'b0 || sample_tick !== 1'b0 ||
            active_sample_rate !== 32'd48_000 || audio_sample_word[0] !== 16'b0 ||
            audio_sample_word[1] !== 16'b0)
        $fatal(1, "audio outputs are not cleared during reset");

    @(negedge clk_pixel);
    resetn = 1'b1;

    sample_count = 0;
    last_sample_cycle = 0;
    previous_audio = 1'b0;

    // One millisecond at 74.25 MHz must contain exactly 48 sample edges.
    for (integer pixel_cycle = 1; pixel_cycle <= 74_250; pixel_cycle++) begin
        @(posedge clk_pixel);
        #1;

        if ($isunknown({clk_audio, audio_sample_word[0], audio_sample_word[1]}))
            $fatal(1, "unknown audio state at pixel cycle %0d", pixel_cycle);

        if (clk_audio && !previous_audio) begin
            if (!sample_tick)
                $fatal(1, "sample tick missing from audio rising edge");
            sample_count++;

            if (last_sample_cycle != 0) begin
                interval = pixel_cycle - last_sample_cycle;
                if (interval != 1_546 && interval != 1_547)
                    $fatal(1, "unexpected sample interval %0d", interval);
            end
            last_sample_cycle = pixel_cycle;

            expected_left = (((sample_count - 1) / 24) % 2 == 0) ?
                16'h2000 : 16'he000;
            expected_right = (((sample_count - 1) / 12) % 2 == 0) ?
                16'h2000 : 16'he000;

            if (audio_sample_word[0] !== expected_left)
                $fatal(1, "left sample %0d was %h, expected %h",
                    sample_count, audio_sample_word[0], expected_left);
            if (audio_sample_word[1] !== expected_right)
                $fatal(1, "right sample %0d was %h, expected %h",
                    sample_count, audio_sample_word[1], expected_right);
        end
        else if (sample_tick)
            $fatal(1, "sample tick occurred without an audio rising edge");

        previous_audio = clk_audio;
    end

    if (sample_count != 48)
        $fatal(1, "generated %0d samples in 1 ms, expected 48", sample_count);
    if (clk_audio !== 1'b0 || sample_tick !== 1'b0)
        $fatal(1, "audio clock did not complete an integral number of cycles");

    // Reset in flight and require the rate and waveform phases to restart.
    @(negedge clk_pixel);
    resetn = 1'b0;
    @(posedge clk_pixel);
    #1;
    if (clk_audio !== 1'b0 || sample_tick !== 1'b0 ||
            active_sample_rate !== 32'd48_000 || audio_sample_word[0] !== 16'b0 ||
            audio_sample_word[1] !== 16'b0)
        $fatal(1, "audio outputs did not clear after restart reset");

    @(negedge clk_pixel);
    resetn = 1'b1;
    previous_audio = 1'b0;
    restart_cycles = 0;
    restart_sample_seen = 1'b0;
    while (restart_cycles < 800 && !restart_sample_seen) begin
        @(posedge clk_pixel);
        #1;
        restart_cycles++;
        if (clk_audio && !previous_audio) begin
            if (restart_cycles != 774)
                $fatal(1, "first restarted sample arrived after %0d cycles", restart_cycles);
            if (audio_sample_word[0] !== 16'h2000 ||
                    audio_sample_word[1] !== 16'h2000)
                $fatal(1, "tone phase did not restart deterministically");
            restart_sample_seen = 1'b1;
        end
        previous_audio = clk_audio;
    end
    if (!restart_sample_seen)
        $fatal(1, "timed out waiting for first sample after reset");

    // A runtime transition must restart cleanly and produce exactly 441 sample
    // edges in 10 ms, with bounded fractional-clock intervals.
    @(negedge clk_pixel);
    rate_48k = 1'b0;
    @(posedge clk_pixel);
    #1;
    if (active_sample_rate !== 32'd44_100 || clk_audio !== 1'b0 ||
            sample_tick !== 1'b0)
        $fatal(1, "44.1 kHz transition did not restart the timebase");

    sample_count = 0;
    last_sample_cycle = 0;
    previous_audio = 1'b0;
    left_phase_model = 0;
    right_phase_model = 0;
    for (integer pixel_cycle = 1; pixel_cycle <= 742_500; pixel_cycle++) begin
        @(posedge clk_pixel);
        #1;
        if (clk_audio && !previous_audio) begin
            if (!sample_tick)
                $fatal(1, "44.1 kHz sample tick missing");
            sample_count++;
            if (last_sample_cycle != 0) begin
                interval = pixel_cycle - last_sample_cycle;
                if (interval != 1_683 && interval != 1_684)
                    $fatal(1, "unexpected 44.1 kHz sample interval %0d", interval);
            end
            last_sample_cycle = pixel_cycle;

            expected_left = left_phase_model < 22_050 ? 16'h2000 : 16'he000;
            expected_right = right_phase_model < 22_050 ? 16'h2000 : 16'he000;
            if (audio_sample_word[0] !== expected_left ||
                    audio_sample_word[1] !== expected_right)
                $fatal(1, "44.1 kHz tone sample %0d was %h/%h, expected %h/%h",
                    sample_count, audio_sample_word[0], audio_sample_word[1],
                    expected_left, expected_right);

            left_phase_model = (left_phase_model + 1_000) % 44_100;
            right_phase_model = (right_phase_model + 2_000) % 44_100;
        end else if (sample_tick)
            $fatal(1, "44.1 kHz tick occurred without an audio rising edge");
        previous_audio = clk_audio;
    end

    if (sample_count != 441 || clk_audio !== 1'b0 || sample_tick !== 1'b0)
        $fatal(1, "44.1 kHz window ended with %0d samples and clock %0b",
            sample_count, clk_audio);

    $display("PASS audio source: exact native 44.1/48 kHz cadence and deterministic stereo tones");
    $finish;
end

endmodule
