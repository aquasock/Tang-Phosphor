// Raw-PCM audio sink: the FPGA player no longer decodes anything.  It takes
// interleaved 16-bit stereo PCM bytes from the AE350's play stream (four bytes
// per sample pair, little-endian: L[7:0], L[15:8], R[7:0], R[15:8]), buffers
// them, and clocks them out to the HDMI audio path at the rate the AE350
// announced in the play-stream START entry.
//
// Ports keep the former wav_stream_player's shape so the top level and debug
// registers are unchanged.  cpu_mode is 1 during playback: with the decoders
// gone, the BL616 native path has nothing to feed this sink.

module pcm_sink #(
    parameter integer FIFO_ADDRESS_WIDTH = 11
) (
    input  logic        clk,
    input  logic        resetn,
    input  logic        stream_start,
    input  logic        stream_end,
    input  logic        stream_cancel,
    input  logic [15:0] stream_id,
    input  logic [7:0]  stream_data,
    input  logic        stream_valid,
    output logic        stream_ready,
    input  logic [31:0] play_rate,      // valid while stream_start pulses
    input  logic        sample_tick,
    input  logic        paused,
    output logic [15:0] audio_left,
    output logic [15:0] audio_right,
    output logic        playback_active,
    output logic [3:0]  player_state,
    output logic        format_valid,
    output logic [31:0] sample_rate,
    output logic [FIFO_ADDRESS_WIDTH:0] fifo_level,
    output logic [31:0] samples_played,
    output logic [35:0] total_samples,
    output logic [31:0] elapsed_seconds,
    output logic [31:0] duration_seconds,
    output logic [31:0] underrun_count,
    output logic [7:0]  error_code,
    output logic [2:0]  detected_format,
    output logic        playback_rate_valid,
    output logic [31:0] playback_rate,
    output logic [15:0] audible_stream_id,
    output logic [31:0] boundary_count,
    output logic [31:0] boundary_gap_samples
);

    localparam logic [3:0]
        ST_IDLE      = 4'd0,
        ST_RECEIVING = 4'd1,
        ST_PLAYING   = 4'd2,
        ST_DONE      = 4'd4;

    logic [3:0]  state;
    logic [31:0] rate;
    logic        rate_valid;
    logic [1:0]  byte_index;
    logic [31:0] shift;        // four bytes -> {right, left}
    logic [31:0] sample;       // captured complete sample
    logic        sample_ready; // one-cycle pulse when sample is complete
    logic        end_seen;

    logic [32:0] fifo_in;
    logic        fifo_in_valid;
    logic        fifo_in_ready;
    logic [32:0] fifo_out;
    logic        fifo_out_valid;

    logic [31:0] samples_played_r;
    logic [31:0] underruns_r;

    assign stream_ready = fifo_in_ready;

    // ------------------------------------------------------------------
    // Byte assembler.  shift collects four bytes into {right, left}; on the
    // fourth byte the complete word is captured into sample and sample_ready
    // pulses one cycle later, after shift has settled.
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!resetn || stream_cancel || stream_start) begin
            byte_index   <= 0;
            shift        <= 0;
            sample       <= 0;
            sample_ready <= 1'b0;
            end_seen     <= 1'b0;
        end else begin
            sample_ready <= 1'b0;
            if (stream_valid && stream_ready) begin
                shift      <= {stream_data, shift[31:8]};
                byte_index <= byte_index + 2'd1;
                if (byte_index == 2'd3) begin
                    sample       <= {stream_data, shift[31:8]};
                    sample_ready <= 1'b1;
                end
            end
            if (stream_end)
                end_seen <= 1'b1;
        end
    end

    assign fifo_in       = {1'b0, sample[31:16], sample[15:0]};
    assign fifo_in_valid = sample_ready;

    pcm_sample_fifo #(.ADDRESS_WIDTH(FIFO_ADDRESS_WIDTH)) fifo (
        .clk(clk), .reset(!resetn), .clear(stream_cancel || stream_start),
        .input_data(fifo_in), .input_valid(fifo_in_valid), .input_ready(fifo_in_ready),
        .output_data(fifo_out), .output_valid(fifo_out_valid),
        .output_ready(sample_tick && !paused), .level(fifo_level)
    );

    // ------------------------------------------------------------------
    // Playback state and status.
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!resetn) begin
            state           <= ST_IDLE;
            rate            <= 32'd0;
            rate_valid      <= 1'b0;
            playback_active <= 1'b0;
            samples_played_r <= 32'd0;
            underruns_r     <= 32'd0;
        end else begin
            if (stream_cancel) begin
                state           <= ST_IDLE;
                playback_active <= 1'b0;
                rate_valid      <= 1'b0;
            end else begin
                if (stream_start) begin
                    state            <= ST_RECEIVING;
                    rate             <= play_rate;
                    rate_valid       <= 1'b1;
                    samples_played_r <= 32'd0;
                end

                if (state == ST_RECEIVING && fifo_out_valid)
                    state <= ST_PLAYING;
                if (state == ST_PLAYING && end_seen && !fifo_out_valid)
                    state <= ST_DONE;
                if (state == ST_DONE)
                    playback_active <= 1'b0;

                if (sample_tick && !paused) begin
                    if (fifo_out_valid) begin
                        samples_played_r <= samples_played_r + 32'd1;
                        playback_active  <= 1'b1;
                    end else if (state == ST_PLAYING || state == ST_RECEIVING) begin
                        underruns_r <= underruns_r + 32'd1;
                    end
                end
            end
        end
    end

    assign audio_left           = fifo_out[15:0];
    assign audio_right          = fifo_out[31:16];
    assign player_state         = state;
    assign format_valid         = rate_valid;
    assign sample_rate          = rate;
    assign samples_played       = samples_played_r;
    assign total_samples        = 36'd0;
    assign elapsed_seconds      = 32'd0;   // placeholder until rate-based time is wired
    assign duration_seconds     = 32'd0;
    assign underrun_count       = underruns_r;
    assign error_code           = 8'd0;
    assign detected_format      = 3'd0;
    assign playback_rate_valid  = rate_valid;
    assign playback_rate        = rate;
    assign audible_stream_id    = stream_id;
    assign boundary_count       = 32'd0;
    assign boundary_gap_samples = 32'd0;

endmodule
