// Stream-to-HDMI audio shell, decoder-removed placeholder.
//
// Tang-Phosphor's FPGA player no longer decodes WAV or FLAC itself: all
// decode moves to the AE350 (Rockbox).  This module keeps the full port list
// of the former player so tang_phosphor_top and debug_regs are unchanged, and
// presents silence to the HDMI audio path (audio_output_policy falls back to
// the diagnostic tones).  It is the placeholder that the next cycle's raw-PCM
// sink (fed by ae350_play_stream) will replace.

module wav_stream_player #(
    parameter integer FIFO_ADDRESS_WIDTH = 14,
    parameter integer PREFILL_SAMPLES = 512
) (
    input  logic         clk,
    input  logic         resetn,
    input  logic         stream_start,
    input  logic         stream_end,
    input  logic         stream_cancel,
    input  logic  [15:0] stream_id,
    input  logic   [7:0] stream_data,
    input  logic         stream_valid,
    output logic         stream_ready,
    input  logic         sample_tick,
    input  logic         paused,
    output logic  [15:0] audio_left,
    output logic  [15:0] audio_right,
    output logic         playback_active,
    output logic   [3:0] player_state,
    output logic         format_valid,
    output logic  [31:0] sample_rate,
    output logic [FIFO_ADDRESS_WIDTH:0] fifo_level,
    output logic  [31:0] samples_played,
    output logic  [35:0] total_samples,
    output logic  [31:0] elapsed_seconds,
    output logic  [31:0] duration_seconds,
    output logic  [31:0] underrun_count,
    output logic   [7:0] error_code,
    output logic   [2:0] detected_format,
    output logic         playback_rate_valid,
    output logic  [31:0] playback_rate,
    output logic  [15:0] audible_stream_id,
    output logic  [31:0] boundary_count,
    output logic  [31:0] boundary_gap_samples
);

    // Accept and discard the ingress so the transport never stalls; the raw
    // PCM path will replace this with a real buffer in the next cycle.
    assign stream_ready = 1'b1;

    assign audio_left          = 16'd0;
    assign audio_right         = 16'd0;
    assign playback_active     = 1'b0;
    assign player_state        = 4'd0;
    assign format_valid        = 1'b0;
    assign sample_rate         = 32'd0;
    assign fifo_level          = '0;
    assign samples_played      = 32'd0;
    assign total_samples       = 36'd0;
    assign elapsed_seconds     = 32'd0;
    assign duration_seconds    = 32'd0;
    assign underrun_count      = 32'd0;
    assign error_code          = 8'd0;
    assign detected_format     = 3'd0;
    assign playback_rate_valid = 1'b0;
    assign playback_rate       = 32'd0;
    assign audible_stream_id   = 16'd0;
    assign boundary_count      = 32'd0;
    assign boundary_gap_samples = 32'd0;

endmodule
