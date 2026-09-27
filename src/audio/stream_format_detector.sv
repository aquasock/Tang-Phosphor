// Content-based stream classifier with byte-exact prefix replay. The bounded
// prefix is deliberately only as large as the current RIFF/WAVE signature;
// adding another format must not silently expand this contract.

module stream_format_detector (
    input  logic       clk,
    input  logic       reset,
    input  logic [7:0] input_data,
    input  logic       input_valid,
    output logic       input_ready,
    input  logic       input_end,
    output logic [7:0] output_data,
    output logic       output_valid,
    input  logic       output_ready,
    output logic       output_end,
    output logic [2:0] detected_format,
    output logic       format_valid,
    output logic       format_error
);

localparam logic [2:0]
    FORMAT_NONE       = 3'd0,
    FORMAT_WAV        = 3'd1,
    FORMAT_FLAC       = 3'd2,
    FORMAT_MP3        = 3'd3, // Reserved for the planned decoder.
    FORMAT_OGG_VORBIS = 3'd4; // Reserved for the planned decoder.

localparam logic [2:0]
    STATE_CAPTURE  = 3'd0,
    STATE_REPLAY   = 3'd1,
    STATE_PASS     = 3'd2,
    STATE_DISCARD  = 3'd3,
    STATE_EMIT_END = 3'd4,
    STATE_DONE     = 3'd5;

logic [2:0] state;
logic [7:0] prefix [0:11];
logic [3:0] prefix_count;
logic [3:0] prefix_length;
logic [3:0] replay_index;
logic end_pending;

wire input_transfer = input_valid && input_ready;
wire output_transfer = output_valid && output_ready;
wire flac_signature = prefix[0] == "f" && prefix[1] == "L" &&
    prefix[2] == "a" && input_data == "C";
wire riff_signature = prefix[0] == "R" && prefix[1] == "I" &&
    prefix[2] == "F" && input_data == "F";
wire wave_signature = prefix[8] == "W" && prefix[9] == "A" &&
    prefix[10] == "V" && input_data == "E";

always_comb begin
    input_ready = 1'b0;
    output_data = 8'b0;
    output_valid = 1'b0;
    output_end = 1'b0;

    case (state)
        STATE_CAPTURE: input_ready = 1'b1;
        STATE_REPLAY: begin
            output_data = prefix[replay_index];
            output_valid = 1'b1;
        end
        STATE_PASS: begin
            input_ready = output_ready;
            output_data = input_data;
            output_valid = input_valid;
            output_end = input_end;
        end
        STATE_DISCARD: input_ready = 1'b1;
        STATE_EMIT_END: output_end = 1'b1;
        default: ;
    endcase
end

always_ff @(posedge clk) begin
    if (reset) begin
        state <= STATE_CAPTURE;
        prefix_count <= 0;
        prefix_length <= 0;
        replay_index <= 0;
        end_pending <= 1'b0;
        detected_format <= FORMAT_NONE;
        format_valid <= 1'b0;
        format_error <= 1'b0;
        for (integer i = 0; i < 12; i = i + 1)
            prefix[i] <= 0;
    end else begin
        case (state)
            STATE_CAPTURE: begin
                if (input_transfer) begin
                    prefix[prefix_count] <= input_data;
                    prefix_count <= prefix_count + 1'b1;

                    if (prefix_count == 4'd3) begin
                        if (flac_signature) begin
                            detected_format <= FORMAT_FLAC;
                            format_valid <= 1'b1;
                            prefix_length <= 4'd4;
                            replay_index <= 0;
                            end_pending <= input_end;
                            state <= STATE_REPLAY;
                        end else if (!riff_signature) begin
                            format_error <= 1'b1;
                            state <= input_end ? STATE_DONE : STATE_DISCARD;
                        end else if (input_end) begin
                            format_error <= 1'b1;
                            state <= STATE_DONE;
                        end
                    end else if (prefix_count == 4'd11) begin
                        if (wave_signature) begin
                            detected_format <= FORMAT_WAV;
                            format_valid <= 1'b1;
                            prefix_length <= 4'd12;
                            replay_index <= 0;
                            end_pending <= input_end;
                            state <= STATE_REPLAY;
                        end else begin
                            format_error <= 1'b1;
                            state <= input_end ? STATE_DONE : STATE_DISCARD;
                        end
                    end else if (input_end) begin
                        format_error <= 1'b1;
                        state <= STATE_DONE;
                    end
                end else if (input_end) begin
                    format_error <= 1'b1;
                    state <= STATE_DONE;
                end
            end

            STATE_REPLAY: begin
                if (input_end)
                    end_pending <= 1'b1;
                if (output_transfer) begin
                    if (replay_index + 1'b1 == prefix_length) begin
                        replay_index <= 0;
                        if (end_pending || input_end) begin
                            end_pending <= 1'b0;
                            state <= STATE_EMIT_END;
                        end else
                            state <= STATE_PASS;
                    end else
                        replay_index <= replay_index + 1'b1;
                end
            end

            STATE_PASS: if (input_end)
                state <= STATE_DONE;

            STATE_DISCARD: if (input_end)
                state <= STATE_DONE;

            STATE_EMIT_END: state <= STATE_DONE;

            default: ;
        endcase
    end
end

endmodule
