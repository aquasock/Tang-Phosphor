// Bounded RIFF/WAVE PCM parser for Tang-Phosphor's first playback profile:
// signed 16-bit stereo at 44.1 or 48 kHz. The byte and PCM sides both use valid/ready
// handshakes, allowing the downstream PCM FIFO to pace the UART stream.

module wav_decoder (
    input  logic               clk,
    input  logic               reset,
    input  logic         [7:0] input_data,
    input  logic               input_valid,
    output logic               input_ready,
    input  logic               input_end,
    output logic               pcm_valid,
    input  logic               pcm_ready,
    output logic signed [15:0] pcm_left,
    output logic signed [15:0] pcm_right,
    output logic               pcm_eof,
    output logic               format_valid,
    output logic               metadata_valid,
    output logic        [31:0] sample_rate,
    output logic        [31:0] total_samples,
    output logic               format_error,
    output logic         [7:0] error_code
);

localparam logic [3:0]
    HEADER        = 4'd0,
    CHUNK_ID      = 4'd1,
    CHUNK_SIZE    = 4'd2,
    CHUNK_DATA    = 4'd3,
    CHUNK_PAD     = 4'd4,
    SAMPLE_LEFT0  = 4'd5,
    SAMPLE_LEFT1  = 4'd6,
    SAMPLE_RIGHT0 = 4'd7,
    SAMPLE_RIGHT1 = 4'd8,
    SAMPLE_EMIT   = 4'd9,
    DRAIN         = 4'd10,
    FAILED        = 4'd11,
    VALIDATE_FMT  = 4'd12;

localparam logic [1:0] CHUNK_SKIP = 2'd0, CHUNK_FMT = 2'd1;

logic [3:0] state;
logic [3:0] header_index;
logic header_bad;
logic [1:0] field_index;
logic [31:0] chunk_id;
logic [31:0] chunk_size_value;
logic [31:0] chunk_remaining;
logic chunk_odd;
logic [1:0] chunk_kind;
logic [31:0] chunk_position;
logic [31:0] data_remaining;
logic [7:0] sample_left_low;
logic [7:0] sample_left_high;
logic [7:0] sample_right_low;
logic [7:0] sample_right_high;

logic [31:0] fmt_size;
logic [15:0] fmt_tag;
logic [15:0] fmt_channels;
logic [31:0] fmt_rate;
logic [15:0] fmt_alignment;
logic [15:0] fmt_bits;

wire consume = input_valid && input_ready;
wire [31:0] completed_chunk_size = {input_data, chunk_size_value[23:0]};

assign input_ready = state == HEADER || state == CHUNK_ID ||
    state == CHUNK_SIZE || state == CHUNK_DATA || state == CHUNK_PAD ||
    state == SAMPLE_LEFT0 || state == SAMPLE_LEFT1 ||
    state == SAMPLE_RIGHT0 || state == SAMPLE_RIGHT1 ||
    state == DRAIN || state == FAILED;

assign pcm_valid = state == SAMPLE_EMIT;
assign pcm_left = {sample_left_high, sample_left_low};
assign pcm_right = {sample_right_high, sample_right_low};
assign pcm_eof = pcm_valid && data_remaining == 32'd4;

task automatic fail(input logic [7:0] code);
begin
    format_error <= 1'b1;
    error_code <= code;
    state <= FAILED;
end
endtask

function automatic logic header_byte_matches(
    input logic [3:0] position,
    input logic [7:0] value
);
begin
    case (position)
        0: header_byte_matches = value == "R";
        1: header_byte_matches = value == "I";
        2: header_byte_matches = value == "F";
        3: header_byte_matches = value == "F";
        8: header_byte_matches = value == "W";
        9: header_byte_matches = value == "A";
        10: header_byte_matches = value == "V";
        11: header_byte_matches = value == "E";
        default: header_byte_matches = 1'b1;
    endcase
end
endfunction

