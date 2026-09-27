`timescale 1ns/1ps

module hdmi_audio_rate_tb;

logic clk_pixel = 1'b0;
logic reset = 1'b1;
logic requested_rate_48k = 1'b1;
logic clk_audio;
logic sample_tick;
logic [31:0] active_sample_rate;
logic [15:0] tone_samples [1:0];
wire active_rate_48k = active_sample_rate == 32'd48_000;

logic acr_wrap;
logic [23:0] acr_header;
logic [55:0] acr_sub [3:0];

logic [7:0] frame_counter = 8'd25;
logic [3:0] sampling_frequency = 4'b0010;
logic [1:0] valid_bit [3:0] = '{default: 2'b00};
logic [1:0] user_data_bit [3:0] = '{default: 2'b00};
logic [23:0] sample_words [3:0] [1:0] =
    '{default: '{default: 24'd0}};
logic [3:0] sample_present = 4'b1111;
logic [23:0] sample_header;
logic [55:0] sample_sub [3:0];
logic picker_rate_48k = 1'b1;
logic picker_packet_enable = 1'b0;
logic [23:0] picker_header;
logic [55:0] picker_sub [3:0];

always #1 clk_pixel = ~clk_pixel;

audio_test_source timebase (
    .clk_pixel(clk_pixel), .resetn(!reset),
    .rate_48k(requested_rate_48k), .clk_audio(clk_audio),
    .sample_tick(sample_tick), .active_sample_rate(active_sample_rate),
    .audio_sample_word(tone_samples)
);

audio_clock_regeneration_packet acr (
    .clk_pixel(clk_pixel), .clk_audio(clk_audio),
    .audio_rate_48k(active_rate_48k), .reset(reset),
    .clk_audio_counter_wrap(acr_wrap), .header(acr_header), .sub(acr_sub)
);

audio_sample_packet #(.WORD_LENGTH(4'b0010)) sample_packet (
    .frame_counter(frame_counter), .sampling_frequency(sampling_frequency),
    .valid_bit(valid_bit), .user_data_bit(user_data_bit),
    .audio_sample_word(sample_words),
    .audio_sample_word_present(sample_present),
    .header(sample_header), .sub(sample_sub)
);

packet_picker #(.AUDIO_BIT_WIDTH(16)) picker (
    .clk_pixel(clk_pixel), .clk_audio(clk_audio),
    .audio_rate_48k(picker_rate_48k), .reset(reset),
    .video_field_end(1'b0), .packet_enable(picker_packet_enable),
    .packet_pixel_counter(5'd0), .audio_sample_word(tone_samples),
    .header(picker_header), .sub(picker_sub)
);

function automatic logic [19:0] acr_n(input logic [55:0] value);
begin
    acr_n = {value[35:32], value[47:40], value[55:48]};
end
endfunction

function automatic logic [19:0] acr_cts(input logic [55:0] value);
begin
    acr_cts = {value[11:8], value[23:16], value[31:24]};
end
endfunction

task automatic wait_for_acr_event;
    logic previous_wrap;
begin
    previous_wrap = acr_wrap;
    while (acr_wrap == previous_wrap)
        @(posedge clk_pixel);
    #1;
end
endtask

initial begin
    repeat (4) @(posedge clk_pixel);
    reset = 1'b0;

    // Discard the startup partial interval, then verify one complete 48 kHz
    // measurement and the matching IEC 60958 channel-status rate bit.
    wait_for_acr_event();
    wait_for_acr_event();
    if (acr_n(acr_sub[0]) !== 20'd6144 ||
            acr_cts(acr_sub[0]) !== 20'd74_250)
        $fatal(1, "48 kHz ACR was N=%0d CTS=%0d",
            acr_n(acr_sub[0]), acr_cts(acr_sub[0]));
    #1;
    if (sample_sub[0][50] !== 1'b1 || sample_sub[0][54] !== 1'b1)
        $fatal(1, "48 kHz channel-status sampling code was not encoded");

    // Change rate at runtime. The ACR block must suppress any partial old-rate
    // measurement and publish the new N only with a full new-rate CTS interval.
    @(negedge clk_pixel);
    requested_rate_48k = 1'b0;
    picker_rate_48k = 1'b0;
    sampling_frequency = 4'b0000;
    wait (active_sample_rate == 32'd44_100);
    repeat (4) @(posedge clk_pixel);
    #1;
    if (picker.packet_audio_rate_48k !== 1'b1)
        $fatal(1, "packetizer changed rate away from a packet boundary");
    @(negedge clk_pixel);
    picker_packet_enable = 1'b1;
    @(posedge clk_pixel);
    #1;
    picker_packet_enable = 1'b0;
    if (picker.packet_audio_rate_48k !== 1'b0 || picker.packet_type !== 8'd0)
        $fatal(1, "packetizer did not adopt rate cleanly at a packet boundary");
    wait_for_acr_event();
    wait_for_acr_event();
    if (acr_n(acr_sub[0]) !== 20'd6272 ||
            acr_cts(acr_sub[0]) !== 20'd82_500)
        $fatal(1, "44.1 kHz ACR was N=%0d CTS=%0d",
            acr_n(acr_sub[0]), acr_cts(acr_sub[0]));
    #1;
    if (sample_sub[0][50] !== 1'b0 || sample_sub[0][54] !== 1'b0)
        $fatal(1, "44.1 kHz channel-status sampling code was not encoded");

    $display("PASS HDMI audio rate switch: native cadence, ACR N/CTS, and channel status");
    $finish;
end

initial begin
    #10_000_000;
    $fatal(1, "FAIL HDMI audio rate test timeout");
end

endmodule
