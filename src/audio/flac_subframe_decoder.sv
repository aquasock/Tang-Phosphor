// RFC 9639 streamable-subset subframe decoder for the Tang-Phosphor
// 16-bit stereo profile. The side channel may be 17 bits. Samples remain
// provisional until the outer decoder validates the frame CRC.

module flac_subframe_decoder (
    input  logic               clk,
    input  logic               reset,
    input  logic               start,
    input  logic        [12:0] block_size,
    input  logic         [4:0] channel_bits,
    input  logic               bit_valid,
    input  logic               bit_data,
    input  logic               bit_end,
    output logic               bit_ready,
    output logic               sample_valid,
    input  logic               sample_ready,
    output logic signed [16:0] sample_data,
    output logic               done,
    output logic               error
);

localparam logic [4:0]
    STATE_IDLE          = 5'd0,
    STATE_READ          = 5'd1,
    STATE_HEADER        = 5'd2,
    STATE_WASTED        = 5'd3,
    STATE_TYPE          = 5'd4,
    STATE_VALUE         = 5'd5,
    STATE_EMIT          = 5'd6,
    STATE_LPC_PRECISION = 5'd7,
    STATE_LPC_SHIFT     = 5'd8,
    STATE_LPC_COEFF     = 5'd9,
    STATE_RICE_METHOD   = 5'd10,
    STATE_PART_ORDER    = 5'd11,
    STATE_RICE_PARAM    = 5'd12,
    STATE_ESCAPE_WIDTH  = 5'd13,
    STATE_RESIDUAL      = 5'd14,
    STATE_UNARY         = 5'd15,
    STATE_REMAINDER     = 5'd16,
    STATE_ESCAPE_VALUE  = 5'd17,
    STATE_MAC_START     = 5'd18,
    STATE_MAC_CAPTURE   = 5'd19,
    STATE_MAC_ACCUM     = 5'd20,
    STATE_MAC_SHIFT     = 5'd21,
    STATE_MAC_FINISH    = 5'd22,
    STATE_RESTORE       = 5'd23,
    STATE_FAILED        = 5'd24,
    STATE_RESTORE_CHECK = 5'd25,
    STATE_ADVANCE       = 5'd26,
    STATE_ADVANCE2      = 5'd27;

localparam logic [1:0]
    KIND_CONSTANT  = 2'd0,
    KIND_VERBATIM  = 2'd1,
    KIND_PREDICTOR = 2'd2;

// Post-emit advance decision, computed in one registered step and applied in
// the next (see STATE_ADVANCE/STATE_ADVANCE2), so the bit reader's setup does
// not share one combinational path with the sample-index and residual-advance
// comparisons.
localparam logic [2:0]
    ADVANCE_DONE     = 3'd0,
    ADVANCE_CONSTANT = 3'd1,
    ADVANCE_VALUE    = 3'd2,
    ADVANCE_LPC      = 3'd3,
    ADVANCE_RICE     = 3'd4,
    ADVANCE_RESIDUAL = 3'd5;

logic [2:0] advance_kind;

logic [4:0] state;
logic [4:0] return_state;
logic [5:0] bits_left;
logic [31:0] bit_field;
logic [31:0] bit_accumulator;

logic [1:0] subframe_kind;
logic [5:0] subframe_type;
logic [3:0] predictor_order;
logic [4:0] nominal_bits;
logic [4:0] coded_bits;
logic [4:0] wasted_bits;
logic [12:0] sample_index;
logic [12:0] partition_size;
logic [12:0] residual_left;
logic [8:0] partition_count;
logic [8:0] partition_index;
logic rice_method;
logic [4:0] rice_parameter;
logic [31:0] rice_quotient_limit;
logic rice_escape;
logic [4:0] escape_width;
logic [31:0] unary_quotient;
logic signed [31:0] residual;
logic signed [47:0] reconstructed_sample;
logic signed [16:0] restored_sample;
logic restored_sample_fits;
logic signed [63:0] restored_wide_q;

logic [3:0] coefficient_precision;
logic [3:0] coefficient_index;
logic signed [5:0] prediction_shift;
logic signed [15:0] coefficients [0:11];
logic signed [16:0] history [0:15];
logic [3:0] history_pointer;
logic [3:0] mac_tap;
logic signed [47:0] mac_accumulator;
logic signed [47:0] mac_product_reg;
logic signed [47:0] shifted_prediction_reg;

