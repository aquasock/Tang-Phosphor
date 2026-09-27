// Deterministic stereo test source for HDMI audio bring-up.

module audio_test_source #(
    parameter integer PIXEL_CLOCK_HZ = 74_250_000,
    parameter integer LEFT_TONE_HZ = 1_000,
    parameter integer RIGHT_TONE_HZ = 2_000,
    parameter logic signed [15:0] AMPLITUDE = 16'sd8192
) (
    input  logic        clk_pixel,
    input  logic        resetn,
    input  logic        rate_48k,
    output logic        clk_audio,
    output logic        sample_tick,
    output logic [31:0] active_sample_rate,
    output logic [15:0] audio_sample_word [1:0]
);

localparam integer RATE_ACCUMULATOR_WIDTH = $clog2(PIXEL_CLOCK_HZ);
localparam logic [RATE_ACCUMULATOR_WIDTH-1:0] RATE_STEP_44 =
    RATE_ACCUMULATOR_WIDTH'(2 * 44_100);
localparam logic [RATE_ACCUMULATOR_WIDTH-1:0] RATE_STEP_48 =
    RATE_ACCUMULATOR_WIDTH'(2 * 48_000);
localparam logic [RATE_ACCUMULATOR_WIDTH-1:0] RATE_WRAP_THRESHOLD_44 =
    RATE_ACCUMULATOR_WIDTH'(PIXEL_CLOCK_HZ - 2 * 44_100);
localparam logic [RATE_ACCUMULATOR_WIDTH-1:0] RATE_WRAP_THRESHOLD_48 =
    RATE_ACCUMULATOR_WIDTH'(PIXEL_CLOCK_HZ - 2 * 48_000);
localparam logic [15:0] LEFT_PHASE_STEP = 16'(LEFT_TONE_HZ);
localparam logic [15:0] RIGHT_PHASE_STEP = 16'(RIGHT_TONE_HZ);

logic [RATE_ACCUMULATOR_WIDTH-1:0] rate_accumulator;
logic active_rate_48k;
logic [15:0] left_phase;
logic [15:0] right_phase;

wire [15:0] selected_sample_rate = active_rate_48k ? 16'd48_000 : 16'd44_100;
wire [15:0] selected_half_rate = active_rate_48k ? 16'd24_000 : 16'd22_050;
wire [15:0] left_wrap_threshold = selected_sample_rate - LEFT_PHASE_STEP;
wire [15:0] right_wrap_threshold = selected_sample_rate - RIGHT_PHASE_STEP;
wire [RATE_ACCUMULATOR_WIDTH-1:0] rate_step =
    active_rate_48k ? RATE_STEP_48 : RATE_STEP_44;
wire [RATE_ACCUMULATOR_WIDTH-1:0] rate_wrap_threshold =
    active_rate_48k ? RATE_WRAP_THRESHOLD_48 : RATE_WRAP_THRESHOLD_44;

assign active_sample_rate = active_rate_48k ? 32'd48_000 : 32'd44_100;

// Generate twice the selected sample rate as an average toggle cadence. Rising
// edges are sample ticks, with individual intervals differing by at most one
// pixel clock. A rate transition restarts the clock and tone phases before a
// prefilling player is allowed to become active.
always_ff @(posedge clk_pixel) begin
    if (!resetn) begin
        rate_accumulator <= 0;
        active_rate_48k <= 1'b1;
        clk_audio <= 1'b0;
        sample_tick <= 1'b0;
        left_phase <= 0;
        right_phase <= 0;
        audio_sample_word[0] <= 16'b0;
        audio_sample_word[1] <= 16'b0;
    end else if (rate_48k != active_rate_48k) begin
        rate_accumulator <= 0;
        active_rate_48k <= rate_48k;
        clk_audio <= 1'b0;
        sample_tick <= 1'b0;
        left_phase <= 0;
        right_phase <= 0;
        audio_sample_word[0] <= 16'b0;
        audio_sample_word[1] <= 16'b0;
    end else begin
        sample_tick <= 1'b0;
        if (rate_accumulator >= rate_wrap_threshold) begin
            rate_accumulator <= rate_accumulator - rate_wrap_threshold;
            clk_audio <= ~clk_audio;

            // The HDMI packetizer consumes a new sample on each rising edge.
            if (!clk_audio) begin
                sample_tick <= 1'b1;
                audio_sample_word[0] <= left_phase < selected_half_rate ?
                    AMPLITUDE : -AMPLITUDE;
                audio_sample_word[1] <= right_phase < selected_half_rate ?
                    AMPLITUDE : -AMPLITUDE;

                left_phase <= left_phase >= left_wrap_threshold ?
                    left_phase - left_wrap_threshold : left_phase + LEFT_PHASE_STEP;
                right_phase <= right_phase >= right_wrap_threshold ?
                    right_phase - right_wrap_threshold : right_phase + RIGHT_PHASE_STEP;
            end
        end else begin
            rate_accumulator <= rate_accumulator + rate_step;
        end
    end
end

endmodule