always_ff @(posedge clk) begin
    if (reset) begin
        state <= HEADER;
        header_index <= 0;
        header_bad <= 1'b0;
        field_index <= 0;
        chunk_id <= 0;
        chunk_size_value <= 0;
        chunk_remaining <= 0;
        chunk_odd <= 1'b0;
        chunk_kind <= CHUNK_SKIP;
        chunk_position <= 0;
        data_remaining <= 0;
        sample_left_low <= 0;
        sample_left_high <= 0;
        sample_right_low <= 0;
        sample_right_high <= 0;
        fmt_size <= 0;
        fmt_tag <= 0;
        fmt_channels <= 0;
        fmt_rate <= 0;
        fmt_alignment <= 0;
        fmt_bits <= 0;
        format_valid <= 1'b0;
        metadata_valid <= 1'b0;
        sample_rate <= 0;
        total_samples <= 0;
        format_error <= 1'b0;
        error_code <= 0;
    end else begin
        // A decoded sample waiting on PCM backpressure needs no more input.
        // input_end stays asserted, so a truncated chunk still fails once the
        // emitted sample returns the parser to a byte-consuming state.
        if (input_end && state != DRAIN && state != FAILED && state != SAMPLE_EMIT)
            fail(8'h04); // Transport ended before the data chunk completed.

        case (state)
            HEADER: if (consume) begin
                if (!header_byte_matches(header_index, input_data))
                    header_bad <= 1'b1;
                if (header_index == 4'd11) begin
                    if (header_bad || !header_byte_matches(header_index, input_data))
                        fail(8'h01); // Not a RIFF/WAVE stream.
                    else begin
                        state <= CHUNK_ID;
                        field_index <= 0;
                    end
                end else
                    header_index <= header_index + 1'b1;
            end

            CHUNK_ID: if (consume) begin
                chunk_id <= {chunk_id[23:0], input_data};
                if (field_index == 2'd3) begin
                    state <= CHUNK_SIZE;
                    field_index <= 0;
                    chunk_size_value <= 0;
                end else
                    field_index <= field_index + 1'b1;
            end

            CHUNK_SIZE: if (consume) begin
                case (field_index)
                    0: chunk_size_value[7:0] <= input_data;
                    1: chunk_size_value[15:8] <= input_data;
                    2: chunk_size_value[23:16] <= input_data;
                    3: chunk_size_value[31:24] <= input_data;
                endcase

                if (field_index == 2'd3) begin
                    field_index <= 0;
                    chunk_remaining <= completed_chunk_size;
                    chunk_odd <= completed_chunk_size[0];
                    chunk_position <= 0;

                    if (chunk_id == 32'h666d7420) begin // "fmt "
                        fmt_size <= completed_chunk_size;
                        fmt_tag <= 0;
                        fmt_channels <= 0;
                        fmt_rate <= 0;
                        fmt_alignment <= 0;
                        fmt_bits <= 0;
                        chunk_kind <= CHUNK_FMT;
                        state <= completed_chunk_size == 0 ? VALIDATE_FMT : CHUNK_DATA;
                    end else if (chunk_id == 32'h64617461) begin // "data"
                        if (!format_valid)
                            fail(8'h02); // Missing or unsupported fmt chunk.
                        else if (completed_chunk_size[1:0] != 0)
                            fail(8'h03); // Partial stereo PCM sample.
                        else begin
                            data_remaining <= completed_chunk_size;
                            total_samples <= completed_chunk_size >> 2;
                            metadata_valid <= 1'b1;
                            state <= completed_chunk_size == 0 ? DRAIN : SAMPLE_LEFT0;
                        end
                    end else begin
                        chunk_kind <= CHUNK_SKIP;
                        state <= completed_chunk_size == 0 ? CHUNK_ID : CHUNK_DATA;
                    end
                end else
                    field_index <= field_index + 1'b1;
            end

            CHUNK_DATA: if (consume) begin
                if (chunk_kind == CHUNK_FMT) begin
                    case (chunk_position)
                        0: fmt_tag[7:0] <= input_data;
                        1: fmt_tag[15:8] <= input_data;
                        2: fmt_channels[7:0] <= input_data;
                        3: fmt_channels[15:8] <= input_data;
                        4: fmt_rate[7:0] <= input_data;
                        5: fmt_rate[15:8] <= input_data;
                        6: fmt_rate[23:16] <= input_data;
                        7: fmt_rate[31:24] <= input_data;
                        12: fmt_alignment[7:0] <= input_data;
                        13: fmt_alignment[15:8] <= input_data;
                        14: fmt_bits[7:0] <= input_data;
                        15: fmt_bits[15:8] <= input_data;
                        default: ;
                    endcase
                end
                chunk_position <= chunk_position + 1'b1;
                chunk_remaining <= chunk_remaining - 1'b1;
                if (chunk_remaining == 1) begin
                    if (chunk_kind == CHUNK_FMT)
                        state <= VALIDATE_FMT;
                    else
                        state <= chunk_odd ? CHUNK_PAD : CHUNK_ID;
                end
            end

            VALIDATE_FMT: begin
                sample_rate <= fmt_rate;
                if (fmt_size >= 16 && fmt_tag == 1 && fmt_channels == 2 &&
                        (fmt_rate == 44100 || fmt_rate == 48000) &&
                        fmt_alignment == 4 && fmt_bits == 16) begin
                    format_valid <= 1'b1;
                    state <= chunk_odd ? CHUNK_PAD : CHUNK_ID;
                end else
                    fail(8'h02);
            end

            CHUNK_PAD: if (consume) begin
                chunk_odd <= 1'b0;
                state <= CHUNK_ID;
                field_index <= 0;
            end

            SAMPLE_LEFT0: if (consume) begin
                sample_left_low <= input_data;
                state <= SAMPLE_LEFT1;
            end
            SAMPLE_LEFT1: if (consume) begin
                sample_left_high <= input_data;
                state <= SAMPLE_RIGHT0;
            end
            SAMPLE_RIGHT0: if (consume) begin
                sample_right_low <= input_data;
                state <= SAMPLE_RIGHT1;
            end
            SAMPLE_RIGHT1: if (consume) begin
                sample_right_high <= input_data;
                state <= SAMPLE_EMIT;
            end
            SAMPLE_EMIT: if (pcm_ready) begin
                data_remaining <= data_remaining - 32'd4;
                state <= data_remaining == 32'd4 ? DRAIN : SAMPLE_LEFT0;
            end

            DRAIN: ;
            FAILED: ;
            default: fail(8'h01);
        endcase
    end
end

endmodule
