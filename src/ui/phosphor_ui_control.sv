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

wire text_write = request_valid && request_write &&
    request_address >= 32'h0000_0100 &&
    request_address <= 32'h0000_021c && request_address[1:0] == 2'b00;
wire [7:0] text_write_word = request_address[9:2] - 8'h40;
wire [7:0] text_write_address = (active_bank ? 8'd0 : 8'd72) +
    text_write_word;
wire [7:0] text_read_address = (active_bank ? 8'd72 : 8'd0) +
    text_address[8:2];
logic [31:0] text_read_word;
logic [1:0] text_byte_select;

wire artwork_write = request_valid && request_write &&
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
    if (text_write)
        text_memory[text_write_address] <= request_wdata;
    text_read_word <= text_memory[text_read_address];
    text_byte_select <= text_address[1:0];
    if (artwork_write)
        artwork_memory[artwork_write_address] <= request_wdata;
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
    end else if (request_valid && request_write) begin
        if (request_address == 32'h0000_0078) begin
            pause_requested <= request_wdata[0];
        end else if (request_address == 32'h0000_007c) begin
            ui_visible <= request_wdata[0];
            playlist <= request_wdata[1];
            if (request_wdata[31]) begin
                active_bank <= ~active_bank;
                current_track <= shadow_playlist_state[7:0];
                track_count <= shadow_playlist_state[15:8];
                window_start <= shadow_playlist_state[23:16];
                lengths_0_3 <= shadow_lengths_0_3;
                lengths_4_7 <= shadow_lengths_4_7;
                length_8 <= shadow_length_8;
            end
        end else if (request_address == 32'h0000_0080) begin
            shadow_playlist_state <= request_wdata[23:0];
        end else if (request_address == 32'h0000_0084) begin
            shadow_lengths_0_3 <= request_wdata;
        end else if (request_address == 32'h0000_0088) begin
            shadow_lengths_4_7 <= request_wdata;
        end else if (request_address == 32'h0000_0094) begin
            shadow_length_8 <= request_wdata[31:24];
        end else if (request_address == 32'h0000_0098) begin
            artwork_valid <= request_wdata[0];
            if (request_wdata[31])
                active_artwork_bank <= ~active_artwork_bank;
        end
    end
end

endmodule
