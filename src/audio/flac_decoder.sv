// Tang-native RFC 9639 streamable-subset FLAC decoder. The implemented audio
// profile is signed 16-bit stereo at 44.1/48 kHz. Two 4,608-sample BSRAM banks
// keep decoded frames provisional until their CRC-16 validates.

module flac_decoder #(
    parameter integer MAX_BLOCK_SIZE = 4608,
    parameter integer ADDRESS_WIDTH = 13
) (
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
    output logic        [35:0] total_samples,
    output logic               format_error,
    output logic         [7:0] error_code
);

localparam logic [5:0]
    STATE_MAGIC_START       = 6'd0,
    STATE_READ_BITS         = 6'd1,
    STATE_MAGIC_CHECK       = 6'd2,
    STATE_META_HEADER_START = 6'd3,
    STATE_META_HEADER_CHECK = 6'd4,
    STATE_INFO_BLOCKS       = 6'd5,
    STATE_INFO_FIELDS_START = 6'd6,
    STATE_INFO_FIELDS       = 6'd7,
    STATE_SKIP_BYTES        = 6'd8,
    STATE_META_FINISH       = 6'd9,
    STATE_WAIT_FRAME        = 6'd10,
    STATE_FRAME_START       = 6'd11,
    STATE_SYNC_CHECK        = 6'd12,
    STATE_FORMAT_START      = 6'd13,
    STATE_FORMAT_CHECK      = 6'd14,
    STATE_NUMBER_START      = 6'd15,
    STATE_NUMBER_FIRST      = 6'd16,
    STATE_NUMBER_MORE       = 6'd17,
    STATE_NUMBER_CHECK      = 6'd18,
    STATE_BLOCK_EXTRA       = 6'd19,
    STATE_RATE_START        = 6'd20,
    STATE_RATE_CHECK        = 6'd21,
    STATE_HEADER_CRC_START  = 6'd22,
    STATE_HEADER_CRC_CHECK  = 6'd23,
    STATE_SUBFRAME_START    = 6'd24,
    STATE_SUBFRAME          = 6'd25,
    STATE_PADDING           = 6'd26,
    STATE_FRAME_CRC_START   = 6'd27,
    STATE_FRAME_CRC_CHECK   = 6'd28,
    STATE_FAILED            = 6'd29,
    STATE_FINISHED          = 6'd30,
    STATE_RATE_DECODE       = 6'd31;

localparam logic [7:0]
    ERROR_PROFILE   = 8'h21,
    ERROR_HEADER    = 8'h22,
    ERROR_CRC       = 8'h23,
    ERROR_SUBFRAME  = 8'h24,
    ERROR_TRUNCATED = 8'h25,
    ERROR_INTERNAL  = 8'h26;
localparam logic [15:0] MAX_BLOCK_SIZE_16 = 16'(MAX_BLOCK_SIZE);

logic [5:0] state;
logic [5:0] read_return_state;
logic [5:0] skip_return_state;
logic [6:0] bits_left;
logic [63:0] bit_field;
logic [63:0] bit_accumulator;
logic [7:0] byte_buffer;
logic [3:0] byte_bits;
logic [23:0] skip_remaining;
logic end_seen;

logic info_seen;
logic metadata_last;
logic [15:0] min_block_size;
logic [15:0] max_block_size;

logic frame_crc_active;
logic header_crc_active;
logic [15:0] frame_crc;
logic [7:0] header_crc;
logic variable_block;
logic blocking_known;
logic blocking_mode;
logic short_frame;
logic [12:0] fixed_frame_size;
logic [3:0] block_code;
logic [3:0] rate_code;
logic [3:0] channel_assignment;
logic [12:0] frame_size;
logic [35:0] frame_number;
logic [35:0] frame_position;
logic [36:0] frame_end_position;
logic [35:0] coded_number;
logic [35:0] coded_number_minimum;
logic [2:0] coded_continuations;

logic sf_reset;
logic sf_start;
logic sf_bit_ready;
logic sf_sample_valid;
logic sf_sample_ready;
logic signed [16:0] sf_sample_data;
logic sf_done;
logic sf_error;
logic sample_channel;
logic [ADDRESS_WIDTH-1:0] write_index;
logic write_bank;

