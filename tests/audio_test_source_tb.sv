`timescale 1ns/1ps

module audio_test_source_tb;

logic clk_pixel = 1'b0;
logic resetn = 1'b0;
logic clk_audio;
logic sample_tick;
logic [15:0] audio_sample_word [1:0];

audio_test_source dut (
    .clk_pixel(clk_pixel),
    .resetn(resetn),
    .clk_audio(clk_audio),
    .sample_tick(sample_tick),
    .audio_sample_word(audio_sample_word)
);

always #5 clk_pixel = ~clk_pixel;

initial begin
    integer sample_count;
    integer last_sample_cycle;
    integer interval;
    integer restart_cycles;
    logic previous_audio;
    logic [15:0] expected_left;
    logic [15:0] expected_right;

    repeat (4) @(posedge clk_pixel);
    #1;
    if (clk_audio !== 1'b0 || sample_tick !== 1'b0 || audio_sample_word[0] !== 16'b0 ||
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
    if (clk_audio !== 1'b0 || sample_tick !== 1'b0 || audio_sample_word[0] !== 16'b0 ||
            audio_sample_word[1] !== 16'b0)
        $fatal(1, "audio outputs did not clear after restart reset");

    @(negedge clk_pixel);
    resetn = 1'b1;
    previous_audio = 1'b0;
    restart_cycles = 0;
    while (restart_cycles < 800) begin
        @(posedge clk_pixel);
        #1;
        restart_cycles++;
        if (clk_audio && !previous_audio) begin
            if (restart_cycles != 774)
                $fatal(1, "first restarted sample arrived after %0d cycles", restart_cycles);
            if (audio_sample_word[0] !== 16'h2000 ||
                    audio_sample_word[1] !== 16'h2000)
                $fatal(1, "tone phase did not restart deterministically");
            $display("PASS audio source: exact 48 kHz average, deterministic 1/2 kHz stereo tones");
            $finish;
        end
        previous_audio = clk_audio;
    end

    $fatal(1, "timed out waiting for first sample after reset");
end

endmodule
