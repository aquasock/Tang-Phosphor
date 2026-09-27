// Stream-to-HDMI audio playback shell. The UART receiver provides byte-level
// backpressure; this module selects the detected decoder, adds decoded-PCM
// buffering, and waits for a useful prefill before replacing diagnostic tones.

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
    output logic   [7:0] error_code,
    output logic   [2:0] detected_format
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
logic [7:0] ingress_data [0:1];
logic ingress_read_pointer;
logic ingress_write_pointer;
logic [1:0] ingress_count;
logic ingress_end_pending;
logic detector_ready;
logic [7:0] detector_data;
logic detector_valid;
logic detector_output_ready;
logic detector_end;
logic detector_format_valid;
logic detector_format_error;
logic [7:0] decoder_ingress_data [0:1];
logic decoder_ingress_read_pointer;
logic decoder_ingress_write_pointer;
logic [1:0] decoder_ingress_count;
logic decoder_end_pending;
logic wav_ready;
logic wav_pcm_valid;
logic wav_pcm_ready;
logic signed [15:0] wav_pcm_left;
logic signed [15:0] wav_pcm_right;
logic wav_pcm_eof;
logic wav_format_valid;
logic [31:0] wav_sample_rate;
logic wav_format_error;
logic [7:0] wav_error_code;
logic flac_ready;
logic flac_pcm_valid;
logic flac_pcm_ready;
logic signed [15:0] flac_pcm_left;
logic signed [15:0] flac_pcm_right;
logic flac_pcm_eof;
logic flac_format_valid;
logic [31:0] flac_sample_rate;
logic flac_format_error;
logic [7:0] flac_error_code;
logic selected_pcm_valid;
logic decoder_pcm_ready;
logic signed [15:0] selected_pcm_left;
logic signed [15:0] selected_pcm_right;
logic selected_pcm_eof;
logic selected_format_error;
logic [7:0] selected_error_code;

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
assign stream_ready = session_active && ingress_count != 2;

wire ingress_push = stream_valid && stream_ready;
wire ingress_pop = ingress_count != 0 && detector_ready;

always_ff @(posedge clk) begin
    if (!resetn || stream_start || stream_cancel) begin
        ingress_read_pointer <= 1'b0;
        ingress_write_pointer <= 1'b0;
        ingress_count <= 0;
        ingress_end_pending <= 1'b0;
    end else begin
        if (stream_end && session_active)
            ingress_end_pending <= 1'b1;

        if (ingress_push) begin
            ingress_data[ingress_write_pointer] <= stream_data;
            ingress_write_pointer <= !ingress_write_pointer;
        end
        if (ingress_pop)
            ingress_read_pointer <= !ingress_read_pointer;

        case ({ingress_push, ingress_pop})
            2'b10: ingress_count <= ingress_count + 1'b1;
            2'b01: ingress_count <= ingress_count - 1'b1;
            default: ;
        endcase
    end
end

stream_format_detector detector (
    .clk(clk), .reset(decoder_reset),
    .input_data(ingress_data[ingress_read_pointer]),
    .input_valid(ingress_count != 0),
    .input_ready(detector_ready),
    .input_end(ingress_end_pending && ingress_count == 0),
    .output_data(detector_data), .output_valid(detector_valid),
    .output_ready(detector_output_ready), .output_end(detector_end),
    .detected_format(detected_format), .format_valid(detector_format_valid),
    .format_error(detector_format_error)
);

wire selected_decoder_ready = detected_format == 3'd1 ? wav_ready :
    detected_format == 3'd2 ? flac_ready : 1'b1;
wire decoder_ingress_push = detector_valid && detector_output_ready;
wire decoder_ingress_pop = decoder_ingress_count != 0 && selected_decoder_ready;

assign detector_output_ready = decoder_ingress_count != 2;

always_ff @(posedge clk) begin
    if (decoder_reset) begin
        decoder_ingress_read_pointer <= 1'b0;
        decoder_ingress_write_pointer <= 1'b0;
        decoder_ingress_count <= 0;
        decoder_end_pending <= 1'b0;
    end else begin
        if (detector_end)
            decoder_end_pending <= 1'b1;

        if (decoder_ingress_push) begin
            decoder_ingress_data[decoder_ingress_write_pointer] <= detector_data;
            decoder_ingress_write_pointer <= !decoder_ingress_write_pointer;
        end
        if (decoder_ingress_pop)
            decoder_ingress_read_pointer <= !decoder_ingress_read_pointer;

        case ({decoder_ingress_push, decoder_ingress_pop})
            2'b10: decoder_ingress_count <= decoder_ingress_count + 1'b1;
            2'b01: decoder_ingress_count <= decoder_ingress_count - 1'b1;
            default: ;
        endcase
    end
