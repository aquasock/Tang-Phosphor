// Stream-to-HDMI WAV playback shell. The UART receiver provides byte-level
// backpressure; this module adds decoded-PCM buffering and waits for a useful
// prefill before replacing the diagnostic tones.

module wav_stream_player #(
    parameter integer FIFO_ADDRESS_WIDTH = 11,
    parameter integer PREFILL_SAMPLES = 512
) (
    input  logic         clk,
    input  logic         resetn,
    input  logic         stream_start,
    input  logic         stream_end,
    input  logic         stream_cancel,
    input  logic   [7:0] stream_data,
    input  logic         stream_valid,
    output logic         stream_ready,
    input  logic         sample_tick,
    output logic  [15:0] audio_left,
    output logic  [15:0] audio_right,
    output logic         playback_active,
    output logic   [3:0] player_state,
    output logic         format_valid,
    output logic  [31:0] sample_rate,
    output logic [FIFO_ADDRESS_WIDTH:0] fifo_level,
    output logic  [31:0] samples_played,
    output logic  [31:0] underrun_count,
    output logic   [7:0] error_code
);

localparam logic [3:0]
    PLAYER_IDLE      = 4'd0,
    PLAYER_RECEIVING = 4'd1,
    PLAYER_PREFILL   = 4'd2,
    PLAYER_PLAYING   = 4'd3,
    PLAYER_COMPLETE  = 4'd4,
    PLAYER_ERROR     = 4'd5,
    PLAYER_CANCELLED = 4'd6;
localparam logic [FIFO_ADDRESS_WIDTH:0] PREFILL_LEVEL =
    (FIFO_ADDRESS_WIDTH + 1)'(PREFILL_SAMPLES);

logic session_active;
logic decoder_reset;
logic decoder_ready;
logic decoder_pcm_valid;
logic decoder_pcm_ready;
logic signed [15:0] decoder_pcm_left;
logic signed [15:0] decoder_pcm_right;
logic decoder_pcm_eof;
logic decoder_metadata_valid;
logic [31:0] decoder_total_samples;
logic decoder_format_error;
logic [7:0] decoder_error_code;

logic [32:0] fifo_input_data;
logic fifo_input_ready;
logic [32:0] fifo_output_data;
logic fifo_output_valid;
logic fifo_output_ready;
logic eof_queued;
logic playback_started;
logic finish_pending;
logic playback_complete;

assign decoder_reset = !resetn || stream_start || stream_cancel;
assign stream_ready = session_active && decoder_ready;

wav_decoder decoder (
    .clk(clk), .reset(decoder_reset),
    .input_data(stream_data),
    .input_valid(stream_valid && session_active),
    .input_ready(decoder_ready),
    .input_end(stream_end && session_active),
    .pcm_valid(decoder_pcm_valid), .pcm_ready(decoder_pcm_ready),
    .pcm_left(decoder_pcm_left), .pcm_right(decoder_pcm_right),
    .pcm_eof(decoder_pcm_eof), .format_valid(format_valid),
    .metadata_valid(decoder_metadata_valid), .sample_rate(sample_rate),
    .total_samples(decoder_total_samples),
    .format_error(decoder_format_error), .error_code(decoder_error_code)
);

assign fifo_input_data = {decoder_pcm_eof, decoder_pcm_left, decoder_pcm_right};
assign decoder_pcm_ready = fifo_input_ready;
assign fifo_output_ready = sample_tick && playback_started && fifo_output_valid;

pcm_sample_fifo #(.ADDRESS_WIDTH(FIFO_ADDRESS_WIDTH)) pcm_fifo (
    .clk(clk), .reset(!resetn), .clear(stream_start || stream_cancel),
    .input_data(fifo_input_data), .input_valid(decoder_pcm_valid),
    .input_ready(fifo_input_ready), .output_data(fifo_output_data),
    .output_valid(fifo_output_valid), .output_ready(fifo_output_ready),
    .level(fifo_level)
);

always_ff @(posedge clk) begin
    if (!resetn) begin
        session_active <= 1'b0;
        audio_left <= 0;
        audio_right <= 0;
        playback_active <= 1'b0;
        player_state <= PLAYER_IDLE;
        samples_played <= 0;
        underrun_count <= 0;
        error_code <= 0;
        eof_queued <= 1'b0;
        playback_started <= 1'b0;
        finish_pending <= 1'b0;
        playback_complete <= 1'b0;
    end else if (stream_cancel) begin
        session_active <= 1'b0;
        audio_left <= 0;
        audio_right <= 0;
        playback_active <= 1'b0;
        player_state <= PLAYER_CANCELLED;
        samples_played <= 0;
        underrun_count <= 0;
        error_code <= 0;
        eof_queued <= 1'b0;
        playback_started <= 1'b0;
        finish_pending <= 1'b0;
        playback_complete <= 1'b0;
    end else if (stream_start) begin
        session_active <= 1'b1;
        audio_left <= 0;
        audio_right <= 0;
        playback_active <= 1'b0;
        player_state <= PLAYER_RECEIVING;
        samples_played <= 0;
        underrun_count <= 0;
        error_code <= 0;
        eof_queued <= 1'b0;
        playback_started <= 1'b0;
        finish_pending <= 1'b0;
        playback_complete <= 1'b0;
    end else begin
        if (stream_end)
            session_active <= 1'b0;

        if (decoder_format_error) begin
            error_code <= decoder_error_code;
            player_state <= PLAYER_ERROR;
            playback_started <= 1'b0;
            playback_active <= 1'b0;
        end else begin
            if (format_valid && !playback_started && !playback_active &&
                    !finish_pending && !playback_complete)
                player_state <= PLAYER_PREFILL;

            if (decoder_pcm_valid && decoder_pcm_ready && decoder_pcm_eof)
                eof_queued <= 1'b1;

            if (!playback_started && !finish_pending && !playback_complete && format_valid &&
                    (fifo_level >= PREFILL_LEVEL || eof_queued)) begin
                playback_started <= 1'b1;
                playback_active <= 1'b1;
                player_state <= PLAYER_PLAYING;
            end

            if (sample_tick && playback_started) begin
                if (fifo_output_valid) begin
                    audio_left <= fifo_output_data[31:16];
                    audio_right <= fifo_output_data[15:0];
                    samples_played <= samples_played + 1'b1;
                    if (fifo_output_data[32]) begin
                        playback_started <= 1'b0;
                        finish_pending <= 1'b1;
                    end
                end else begin
                    audio_left <= 0;
                    audio_right <= 0;
                    underrun_count <= underrun_count + 1'b1;
                end
            end else if (sample_tick && finish_pending) begin
                audio_left <= 0;
                audio_right <= 0;
                playback_active <= 1'b0;
                finish_pending <= 1'b0;
                playback_complete <= 1'b1;
                player_state <= PLAYER_COMPLETE;
            end
        end
    end
end

endmodule