logic [1:0] bank_full;
logic [12:0] bank_size [0:1];
logic [3:0] bank_assignment [0:1];
logic [1:0] bank_eof;
logic last_committed_valid;
logic last_committed_bank;

logic read_bank;
logic output_active;
logic output_bank;
logic [ADDRESS_WIDTH-1:0] output_index;
logic [ADDRESS_WIDTH-1:0] read_address;
logic [1:0] read_delay;
logic pcm_valid_reg;
logic signed [15:0] pcm_left_reg;
logic signed [15:0] pcm_right_reg;
logic decoded_sample_pending;
logic decoded_sample_fits;

logic signed [16:0] bank0_read_channel0;
logic signed [16:0] bank0_read_channel1;
logic signed [16:0] bank1_read_channel0;
logic signed [16:0] bank1_read_channel1;

wire parser_bit_demand = state == STATE_READ_BITS;
wire subframe_bit_demand = state == STATE_SUBFRAME && sf_bit_ready;
wire padding_bit_demand = state == STATE_PADDING && byte_bits != 0;
wire consume_bit = byte_bits != 0 &&
    (parser_bit_demand || subframe_bit_demand || padding_bit_demand);
wire input_transfer = input_valid && input_ready;
wire sf_bit_valid = state == STATE_SUBFRAME && byte_bits != 0;
wire sf_bit_end = end_seen && !input_valid && byte_bits == 0;
wire sf_sample_transfer = sf_sample_valid && sf_sample_ready;
wire [36:0] next_frame_position =
    {1'b0, frame_position} + {{24{1'b0}}, frame_size};
