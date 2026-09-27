// Deterministic stereo test source for HDMI audio bring-up.

module audio_test_source #(
    parameter integer PIXEL_CLOCK_HZ = 74_250_000,
    parameter integer SAMPLE_RATE_HZ = 48_000,
    parameter integer LEFT_TONE_HZ = 1_000,
    parameter integer RIGHT_TONE_HZ = 2_000,
    parameter logic signed [15:0] AMPLITUDE = 16'sd8192
) (
    input  logic        clk_pixel,
    input  logic        resetn,
    output logic        clk_audio,
    output logic [15:0] audio_sample_word [1:0]
);

localparam integer AUDIO_TOGGLE_RATE_HZ = 2 * SAMPLE_RATE_HZ;
localparam integer RATE_ACCUMULATOR_WIDTH = $clog2(PIXEL_CLOCK_HZ);
localparam integer LEFT_HALF_PERIOD = SAMPLE_RATE_HZ / (2 * LEFT_TONE_HZ);
localparam integer RIGHT_HALF_PERIOD = SAMPLE_RATE_HZ / (2 * RIGHT_TONE_HZ);
localparam integer LEFT_COUNTER_WIDTH = $clog2(LEFT_HALF_PERIOD);
localparam integer RIGHT_COUNTER_WIDTH = $clog2(RIGHT_HALF_PERIOD);

localparam logic [RATE_ACCUMULATOR_WIDTH-1:0] RATE_STEP =
    RATE_ACCUMULATOR_WIDTH'(AUDIO_TOGGLE_RATE_HZ);
localparam logic [RATE_ACCUMULATOR_WIDTH-1:0] RATE_WRAP_THRESHOLD =
    RATE_ACCUMULATOR_WIDTH'(PIXEL_CLOCK_HZ - AUDIO_TOGGLE_RATE_HZ);
localparam logic [LEFT_COUNTER_WIDTH-1:0] LEFT_COUNT_END =
    LEFT_COUNTER_WIDTH'(LEFT_HALF_PERIOD - 1);
localparam logic [RIGHT_COUNTER_WIDTH-1:0] RIGHT_COUNT_END =
    RIGHT_COUNTER_WIDTH'(RIGHT_HALF_PERIOD - 1);

logic [RATE_ACCUMULATOR_WIDTH-1:0] rate_accumulator;
logic [LEFT_COUNTER_WIDTH-1:0] left_half_count;
logic [RIGHT_COUNTER_WIDTH-1:0] right_half_count;
logic left_positive;
logic right_positive;

// Generate a 96 kHz average toggle rate. Rising edges therefore occur at an
// exact average of 48 kHz, with the individual sample intervals differing by
// at most one pixel clock.
always_ff @(posedge clk_pixel) begin
    if (!resetn) begin
        rate_accumulator <= 0;
        clk_audio <= 1'b0;
        left_half_count <= 0;
        right_half_count <= 0;
        left_positive <= 1'b1;
        right_positive <= 1'b1;
        audio_sample_word[0] <= 16'b0;
        audio_sample_word[1] <= 16'b0;
    end else begin
        if (rate_accumulator >= RATE_WRAP_THRESHOLD) begin
            rate_accumulator <= rate_accumulator - RATE_WRAP_THRESHOLD;
            clk_audio <= ~clk_audio;

            // The HDMI packetizer consumes a new sample on each rising edge.
            if (!clk_audio) begin
                audio_sample_word[0] <= left_positive ? AMPLITUDE : -AMPLITUDE;
                audio_sample_word[1] <= right_positive ? AMPLITUDE : -AMPLITUDE;

                if (left_half_count == LEFT_COUNT_END) begin
                    left_half_count <= 0;
                    left_positive <= ~left_positive;
                end else begin
                    left_half_count <= left_half_count + 1'b1;
                end

                if (right_half_count == RIGHT_COUNT_END) begin
                    right_half_count <= 0;
                    right_positive <= ~right_positive;
                end else begin
                    right_half_count <= right_half_count + 1'b1;
                end
            end
        end else begin
            rate_accumulator <= rate_accumulator + RATE_STEP;
        end
    end
end

endmodule
