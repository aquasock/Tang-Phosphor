// SPDX-License-Identifier: GPL-3.0-only
// Output-only I2S2 bring-up: 48 kHz stereo, left 1 kHz and right 2 kHz.
// Digilent lanes 0..3 are DAC MCLK, LRCK, SCLK, SDIN. The ADC row is
// released. This personality does not consume the player's PCM yet.
module pmod_i2s2_tone (
    input  logic       clk_mclk,  // PLL-derived 12.288 MHz
    input  logic       enable,    // includes reset and both PLL locks
    output logic [7:0] lane_o,
    output logic [7:0] lane_oe
);
    // Async assertion stops output if the socket is withdrawn or a PLL
    // unlocks. Release is synchronized to the destination clock, following
    // the reset synchronization practice inspected in local colibri.
    logic [1:0] reset_sync = 2'b00 /* synthesis syn_srlstyle = "registers" */;
    always_ff @(posedge clk_mclk or negedge enable) begin
        if (!enable)
            reset_sync <= 2'b00;
        else
            reset_sync <= {reset_sync[0], 1'b1};
    end
    wire resetn = reset_sync[1];
    logic [5:0] tone_phase;
    wire [15:0] left_sample = tone_phase < 6'd24 ? 16'h2000 : 16'he000;
    wire [15:0] right_sample = (tone_phase < 6'd12 ||
                              (tone_phase >= 6'd24 && tone_phase < 6'd36))
                              ? 16'h2000 : 16'he000;
    wire sample_tick;
    wire sclk, lrck, sdata;

    always_ff @(posedge clk_mclk or negedge resetn) begin
        if (!resetn)
            tone_phase <= 6'd0;
        else if (sample_tick)
            tone_phase <= tone_phase == 6'd47 ? 6'd0 : tone_phase + 6'd1;
    end

    i2s_tx tx (
        .clk_mclk(clk_mclk), .resetn(resetn),
        .sample_left(left_sample), .sample_right(right_sample),
        .sclk(sclk), .lrck(lrck), .sdata(sdata), .sample_tick(sample_tick)
    );
    assign lane_o  = {4'b0, sdata, sclk, lrck, clk_mclk && resetn};
    assign lane_oe = enable ? 8'h0f : 8'h00;
endmodule
