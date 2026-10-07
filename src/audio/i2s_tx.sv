// SPDX-License-Identifier: GPL-3.0-only
// I2S output, 256 MCLK cycles per stereo frame and 32 bits per channel.
// Signed 16-bit PCM occupies the high 16 bits of a 24-bit DAC word; the
// remaining bits are zero. LRCK and SD change on falling SCLK edges. Slot
// zero is the I2S delay bit, followed by the MSB in slot one.
module i2s_tx (
    input  logic        clk_mclk,
    input  logic        resetn,
    input  logic [15:0] sample_left,
    input  logic [15:0] sample_right,
    output logic        sclk,
    output logic        lrck,
    output logic        sdata,
    output logic        sample_tick
);
    logic [7:0] phase;
    logic [15:0] left_q, right_q;
    logic [23:0] shift;
    wire [4:0] slot = phase[6:2];
    wire [23:0] channel_word = {phase[7] ? right_q : left_q, 8'b0};

    assign sclk = phase[1];
    assign lrck = phase[7];
    // Both channels are captured together at the left-channel boundary.
    assign sample_tick = resetn && phase == 8'hff;

    always_ff @(posedge clk_mclk or negedge resetn) begin
        if (!resetn) begin
            phase   <= 8'd0;
            left_q  <= 16'd0;
            right_q <= 16'd0;
            shift   <= 24'd0;
            sdata   <= 1'b0;
        end else begin
            phase <= phase + 8'd1;
            if (sample_tick) begin
                left_q  <= sample_left;
                right_q <= sample_right;
            end
            if (phase[1:0] == 2'b11) begin
                if (slot == 5'd0) begin
                    sdata <= channel_word[23];
                    shift <= {channel_word[22:0], 1'b0};
                end else if (slot < 5'd24) begin
                    sdata <= shift[23];
                    shift <= {shift[22:0], 1'b0};
                end else begin
                    sdata <= 1'b0;
                end
            end
        end
    end
endmodule