end

wav_decoder wav_decoder_instance (
    .clk(clk), .reset(decoder_reset),
    .input_data(decoder_ingress_data[decoder_ingress_read_pointer]),
    .input_valid(decoder_ingress_count != 0 && detected_format == 3'd1),
    .input_ready(wav_ready),
    .input_end(decoder_end_pending && decoder_ingress_count == 0 &&
        detected_format == 3'd1),
    .pcm_valid(wav_pcm_valid), .pcm_ready(wav_pcm_ready),
    .pcm_left(wav_pcm_left), .pcm_right(wav_pcm_right),
    .pcm_eof(wav_pcm_eof), .format_valid(wav_format_valid),
    .metadata_valid(), .sample_rate(wav_sample_rate), .total_samples(),
    .format_error(wav_format_error), .error_code(wav_error_code)
);

flac_decoder flac_decoder_instance (
    .clk(clk), .reset(decoder_reset),
    .input_data(decoder_ingress_data[decoder_ingress_read_pointer]),
    .input_valid(decoder_ingress_count != 0 && detected_format == 3'd2),
    .input_ready(flac_ready),
    .input_end(decoder_end_pending && decoder_ingress_count == 0 &&
        detected_format == 3'd2),
    .pcm_valid(flac_pcm_valid), .pcm_ready(flac_pcm_ready),
    .pcm_left(flac_pcm_left), .pcm_right(flac_pcm_right),
    .pcm_eof(flac_pcm_eof), .format_valid(flac_format_valid),
    .metadata_valid(), .sample_rate(flac_sample_rate), .total_samples(),
    .format_error(flac_format_error), .error_code(flac_error_code)
);

assign format_valid = detected_format == 3'd1 ? wav_format_valid :
    detected_format == 3'd2 ? flac_format_valid : 1'b0;
assign sample_rate = detected_format == 3'd1 ? wav_sample_rate :
    detected_format == 3'd2 ? flac_sample_rate : 32'b0;
assign selected_pcm_valid = detected_format == 3'd1 ? wav_pcm_valid :
    detected_format == 3'd2 ? flac_pcm_valid : 1'b0;
assign selected_pcm_left = detected_format == 3'd1 ? wav_pcm_left : flac_pcm_left;
assign selected_pcm_right = detected_format == 3'd1 ? wav_pcm_right : flac_pcm_right;
assign selected_pcm_eof = detected_format == 3'd1 ? wav_pcm_eof : flac_pcm_eof;
assign selected_format_error = detected_format == 3'd1 ? wav_format_error :
    detected_format == 3'd2 ? flac_format_error : 1'b0;
assign selected_error_code = detected_format == 3'd1 ? wav_error_code : flac_error_code;

assign fifo_input_data = {selected_pcm_eof, selected_pcm_left, selected_pcm_right};
assign decoder_pcm_ready = fifo_input_ready;
assign wav_pcm_ready = decoder_pcm_ready && detected_format == 3'd1;
assign flac_pcm_ready = decoder_pcm_ready && detected_format == 3'd2;
assign fifo_output_ready = sample_tick && playback_started && fifo_output_valid;

pcm_sample_fifo #(.ADDRESS_WIDTH(FIFO_ADDRESS_WIDTH)) pcm_fifo (
    .clk(clk), .reset(!resetn), .clear(stream_start || stream_cancel),
    .input_data(fifo_input_data), .input_valid(selected_pcm_valid),
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

        if (detector_format_error) begin
            error_code <= 8'h11; // Unknown or truncated content signature.
            player_state <= PLAYER_ERROR;
            playback_started <= 1'b0;
            playback_active <= 1'b0;
        end else if (detector_format_valid &&
                detected_format != 3'd1 && detected_format != 3'd2) begin
            error_code <= 8'h10; // Recognized format has no decoder yet.
            player_state <= PLAYER_ERROR;
            playback_started <= 1'b0;
            playback_active <= 1'b0;
        end else if (selected_format_error) begin
            error_code <= selected_error_code;
            player_state <= PLAYER_ERROR;
            playback_started <= 1'b0;
            playback_active <= 1'b0;
        end else begin
            if (format_valid && !playback_started && !playback_active &&
                    !finish_pending && !playback_complete)
                player_state <= PLAYER_PREFILL;

            if (selected_pcm_valid && decoder_pcm_ready && selected_pcm_eof)
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
