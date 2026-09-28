// Phosphor-specific UI/control registers behind the generic Tang-Control
// debug bus. Text and RGB332 artwork are assembled in independent inactive
// banks and published atomically.

module phosphor_ui_control (
    input  logic        clk,
    input  logic        resetn,
    input  logic        request_valid,
    input  logic        request_write,
    input  logic [31:0] request_address,
    input  logic [31:0] request_wdata,

    output logic        pause_requested,
    output logic        ui_visible,
    output logic        playlist,
    output logic  [7:0] current_track,
    output logic  [7:0] track_count,
    output logic  [7:0] window_start,
    output logic [31:0] lengths_0_3,
    output logic [31:0] lengths_4_7,
    output logic  [7:0] length_8,

    input  logic  [8:0] text_address,
    output logic  [7:0] text_data,
    output logic        artwork_valid,
    input  logic [13:0] artwork_address,
    output logic  [7:0] artwork_data
);

logic active_bank;
logic active_artwork_bank;
logic [23:0] shadow_playlist_state;
logic [31:0] shadow_lengths_0_3;
logic [31:0] shadow_lengths_4_7;
logic [7:0] shadow_length_8;
// Pad the two 72-word text banks to a power-of-two physical RAM.  A
// synchronous read is intentional: Gowin can map this store into one BSRAM
// instead of building 4.5 kbits of storage plus its read mux from fabric.
(* syn_ramstyle = "block_ram" *) logic [31:0] text_memory [0:255];
(* syn_ramstyle = "block_ram" *) logic [31:0] artwork_memory [0:4231];

// Writes are decoded from the transport request and applied one cycle later
// from registered strobes, keeping the 32-bit address compare and bank-offset
// arithmetic off the storage and register enables.
logic write_q;
logic [31:0] wdata_q;
logic pause_write_q;
logic visibility_write_q;
logic playlist_write_q;
logic lengths_0_3_write_q;
logic lengths_4_7_write_q;
logic length_8_write_q;
logic artwork_control_write_q;
logic text_write_q;
logic [7:0] text_write_address_q;
logic artwork_write_q;
logic [12:0] artwork_write_address_q;

wire request_write_valid = request_valid && request_write;
wire text_write = request_write_valid &&
    request_address >= 32'h0000_0100 &&
    request_address <= 32'h0000_021c && request_address[1:0] == 2'b00;
wire [7:0] text_write_word = request_address[9:2] - 8'h40;
wire [7:0] text_write_address = (active_bank ? 8'd0 : 8'd72) +
    text_write_word;
wire [7:0] text_read_address = (active_bank ? 8'd72 : 8'd0) +
    text_address[8:2];
logic [31:0] text_read_word;
logic [1:0] text_byte_select;

wire artwork_write = request_write_valid &&
    request_address >= 32'h0000_1000 &&
    request_address <= 32'h0000_310c && request_address[1:0] == 2'b00;
wire [11:0] artwork_write_word = request_address[13:2] - 12'h400;
wire [12:0] artwork_write_address =
    (active_artwork_bank ? 13'd0 : 13'd2116) + artwork_write_word;
wire [12:0] artwork_read_address =
    (active_artwork_bank ? 13'd2116 : 13'd0) + artwork_address[13:2];
logic [31:0] artwork_read_word;
logic [1:0] artwork_byte_select;

always_comb begin
    case (text_byte_select)
        0: text_data = text_read_word[31:24];
        1: text_data = text_read_word[23:16];
        2: text_data = text_read_word[15:8];
        default: text_data = text_read_word[7:0];
    endcase
end

always_comb begin
    case (artwork_byte_select)
        0: artwork_data = artwork_read_word[31:24];
        1: artwork_data = artwork_read_word[23:16];
        2: artwork_data = artwork_read_word[15:8];
        default: artwork_data = artwork_read_word[7:0];
    endcase
end

// Text storage does not require reset contents: lengths remain zero until the
// first committed snapshot.  Keeping its write port outside the reset mux
// avoids putting the high-fanout video reset on every byte lane.
always_ff @(posedge clk) begin
    if (!resetn) begin
        write_q <= 1'b0;
        text_write_q <= 1'b0;
        artwork_write_q <= 1'b0;
    end else begin
        write_q <= request_write_valid;
        text_write_q <= text_write;
        artwork_write_q <= artwork_write;
    end
    wdata_q <= request_wdata;
    pause_write_q <= request_address == 32'h0000_0078;
    visibility_write_q <= request_address == 32'h0000_007c;
    playlist_write_q <= request_address == 32'h0000_0080;
    lengths_0_3_write_q <= request_address == 32'h0000_0084;
    lengths_4_7_write_q <= request_address == 32'h0000_0088;
    length_8_write_q <= request_address == 32'h0000_0094;
    artwork_control_write_q <= request_address == 32'h0000_0098;
    text_write_address_q <= text_write_address;
    artwork_write_address_q <= artwork_write_address;
end

always_ff @(posedge clk) begin
    if (text_write_q)
        text_memory[text_write_address_q] <= wdata_q;
    text_read_word <= text_memory[text_read_address];
    text_byte_select <= text_address[1:0];
    if (artwork_write_q)
        artwork_memory[artwork_write_address_q] <= wdata_q;
    artwork_read_word <= artwork_memory[artwork_read_address];
    artwork_byte_select <= artwork_address[1:0];
end

always_ff @(posedge clk) begin
    if (!resetn) begin
        active_bank <= 1'b0;
        active_artwork_bank <= 1'b0;
        artwork_valid <= 1'b0;
        pause_requested <= 1'b0;
        ui_visible <= 1'b0;
        playlist <= 1'b0;
        current_track <= 0;
        track_count <= 0;
        window_start <= 0;
        lengths_0_3 <= 0;
        lengths_4_7 <= 0;
        length_8 <= 0;
        shadow_playlist_state <= 0;
        shadow_lengths_0_3 <= 0;
        shadow_lengths_4_7 <= 0;
        shadow_length_8 <= 0;
    end else if (write_q) begin
        if (pause_write_q) begin
            pause_requested <= wdata_q[0];
        end else if (visibility_write_q) begin
            ui_visible <= wdata_q[0];
            playlist <= wdata_q[1];
            if (wdata_q[31]) begin
                active_bank <= ~active_bank;
                current_track <= shadow_playlist_state[7:0];
                track_count <= shadow_playlist_state[15:8];
                window_start <= shadow_playlist_state[23:16];
                lengths_0_3 <= shadow_lengths_0_3;
                lengths_4_7 <= shadow_lengths_4_7;
                length_8 <= shadow_length_8;
            end
        end else if (playlist_write_q) begin
            shadow_playlist_state <= wdata_q[23:0];
        end else if (lengths_0_3_write_q) begin
            shadow_lengths_0_3 <= wdata_q;
        end else if (lengths_4_7_write_q) begin
            shadow_lengths_4_7 <= wdata_q;
        end else if (length_8_write_q) begin
            shadow_length_8 <= wdata_q[31:24];
        end else if (artwork_control_write_q) begin
            artwork_valid <= wdata_q[0];
            if (wdata_q[31])
                active_artwork_bank <= ~active_artwork_bank;
        end
    end
end

endmodule
