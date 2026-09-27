// Owns the HDMI audio source and native-rate behavior around stream boundaries.
// Diagnostic tones are available only before the first stream session. Once
// file playback has begun, inactive periods are silent so a completed track or
// playlist transition cannot expose the diagnostic source.

module audio_output_policy (
    input  logic         clk,
    input  logic         resetn,
    input  logic         stream_start,
    input  logic         format_valid,
    input  logic  [31:0] sample_rate,
    input  logic         playback_active,
    input  logic  [15:0] player_left,
    input  logic  [15:0] player_right,
    input  logic  [15:0] diagnostic_left,
    input  logic  [15:0] diagnostic_right,
    output logic         rate_48k,
    output logic  [15:0] output_left,
    output logic  [15:0] output_right
);

logic stream_seen;

always_ff @(posedge clk) begin
    if (!resetn) begin
        stream_seen <= 1'b0;
        rate_48k <= 1'b1;
    end else begin
        if (stream_start)
            stream_seen <= 1'b1;

        // Retain the last valid rate while the next independent stream parses
        // its metadata. This avoids a false 44.1 -> 48 -> 44.1 kHz transition.
        if (format_valid)
            rate_48k <= sample_rate == 32'd48_000;
    end
end

always_comb begin
    if (!resetn) begin
        output_left = 16'b0;
        output_right = 16'b0;
    end else if (playback_active) begin
        output_left = player_left;
        output_right = player_right;
    end else if (!stream_seen) begin
        output_left = diagnostic_left;
        output_right = diagnostic_right;
    end else begin
        output_left = 16'b0;
        output_right = 16'b0;
    end
end

endmodule