wire bit_transfer = bit_valid && bit_ready;
wire sample_transfer = sample_valid && sample_ready;
wire [31:0] folded_residual = (unary_quotient << rice_parameter) | bit_field;
wire signed [47:0] mac_product =
    $signed(history[(history_pointer - 1'b1 - mac_tap) & 4'hf]) *
    $signed(coefficients[mac_tap]);
wire signed [47:0] shifted_prediction = prediction_shift < 0 ?
    $signed(mac_accumulator) <<< -prediction_shift :
    $signed(mac_accumulator) >>> prediction_shift;
wire signed [63:0] restored_wide =
    $signed({{16{reconstructed_sample[47]}}, reconstructed_sample}) <<< wasted_bits;
// The wasted-bits shift and the range check occupy separate cycles.
wire restored_fits = nominal_bits == 5'd17 ?
    restored_wide_q[63:16] == {48{restored_wide_q[16]}} :
    restored_wide_q[63:15] == {49{restored_wide_q[15]}};
wire [12:0] next_partition_size = block_size >> bit_field[3:0];
wire [12:0] predictor_order_wide = {9'b0, predictor_order};
wire signed [31:0] sign_extended_value =
    sign_extend_field(bit_field, {1'b0, coded_bits});

assign bit_ready = state == STATE_READ || state == STATE_WASTED ||
    state == STATE_UNARY;
assign sample_valid = state == STATE_EMIT && restored_sample_fits && !error;
assign sample_data = restored_sample;

function automatic logic signed [31:0] sign_extend_field(
    input logic [31:0] value,
    input logic [5:0] width
);
begin
    case (width)
        0:  sign_extend_field = 32'sd0;
        1:  sign_extend_field = {{31{value[0]}}, value[0:0]};
        2:  sign_extend_field = {{30{value[1]}}, value[1:0]};
        3:  sign_extend_field = {{29{value[2]}}, value[2:0]};
        4:  sign_extend_field = {{28{value[3]}}, value[3:0]};
        5:  sign_extend_field = {{27{value[4]}}, value[4:0]};
        6:  sign_extend_field = {{26{value[5]}}, value[5:0]};
        7:  sign_extend_field = {{25{value[6]}}, value[6:0]};
        8:  sign_extend_field = {{24{value[7]}}, value[7:0]};
        9:  sign_extend_field = {{23{value[8]}}, value[8:0]};
        10: sign_extend_field = {{22{value[9]}}, value[9:0]};
        11: sign_extend_field = {{21{value[10]}}, value[10:0]};
        12: sign_extend_field = {{20{value[11]}}, value[11:0]};
        13: sign_extend_field = {{19{value[12]}}, value[12:0]};
        14: sign_extend_field = {{18{value[13]}}, value[13:0]};
        15: sign_extend_field = {{17{value[14]}}, value[14:0]};
        16: sign_extend_field = {{16{value[15]}}, value[15:0]};
        17: sign_extend_field = {{15{value[16]}}, value[16:0]};
        18: sign_extend_field = {{14{value[17]}}, value[17:0]};
        19: sign_extend_field = {{13{value[18]}}, value[18:0]};
        20: sign_extend_field = {{12{value[19]}}, value[19:0]};
        21: sign_extend_field = {{11{value[20]}}, value[20:0]};
        22: sign_extend_field = {{10{value[21]}}, value[21:0]};
        23: sign_extend_field = {{9{value[22]}}, value[22:0]};
        24: sign_extend_field = {{8{value[23]}}, value[23:0]};
        25: sign_extend_field = {{7{value[24]}}, value[24:0]};
        26: sign_extend_field = {{6{value[25]}}, value[25:0]};
        27: sign_extend_field = {{5{value[26]}}, value[26:0]};
        28: sign_extend_field = {{4{value[27]}}, value[27:0]};
        29: sign_extend_field = {{3{value[28]}}, value[28:0]};
        30: sign_extend_field = {{2{value[29]}}, value[29:0]};
        31: sign_extend_field = {{1{value[30]}}, value[30:0]};
        default: sign_extend_field = value;
    endcase
end
endfunction

function automatic logic signed [15:0] sign_extend_coefficient(
    input logic [31:0] value,
    input logic [3:0] width
);
    logic signed [31:0] extended;
begin
    extended = sign_extend_field(value, {2'b0, width});
    sign_extend_coefficient = extended[15:0];
end
endfunction

function automatic logic signed [15:0] fixed_coefficient(
    input logic [3:0] order,
    input logic [3:0] index
);
begin
    fixed_coefficient = 16'sd0;
    case (order)
        1: fixed_coefficient = 16'sd1;
        2: fixed_coefficient = index == 0 ? 16'sd2 : -16'sd1;
        3: fixed_coefficient = index == 0 ? 16'sd3 :
            index == 1 ? -16'sd3 : 16'sd1;
        4: fixed_coefficient = index == 0 ? 16'sd4 :
            index == 1 ? -16'sd6 : index == 2 ? 16'sd4 : -16'sd1;
        default: fixed_coefficient = 16'sd0;
    endcase
end
endfunction

task automatic read_bits(input logic [5:0] count, input logic [4:0] next_state);
begin
    bit_accumulator <= 0;
    bits_left <= count;
    return_state <= next_state;
    if (count == 0) begin
        bit_field <= 0;
        state <= next_state;
    end else
        state <= STATE_READ;
end
endtask

task automatic fail;
begin
    error <= 1'b1;
    state <= STATE_FAILED;
end
endtask

task automatic begin_residual;
begin
    if (rice_escape) begin
        if (escape_width == 0) begin
            residual <= 0;
            state <= STATE_MAC_START;
        end else
            read_bits({1'b0, escape_width}, STATE_ESCAPE_VALUE);
    end else begin
        unary_quotient <= 0;
        state <= STATE_UNARY;
    end
end
endtask

task automatic next_after_sample;
begin
    // Retired: the advance is now split across STATE_ADVANCE and
    // STATE_ADVANCE2 so its comparisons and the bit reader's setup land in
    // separate register stages.
end
endtask

always_ff @(posedge clk) begin
    if (reset) begin
        state <= STATE_IDLE;
        return_state <= STATE_IDLE;
        bits_left <= 0;
        bit_field <= 0;
        bit_accumulator <= 0;
        subframe_kind <= KIND_CONSTANT;
        subframe_type <= 0;
        predictor_order <= 0;
        nominal_bits <= 0;
        coded_bits <= 0;
        wasted_bits <= 0;
        sample_index <= 0;
        partition_size <= 0;
        residual_left <= 0;
        partition_count <= 0;
        partition_index <= 0;
        rice_method <= 0;
        rice_parameter <= 0;
        rice_quotient_limit <= 0;
        rice_escape <= 0;
        escape_width <= 0;
        unary_quotient <= 0;
        residual <= 0;
        reconstructed_sample <= 0;
        restored_sample <= 0;
        restored_sample_fits <= 1'b0;
        restored_wide_q <= 0;
        coefficient_precision <= 0;
        coefficient_index <= 0;
        prediction_shift <= 0;
        history_pointer <= 0;
        mac_tap <= 0;
        mac_accumulator <= 0;
        mac_product_reg <= 0;
        shifted_prediction_reg <= 0;
        done <= 1'b0;
        error <= 1'b0;
        advance_kind <= ADVANCE_DONE;
        for (integer i = 0; i < 12; i = i + 1)
            coefficients[i] <= 0;
        for (integer i = 0; i < 16; i = i + 1)
            history[i] <= 0;
    end else begin
        done <= 1'b0;

        case (state)
            STATE_IDLE: if (start) begin
                nominal_bits <= channel_bits;
                coded_bits <= channel_bits;
                wasted_bits <= 0;
                sample_index <= 0;
                history_pointer <= 0;
                prediction_shift <= 0;
                error <= 1'b0;
                if (block_size == 0 || (channel_bits != 16 && channel_bits != 17))
                    fail();
                else
                    read_bits(6'd8, STATE_HEADER);
            end

            STATE_READ: begin
                if (bit_transfer) begin
                    bit_accumulator <= {bit_accumulator[30:0], bit_data};
                    bits_left <= bits_left - 1'b1;
                    if (bits_left == 1) begin
                        bit_field <= {bit_accumulator[30:0], bit_data};
                        state <= return_state;
                    end
                end else if (bit_end)
                    fail();
            end

            STATE_HEADER: begin
                subframe_type <= bit_field[6:1];
                if (bit_field[7] || !(
                        bit_field[6:1] <= 1 ||
                        (bit_field[6:1] >= 8 && bit_field[6:1] <= 12) ||
                        (bit_field[6:1] >= 32 && bit_field[6:1] <= 43)))
                    fail();
                else begin
                    if (bit_field[6:1] == 0) begin
                        subframe_kind <= KIND_CONSTANT;
                        predictor_order <= 0;
                    end else if (bit_field[6:1] == 1) begin
                        subframe_kind <= KIND_VERBATIM;
                        predictor_order <= 0;
                    end else begin
                        subframe_kind <= KIND_PREDICTOR;
                        predictor_order <= bit_field[6] ?
                            bit_field[4:1] + 1'b1 : bit_field[4:1] - 4'd8;
                    end

                    if (bit_field[0]) begin
                        wasted_bits <= 1;
                        state <= STATE_WASTED;
                    end else
                        state <= STATE_TYPE;
                end
            end

            STATE_WASTED: begin
                if (bit_transfer) begin
                    if (bit_data) begin
                        coded_bits <= nominal_bits - wasted_bits;
                        state <= STATE_TYPE;
                    end else if (wasted_bits >= nominal_bits - 1'b1)
                        fail();
                    else
                        wasted_bits <= wasted_bits + 1'b1;
                end else if (bit_end)
                    fail();
            end

            STATE_TYPE: begin
                if (subframe_kind == KIND_PREDICTOR && predictor_order_wide >= block_size)
                    fail();
                else if (subframe_kind == KIND_PREDICTOR && predictor_order == 0)
                    read_bits(6'd2, STATE_RICE_METHOD);
                else
                    read_bits({1'b0, coded_bits}, STATE_VALUE);
            end

            STATE_VALUE: begin
                reconstructed_sample <=
                    $signed({{16{sign_extended_value[31]}}, sign_extended_value});
                state <= STATE_RESTORE;
            end

            STATE_EMIT: begin
                if (!restored_sample_fits)
                    fail();
                else if (sample_transfer) begin
                    history[history_pointer] <= reconstructed_sample[16:0];
                    history_pointer <= history_pointer + 1'b1;
                    sample_index <= sample_index + 1'b1;
                    state <= STATE_ADVANCE;
                end
            end

            STATE_LPC_PRECISION: begin
                if (bit_field[3:0] == 4'hf)
                    fail();
                else begin
                    coefficient_precision <= bit_field[3:0] + 1'b1;
                    read_bits(6'd5, STATE_LPC_SHIFT);
                end
            end

            STATE_LPC_SHIFT: begin
                prediction_shift <= $signed({bit_field[4], bit_field[4:0]});
                coefficient_index <= 0;
                read_bits({2'b0, coefficient_precision}, STATE_LPC_COEFF);
            end

            STATE_LPC_COEFF: begin
                if (subframe_type[5])
                    coefficients[coefficient_index] <=
                        sign_extend_coefficient(bit_field, coefficient_precision);
                else if (coefficient_index < predictor_order)
                    coefficients[coefficient_index] <=
                        fixed_coefficient(predictor_order, coefficient_index);

                if (coefficient_index + 1'b1 == predictor_order)
                    read_bits(6'd2, STATE_RICE_METHOD);
                else begin
                    coefficient_index <= coefficient_index + 1'b1;
                    if (subframe_type[5])
                        read_bits({2'b0, coefficient_precision}, STATE_LPC_COEFF);
                end
            end

            STATE_RICE_METHOD: begin
                if (bit_field[1:0] > 1)
                    fail();
                else begin
                    rice_method <= bit_field[0];
                    read_bits(6'd4, STATE_PART_ORDER);
                end
            end

            STATE_PART_ORDER: begin
                if (bit_field[3:0] > 8 ||
                        (block_size & ((13'd1 << bit_field[3:0]) - 1'b1)) != 0 ||
                        next_partition_size <= predictor_order_wide)
                    fail();
                else begin
                    partition_size <= next_partition_size;
                    partition_count <= 9'd1 << bit_field[3:0];
                    partition_index <= 0;
                    residual_left <= next_partition_size - predictor_order_wide;
                    read_bits(rice_method ? 6'd5 : 6'd4, STATE_RICE_PARAM);
                end
            end

            STATE_RICE_PARAM: begin
                rice_parameter <= bit_field[4:0];
                rice_quotient_limit <= 32'hffff_fffe >> bit_field[4:0];
                rice_escape <= bit_field[4:0] == (rice_method ? 5'd31 : 5'd15);
                if (bit_field[4:0] == (rice_method ? 5'd31 : 5'd15))
                    read_bits(6'd5, STATE_ESCAPE_WIDTH);
                else
                    state <= STATE_RESIDUAL;
            end

            STATE_ESCAPE_WIDTH: begin
                escape_width <= bit_field[4:0];
                if (bit_field[4:0] == 0) begin
                    residual <= 0;
                    state <= STATE_MAC_START;
                end else
                    read_bits({1'b0, bit_field[4:0]}, STATE_ESCAPE_VALUE);
            end

            STATE_RESIDUAL: begin
                if (rice_escape)
                    begin_residual();
                else begin
                    unary_quotient <= 0;
                    state <= STATE_UNARY;
                end
            end

            STATE_UNARY: begin
                if (bit_transfer) begin
                    if (bit_data) begin
                        if (rice_parameter == 0) begin
                            bit_field <= 0;
                            residual <= unary_quotient[0] ?
                                -$signed({1'b0, unary_quotient[31:1]}) - 1 :
                                $signed({1'b0, unary_quotient[31:1]});
                            state <= STATE_MAC_START;
                        end else
                            read_bits({1'b0, rice_parameter}, STATE_REMAINDER);
                    end else if (unary_quotient >= rice_quotient_limit)
                        fail();
                    else
                        unary_quotient <= unary_quotient + 1'b1;
                end else if (bit_end)
                    fail();
            end

            STATE_REMAINDER: begin
                if (folded_residual == 32'hffff_ffff)
                    fail();
                else begin
                    residual <= folded_residual[0] ?
                        -$signed({1'b0, folded_residual[31:1]}) - 1 :
                        $signed({1'b0, folded_residual[31:1]});
                    state <= STATE_MAC_START;
                end
            end

            STATE_ESCAPE_VALUE: begin
                residual <= sign_extend_field(bit_field, {1'b0, escape_width});
                state <= STATE_MAC_START;
            end

            STATE_MAC_START: begin
                if (predictor_order == 0) begin
                    reconstructed_sample <= $signed({{16{residual[31]}}, residual});
                    state <= STATE_RESTORE;
                end else begin
                    mac_tap <= 0;
                    mac_accumulator <= 0;
                    state <= STATE_MAC_CAPTURE;
                end
            end

            STATE_MAC_CAPTURE: begin
                mac_product_reg <= mac_product;
                state <= STATE_MAC_ACCUM;
            end

            STATE_MAC_ACCUM: begin
                mac_accumulator <= mac_accumulator + mac_product_reg;
                if (mac_tap + 1'b1 == predictor_order)
                    state <= STATE_MAC_SHIFT;
                else begin
                    mac_tap <= mac_tap + 1'b1;
                    state <= STATE_MAC_CAPTURE;
                end
            end

            STATE_MAC_SHIFT: begin
                shifted_prediction_reg <= shifted_prediction;
                state <= STATE_MAC_FINISH;
            end

            STATE_MAC_FINISH: begin
                reconstructed_sample <= shifted_prediction_reg +
                    $signed({{16{residual[31]}}, residual});
                state <= STATE_RESTORE;
            end

            STATE_RESTORE: begin
                restored_wide_q <= restored_wide;
                state <= STATE_RESTORE_CHECK;
            end

            STATE_RESTORE_CHECK: begin
                restored_sample <= restored_wide_q[16:0];
                restored_sample_fits <= restored_fits;
                state <= STATE_EMIT;
            end

            // Two-stage post-emit advance.  sample_index is already the new
            // index here; the first stage only decides and updates the
            // residual position, and the second stage sets the bit reader or
            // next state from the registered decision.
            STATE_ADVANCE: begin
                if (sample_index == block_size)
                    advance_kind <= ADVANCE_DONE;
                else if (subframe_kind == KIND_CONSTANT)
                    advance_kind <= ADVANCE_CONSTANT;
                else if (subframe_kind == KIND_VERBATIM)
                    advance_kind <= ADVANCE_VALUE;
                else if (sample_index < predictor_order_wide)
                    advance_kind <= ADVANCE_VALUE;
                else if (sample_index == predictor_order_wide)
                    advance_kind <= ADVANCE_LPC;
                else if (residual_left == 1) begin
                    partition_index <= partition_index + 1'b1;
                    residual_left <= partition_size;
                    advance_kind <= ADVANCE_RICE;
                end else begin
                    residual_left <= residual_left - 1'b1;
                    advance_kind <= ADVANCE_RESIDUAL;
                end
                state <= STATE_ADVANCE2;
            end

            STATE_ADVANCE2: begin
                case (advance_kind)
                    ADVANCE_DONE: begin
                        done <= 1'b1;
                        state <= STATE_IDLE;
                    end
                    ADVANCE_CONSTANT: state <= STATE_EMIT;
                    ADVANCE_VALUE:    read_bits({1'b0, coded_bits}, STATE_VALUE);
                    ADVANCE_LPC: begin
                        if (subframe_type[5])
                            read_bits(6'd4, STATE_LPC_PRECISION);
                        else if (predictor_order == 0)
                            read_bits(6'd2, STATE_RICE_METHOD);
                        else begin
                            coefficient_index <= 0;
                            state <= STATE_LPC_COEFF;
                        end
                    end
                    ADVANCE_RICE:     read_bits(rice_method ? 6'd5 : 6'd4, STATE_RICE_PARAM);
                    default:          state <= STATE_RESIDUAL;   // ADVANCE_RESIDUAL
                endcase
            end

            STATE_FAILED: ;
            default: fail();
        endcase
    end
end

endmodule
