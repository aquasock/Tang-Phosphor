`timescale 1ns/1ps

module audio_output_policy_tb;

logic clk = 1'b0;
logic resetn = 1'b0;
logic stream_start = 1'b0;
logic format_valid = 1'b0;
logic [31:0] sample_rate = 0;
logic playback_active = 1'b0;
logic [15:0] player_left = 16'h1234;
logic [15:0] player_right = 16'h5678;
logic [15:0] diagnostic_left = 16'h2000;
logic [15:0] diagnostic_right = 16'he000;
logic rate_48k;
logic [15:0] output_left;
logic [15:0] output_right;

audio_output_policy dut (
    .clk(clk), .resetn(resetn), .stream_start(stream_start),
    .format_valid(format_valid), .sample_rate(sample_rate),
    .playback_active(playback_active), .player_left(player_left),
    .player_right(player_right), .diagnostic_left(diagnostic_left),
    .diagnostic_right(diagnostic_right), .rate_48k(rate_48k),
    .output_left(output_left), .output_right(output_right)
);

always #5 clk = ~clk;

task automatic check_output(
    input logic [15:0] expected_left,
    input logic [15:0] expected_right,
    input string message
);
    #1;
    if (output_left !== expected_left || output_right !== expected_right)
        $fatal(1, "%s: output=%h/%h expected=%h/%h", message,
            output_left, output_right, expected_left, expected_right);
endtask

initial begin
    @(posedge clk);
    check_output(16'h0000, 16'h0000, "reset silence");
    if (rate_48k !== 1'b1)
        $fatal(1, "reset rate was not 48 kHz");

    @(negedge clk);
    resetn = 1'b1;
    check_output(16'h2000, 16'he000, "startup diagnostics");

    @(negedge clk);
    sample_rate = 32'd44_100;
    format_valid = 1'b1;
    @(posedge clk);
    #1;
    if (rate_48k !== 1'b0)
        $fatal(1, "44.1 kHz metadata was not latched");

    @(negedge clk);
    format_valid = 1'b0;
    stream_start = 1'b1;
    @(posedge clk);
    #1;
    stream_start = 1'b0;
    if (rate_48k !== 1'b0)
        $fatal(1, "rate changed while next stream metadata was invalid");
    check_output(16'h0000, 16'h0000, "stream prefill silence");

    @(negedge clk);
    playback_active = 1'b1;
    check_output(16'h1234, 16'h5678, "active player source");

    @(negedge clk);
    playback_active = 1'b0;
    check_output(16'h0000, 16'h0000, "post-playback silence");

    @(negedge clk);
    sample_rate = 32'd48_000;
    format_valid = 1'b1;
    @(posedge clk);
    #1;
    if (rate_48k !== 1'b1)
        $fatal(1, "48 kHz metadata was not latched");

    @(negedge clk);
    resetn = 1'b0;
    check_output(16'h0000, 16'h0000, "restart reset silence");
    @(posedge clk);
    #1;
    if (rate_48k !== 1'b1)
        $fatal(1, "restart did not restore 48 kHz default");

    @(negedge clk);
    resetn = 1'b1;
    check_output(16'h2000, 16'he000, "diagnostics restored after reset");

    $display("PASS audio output policy: silent boundaries and retained native rate");
    $finish;
end

endmodule