wire [16:0] explicit_block_size = {1'b0, bit_field[15:0]} + 17'd1;

wire frame_write_enable = state == STATE_SUBFRAME && sf_sample_transfer;
wire bank0_write_enable = frame_write_enable && !write_bank;
wire bank1_write_enable = frame_write_enable && write_bank;

wire signed [16:0] selected_raw0 = output_bank ?
    bank1_read_channel0 : bank0_read_channel0;
wire signed [16:0] selected_raw1 = output_bank ?
    bank1_read_channel1 : bank0_read_channel1;
logic signed [17:0] stereo_left_wide;
logic signed [17:0] stereo_right_wide;
logic signed [17:0] mid_expanded;
logic stereo_fits;

assign sf_reset = reset || state == STATE_FAILED;
assign sf_start = state == STATE_SUBFRAME_START;
assign sf_sample_ready = 1'b1;

assign input_ready = !reset && !format_error &&
    (state == STATE_SKIP_BYTES ||
     (byte_bits == 0 && (parser_bit_demand || subframe_bit_demand)));

assign pcm_valid = pcm_valid_reg;
assign pcm_left = pcm_left_reg;
assign pcm_right = pcm_right_reg;
assign pcm_eof = pcm_valid_reg && bank_eof[output_bank] &&
    output_index + 1'b1 == bank_size[output_bank];

always_comb begin
    stereo_left_wide = 0;
    stereo_right_wide = 0;
    mid_expanded = 0;

    case (bank_assignment[output_bank])
        4'd1: begin
            stereo_left_wide = $signed({selected_raw0[16], selected_raw0});
            stereo_right_wide = $signed({selected_raw1[16], selected_raw1});
        end
        4'd8: begin
            stereo_left_wide = $signed({selected_raw0[16], selected_raw0});
            stereo_right_wide = $signed({selected_raw0[16], selected_raw0}) -
                $signed({selected_raw1[16], selected_raw1});
        end
        4'd9: begin
            stereo_left_wide = $signed({selected_raw0[16], selected_raw0}) +
                $signed({selected_raw1[16], selected_raw1});
            stereo_right_wide = $signed({selected_raw1[16], selected_raw1});
        end
        4'd10: begin
            mid_expanded =
                ($signed({selected_raw0[16], selected_raw0}) <<< 1) |
                $signed({17'b0, selected_raw1[0]});
            stereo_left_wide = (mid_expanded + selected_raw1) >>> 1;
            stereo_right_wide = (mid_expanded - selected_raw1) >>> 1;
        end
        default: ;
    endcase

    stereo_fits =
        stereo_left_wide[17:15] == {3{stereo_left_wide[15]}} &&
        stereo_right_wide[17:15] == {3{stereo_right_wide[15]}};
end

function automatic logic [7:0] next_crc8(
    input logic [7:0] previous,
    input logic [7:0] value
);
    logic [7:0] crc;
begin
    crc = previous ^ value;
    for (integer i = 0; i < 8; i = i + 1)
        crc = crc[7] ? (crc << 1) ^ 8'h07 : crc << 1;
    next_crc8 = crc;
end
endfunction

function automatic logic [15:0] next_crc16(
    input logic [15:0] previous,
    input logic [7:0] value
);
    logic [15:0] crc;
begin
    crc = previous ^ {value, 8'b0};
    for (integer i = 0; i < 8; i = i + 1)
        crc = crc[15] ? (crc << 1) ^ 16'h8005 : crc << 1;
    next_crc16 = crc;
end
endfunction

function automatic logic [12:0] coded_block_size(input logic [3:0] code);
begin
    if (code == 1)
        coded_block_size = 13'd192;
    else if (code >= 2 && code <= 5)
        coded_block_size = 13'd576 << (code - 2);
    else if (code >= 8)
        coded_block_size = 13'd256 << (code - 8);
    else
        coded_block_size = 0;
end
endfunction

task automatic read_bits(input logic [6:0] count, input logic [5:0] next_state);
begin
    bits_left <= count;
    bit_accumulator <= 0;
    read_return_state <= next_state;
    if (count == 0) begin
        bit_field <= 0;
        state <= next_state;
    end else
        state <= STATE_READ_BITS;
end
endtask

task automatic skip_bytes(input logic [23:0] count, input logic [5:0] next_state);
begin
    skip_remaining <= count;
    skip_return_state <= next_state;
    state <= count == 0 ? next_state : STATE_SKIP_BYTES;
end
endtask

task automatic fail(input logic [7:0] code);
begin
    format_error <= 1'b1;
    error_code <= code;
    state <= STATE_FAILED;
end
endtask

flac_subframe_decoder subframe_decoder (
    .clk(clk), .reset(sf_reset), .start(sf_start),
    .block_size(frame_size),
    .channel_bits(((channel_assignment == 8 || channel_assignment == 10) && sample_channel) ||
        (channel_assignment == 9 && !sample_channel) ? 5'd17 : 5'd16),
    .bit_valid(sf_bit_valid), .bit_data(byte_buffer[7]),
    .bit_end(sf_bit_end), .bit_ready(sf_bit_ready),
    .sample_valid(sf_sample_valid), .sample_ready(sf_sample_ready),
    .sample_data(sf_sample_data), .done(sf_done), .error(sf_error)
);

flac_frame_ram #(
    .MAX_BLOCK_SIZE(MAX_BLOCK_SIZE), .ADDRESS_WIDTH(ADDRESS_WIDTH)
) frame_bank0 (
    .clk(clk), .write_enable(bank0_write_enable),
    .write_channel(sample_channel), .write_address(write_index),
    .write_data(sf_sample_data), .read_address(read_address),
    .read_channel0(bank0_read_channel0), .read_channel1(bank0_read_channel1)
);

flac_frame_ram #(
    .MAX_BLOCK_SIZE(MAX_BLOCK_SIZE), .ADDRESS_WIDTH(ADDRESS_WIDTH)
) frame_bank1 (
    .clk(clk), .write_enable(bank1_write_enable),
    .write_channel(sample_channel), .write_address(write_index),
    .write_data(sf_sample_data), .read_address(read_address),
    .read_channel0(bank1_read_channel0), .read_channel1(bank1_read_channel1)
);

always_ff @(posedge clk) begin
    if (reset) begin
        state <= STATE_MAGIC_START;
        read_return_state <= STATE_MAGIC_START;
        skip_return_state <= STATE_MAGIC_START;
        bits_left <= 0;
        bit_field <= 0;
        bit_accumulator <= 0;
        byte_buffer <= 0;
        byte_bits <= 0;
        skip_remaining <= 0;
        end_seen <= 1'b0;
        info_seen <= 1'b0;
        metadata_last <= 1'b0;
        min_block_size <= 0;
        max_block_size <= 0;
        frame_crc_active <= 1'b0;
        header_crc_active <= 1'b0;
        frame_crc <= 0;
        header_crc <= 0;
        variable_block <= 1'b0;
        blocking_known <= 1'b0;
        blocking_mode <= 1'b0;
        short_frame <= 1'b0;
        fixed_frame_size <= 0;
        block_code <= 0;
        rate_code <= 0;
        channel_assignment <= 0;
        frame_size <= 0;
        frame_number <= 0;
        frame_position <= 0;
        frame_end_position <= 0;
        coded_number <= 0;
        coded_number_minimum <= 0;
        coded_continuations <= 0;
        sample_channel <= 1'b0;
        write_index <= 0;
        write_bank <= 1'b0;
        bank_full <= 0;
        bank_size[0] <= 0;
        bank_size[1] <= 0;
        bank_assignment[0] <= 0;
        bank_assignment[1] <= 0;
        bank_eof <= 0;
        last_committed_valid <= 1'b0;
        last_committed_bank <= 1'b0;
        read_bank <= 1'b0;
        output_active <= 1'b0;
        output_bank <= 1'b0;
        output_index <= 0;
        read_address <= 0;
        read_delay <= 0;
        pcm_valid_reg <= 1'b0;
        pcm_left_reg <= 0;
        pcm_right_reg <= 0;
        decoded_sample_pending <= 1'b0;
        decoded_sample_fits <= 1'b0;
        format_valid <= 1'b0;
        metadata_valid <= 1'b0;
        sample_rate <= 0;
        total_samples <= 0;
        format_error <= 1'b0;
        error_code <= 0;
    end else begin
        if (input_end)
            end_seen <= 1'b1;

        if (input_transfer && state != STATE_SKIP_BYTES) begin
            byte_buffer <= input_data;
            byte_bits <= 4'd8;
            if (frame_crc_active)
                frame_crc <= next_crc16(frame_crc, input_data);
            if (header_crc_active)
                header_crc <= next_crc8(header_crc, input_data);
        end else if (consume_bit) begin
            byte_buffer <= {byte_buffer[6:0], 1'b0};
            byte_bits <= byte_bits - 1'b1;
        end

        if (!output_active && bank_full[read_bank]) begin
            output_active <= 1'b1;
            output_bank <= read_bank;
            output_index <= 0;
            read_address <= 0;
            read_delay <= 2;
            pcm_valid_reg <= 1'b0;
            decoded_sample_pending <= 1'b0;
        end else if (output_active) begin
            if (!pcm_valid_reg) begin
                if (read_delay != 0)
                    read_delay <= read_delay - 1'b1;
                else if (!decoded_sample_pending) begin
                    pcm_left_reg <= stereo_left_wide[15:0];
                    pcm_right_reg <= stereo_right_wide[15:0];
                    decoded_sample_fits <= stereo_fits;
                    decoded_sample_pending <= 1'b1;
                end else if (!decoded_sample_fits) begin
                    decoded_sample_pending <= 1'b0;
                    fail(ERROR_INTERNAL);
                end else begin
                    pcm_valid_reg <= 1'b1;
                    decoded_sample_pending <= 1'b0;
                end
            end else if (pcm_ready) begin
                pcm_valid_reg <= 1'b0;
                if (output_index + 1'b1 == bank_size[output_bank]) begin
                    bank_full[output_bank] <= 1'b0;
                    bank_eof[output_bank] <= 1'b0;
                    output_active <= 1'b0;
                    decoded_sample_pending <= 1'b0;
                    read_bank <= !read_bank;
                end else begin
                    output_index <= output_index + 1'b1;
                    read_address <= output_index + 1'b1;
                    read_delay <= 2;
                end
            end
        end

        if (sf_sample_transfer)
            write_index <= write_index + 1'b1;

        case (state)
            STATE_MAGIC_START: read_bits(7'd32, STATE_MAGIC_CHECK);

            STATE_READ_BITS: begin
                if (consume_bit) begin
                    bit_accumulator <= {bit_accumulator[62:0], byte_buffer[7]};
                    bits_left <= bits_left - 1'b1;
                    if (bits_left == 1) begin
                        bit_field <= {bit_accumulator[62:0], byte_buffer[7]};
                        state <= read_return_state;
                    end
                end else if (end_seen && !input_valid && byte_bits == 0)
                    fail(ERROR_TRUNCATED);
            end

            STATE_MAGIC_CHECK: begin
                if (bit_field[31:0] != 32'h664c_6143)
                    fail(ERROR_PROFILE);
                else
                    state <= STATE_META_HEADER_START;
            end

            STATE_META_HEADER_START:
                read_bits(7'd32, STATE_META_HEADER_CHECK);

            STATE_META_HEADER_CHECK: begin
                metadata_last <= bit_field[31];
                if (bit_field[30:24] == 7'd127)
                    fail(ERROR_PROFILE);
                else if (!info_seen) begin
                    if (bit_field[30:24] != 0 || bit_field[23:0] != 24'd34)
                        fail(ERROR_PROFILE);
                    else begin
                        info_seen <= 1'b1;
                        read_bits(7'd32, STATE_INFO_BLOCKS);
                    end
                end else if (bit_field[30:24] == 0)
                    fail(ERROR_PROFILE);
                else
                    skip_bytes(bit_field[23:0], STATE_META_FINISH);
            end

            STATE_INFO_BLOCKS: begin
                min_block_size <= bit_field[31:16];
                max_block_size <= bit_field[15:0];
                if (bit_field[31:16] < 16 || bit_field[15:0] < bit_field[31:16] ||
                        bit_field[15:0] > MAX_BLOCK_SIZE_16)
                    fail(ERROR_PROFILE);
                else
                    skip_bytes(24'd6, STATE_INFO_FIELDS_START);
            end

            STATE_INFO_FIELDS_START:
                read_bits(7'd64, STATE_INFO_FIELDS);

            STATE_INFO_FIELDS: begin
                sample_rate <= {12'b0, bit_field[63:44]};
                total_samples <= bit_field[35:0];
                if ((bit_field[63:44] != 20'd44100 &&
                        bit_field[63:44] != 20'd48000) ||
                        bit_field[43:41] != 3'd1 || bit_field[40:36] != 5'd15)
                    fail(ERROR_PROFILE);
                else begin
                    format_valid <= 1'b1;
                    metadata_valid <= 1'b1;
                    skip_bytes(24'd16, STATE_META_FINISH);
                end
            end

            STATE_SKIP_BYTES: begin
                if (input_transfer) begin
                    skip_remaining <= skip_remaining - 1'b1;
                    if (skip_remaining == 1)
                        state <= skip_return_state;
                end else if (end_seen)
                    fail(ERROR_TRUNCATED);
            end

            STATE_META_FINISH: begin
                if (metadata_last)
                    state <= STATE_WAIT_FRAME;
                else
                    state <= STATE_META_HEADER_START;
            end

            STATE_WAIT_FRAME: begin
                frame_crc_active <= 1'b0;
                header_crc_active <= 1'b0;
                if (end_seen && !input_valid && byte_bits == 0) begin
                    if (total_samples != 0 && frame_position != total_samples)
                        fail(ERROR_TRUNCATED);
                    else begin
                        if (last_committed_valid)
                            bank_eof[last_committed_bank] <= 1'b1;
                        state <= STATE_FINISHED;
                    end
                end else if (input_valid && !bank_full[write_bank]) begin
                    if (short_frame)
                        fail(ERROR_HEADER);
                    else
                        state <= STATE_FRAME_START;
                end
            end

            STATE_FRAME_START: begin
                frame_crc_active <= 1'b1;
                header_crc_active <= 1'b1;
                frame_crc <= 0;
                header_crc <= 0;
                read_bits(7'd16, STATE_SYNC_CHECK);
            end

            STATE_SYNC_CHECK: begin
                if (bit_field[15:1] != 15'h7ffc ||
                        (blocking_known && bit_field[0] != blocking_mode))
                    fail(ERROR_HEADER);
                else begin
                    variable_block <= bit_field[0];
                    state <= STATE_FORMAT_START;
                end
            end

            STATE_FORMAT_START:
                read_bits(7'd16, STATE_FORMAT_CHECK);

            STATE_FORMAT_CHECK: begin
                block_code <= bit_field[15:12];
                rate_code <= bit_field[11:8];
                channel_assignment <= bit_field[7:4];
                frame_size <= coded_block_size(bit_field[15:12]);
                if (bit_field[0] || bit_field[3:1] != 3'b100 ||
                        !(bit_field[7:4] == 1 || bit_field[7:4] == 8 ||
                          bit_field[7:4] == 9 || bit_field[7:4] == 10) ||
                        bit_field[15:12] == 0 ||
                        !(bit_field[11:8] == 9 || bit_field[11:8] == 10 ||
                          bit_field[11:8] == 12 || bit_field[11:8] == 13 ||
                          bit_field[11:8] == 14))
                    fail(ERROR_PROFILE);
                else
                    state <= STATE_NUMBER_START;
            end

            STATE_NUMBER_START:
                read_bits(7'd8, STATE_NUMBER_FIRST);

            STATE_NUMBER_FIRST: begin
                if (!bit_field[7]) begin
                    coded_number <= {29'b0, bit_field[6:0]};
                    coded_number_minimum <= 0;
                    coded_continuations <= 0;
                    state <= STATE_NUMBER_CHECK;
                end else if (bit_field[7:5] == 3'b110) begin
                    coded_number <= {31'b0, bit_field[4:0]};
                    coded_number_minimum <= 36'd128;
                    coded_continuations <= 1;
                    read_bits(7'd8, STATE_NUMBER_MORE);
                end else if (bit_field[7:4] == 4'b1110) begin
                    coded_number <= {32'b0, bit_field[3:0]};
                    coded_number_minimum <= 36'd2048;
                    coded_continuations <= 2;
                    read_bits(7'd8, STATE_NUMBER_MORE);
                end else if (bit_field[7:3] == 5'b11110) begin
                    coded_number <= {33'b0, bit_field[2:0]};
                    coded_number_minimum <= 36'd65536;
                    coded_continuations <= 3;
                    read_bits(7'd8, STATE_NUMBER_MORE);
                end else if (bit_field[7:2] == 6'b111110) begin
                    coded_number <= {34'b0, bit_field[1:0]};
                    coded_number_minimum <= 36'd2097152;
                    coded_continuations <= 4;
                    read_bits(7'd8, STATE_NUMBER_MORE);
                end else if (bit_field[7:1] == 7'b1111110) begin
                    coded_number <= {35'b0, bit_field[0]};
                    coded_number_minimum <= 36'd67108864;
                    coded_continuations <= 5;
                    read_bits(7'd8, STATE_NUMBER_MORE);
                end else if (bit_field[7:0] == 8'hfe) begin
                    coded_number <= 0;
                    coded_number_minimum <= 36'h080000000;
                    coded_continuations <= 6;
                    read_bits(7'd8, STATE_NUMBER_MORE);
                end else
                    fail(ERROR_HEADER);
            end

            STATE_NUMBER_MORE: begin
                if (bit_field[7:6] != 2'b10)
                    fail(ERROR_HEADER);
                else begin
                    coded_number <= {coded_number[29:0], bit_field[5:0]};
                    coded_continuations <= coded_continuations - 1'b1;
                    if (coded_continuations == 1)
                        state <= STATE_NUMBER_CHECK;
                    else
                        read_bits(7'd8, STATE_NUMBER_MORE);
                end
            end

            STATE_NUMBER_CHECK: begin
                if (coded_number < coded_number_minimum ||
                        (!variable_block && coded_number[35:31] != 0) ||
                        (variable_block ? coded_number != frame_position :
                            coded_number != frame_number))
                    fail(ERROR_HEADER);
                else if (block_code == 6)
                    read_bits(7'd8, STATE_BLOCK_EXTRA);
                else if (block_code == 7)
                    read_bits(7'd16, STATE_BLOCK_EXTRA);
                else
                    state <= STATE_RATE_START;
            end

            STATE_BLOCK_EXTRA: begin
                if ((block_code == 7 && bit_field[15:0] == 16'hffff) ||
                        explicit_block_size > {1'b0, MAX_BLOCK_SIZE_16})
                    fail(ERROR_PROFILE);
                else begin
                    frame_size <= explicit_block_size[12:0];
                    state <= STATE_RATE_START;
                end
            end

            STATE_RATE_START: begin
                if (frame_size == 0 || {3'b0, frame_size} > max_block_size ||
                        {3'b0, frame_size} > MAX_BLOCK_SIZE_16 ||
                        (blocking_known && !variable_block &&
                            frame_size > fixed_frame_size))
                    fail(ERROR_PROFILE);
                else
                    state <= STATE_RATE_DECODE;
            end

            STATE_RATE_DECODE: begin
                if (rate_code >= 12)
                    read_bits(rate_code == 12 ? 7'd8 : 7'd16, STATE_RATE_CHECK);
                else if ((rate_code == 9 && sample_rate == 44100) ||
                        (rate_code == 10 && sample_rate == 48000))
                    state <= STATE_HEADER_CRC_START;
                else
                    fail(ERROR_PROFILE);
            end

            STATE_RATE_CHECK: begin
                if (!((rate_code == 12 && sample_rate == 48000 &&
                            bit_field[31:0] == 32'd48) ||
                      (rate_code == 13 && bit_field[31:0] == sample_rate) ||
                      (rate_code == 14 && bit_field[31:0] * 32'd10 == sample_rate)))
                    fail(ERROR_PROFILE);
                else
                    state <= STATE_HEADER_CRC_START;
            end

            STATE_HEADER_CRC_START:
                read_bits(7'd8, STATE_HEADER_CRC_CHECK);

            STATE_HEADER_CRC_CHECK: begin
                if (header_crc != 0)
                    fail(ERROR_CRC);
                else begin
                    header_crc_active <= 1'b0;
                    if (!blocking_known) begin
                        blocking_known <= 1'b1;
                        blocking_mode <= variable_block;
                        fixed_frame_size <= frame_size;
                    end
                    short_frame <= {3'b0, frame_size} < min_block_size ||
                        (blocking_known && !variable_block &&
                            frame_size != fixed_frame_size);
                    frame_end_position <= next_frame_position;
                    sample_channel <= 1'b0;
                    write_index <= 0;
                    state <= STATE_SUBFRAME_START;
                end
            end

            STATE_SUBFRAME_START:
                state <= STATE_SUBFRAME;

            STATE_SUBFRAME: begin
                if (sf_error)
                    fail(ERROR_SUBFRAME);
                else if (sf_done) begin
                    if (!sample_channel) begin
                        sample_channel <= 1'b1;
                        write_index <= 0;
                        state <= STATE_SUBFRAME_START;
                    end else
                        state <= STATE_PADDING;
                end
            end

            STATE_PADDING: begin
                if (byte_bits == 0)
                    state <= STATE_FRAME_CRC_START;
                else if (consume_bit && byte_buffer[7])
                    fail(ERROR_HEADER);
            end

            STATE_FRAME_CRC_START:
                read_bits(7'd16, STATE_FRAME_CRC_CHECK);

            STATE_FRAME_CRC_CHECK: begin
                if (frame_crc != 0)
                    fail(ERROR_CRC);
                else if (frame_end_position[36] ||
                        (total_samples != 0 &&
                            frame_end_position > {1'b0, total_samples}))
                    fail(ERROR_HEADER);
                else begin
                    frame_crc_active <= 1'b0;
                    bank_full[write_bank] <= 1'b1;
                    bank_size[write_bank] <= frame_size;
                    bank_assignment[write_bank] <= channel_assignment;
                    bank_eof[write_bank] <= total_samples != 0 &&
                        frame_end_position[35:0] == total_samples;
                    last_committed_valid <= 1'b1;
                    last_committed_bank <= write_bank;
                    write_bank <= !write_bank;
                    frame_position <= frame_end_position[35:0];
                    frame_number <= frame_number + 1'b1;
                    state <= STATE_WAIT_FRAME;
                end
            end

            STATE_FINISHED: ;
            STATE_FAILED: ;
            default: fail(ERROR_INTERNAL);
        endcase
    end
end

endmodule
