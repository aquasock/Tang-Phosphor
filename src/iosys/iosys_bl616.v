// IOSys_bl616 - BL616-based IO system
// 
// This manages UART connection to the companion bl616 MCU, accepts ROM loading and other requests,
// and display the text overlay when needed.
// 
// Author: nand2mario, 2/2025

`define MCU_BL616

module iosys_bl616 #(
    parameter FREQ=21_477_000,
    parameter [14:0] COLOR_LOGO=15'b00000_10101_00000,
    parameter [15:0] CORE_ID=1,     // 1: nestang, 2: snestang
    parameter [7:0] LOADING_STATE=0
)
(
    input clk,                      // main logic clock
    // input clk50,                    // 50mhz clock for UART
    input hclk,                     // hdmi clock
    input resetn,

    // OSD display interface
    output overlay,
    input [7:0] overlay_x,          // 0-255
    input [7:0] overlay_y,          // 0-223
    output [14:0] overlay_color,    // BGR5
    input [11:0] joy1,              // DS2/SNES joystick 1: (R L X A RT LT DN UP START SELECT Y B)
    input [11:0] joy2,              // DS2/SNES joystick 2
    output reg [15:0] hid1,         // USB HID joystick 1
    output reg [15:0] hid2,         // USB HID joystick 2

    // ROM loading interface
    output [7:0] rom_loading,   // 0-to-1 loading starts, 1-to-0 loading is finished
    output reg [7:0] rom_do,        // first 64 bytes are snes header + 32 bytes after snes header 
    output reg rom_do_valid,        // strobe for rom_do

    // PCXT management interface
    output reg [15:0] mgmt_address,
    output reg        mgmt_read,
    input      [15:0] mgmt_readdata,
    output reg        mgmt_write,
    output reg [15:0] mgmt_writedata,
    input      [1:0]  fdd_request,      // [1]: write, [0]: read

    // Keyboard interface
    output reg [7:0] kbd_data,
    output reg       kbd_data_valid,
    
    output reg [31:0] core_config,

    // Generic core-owned 32-bit debug register bus
    output reg        debug_valid,
    output reg        debug_write,
    output reg [31:0] debug_address,
    output reg [31:0] debug_wdata,
    input      [31:0] debug_rdata,
    output reg [31:0] debug_crc_errors,
    output reg [31:0] debug_bad_requests,

    // Credit-based byte stream from the BL616/SD card
    output reg        stream_start,
    output reg        stream_end,
    output reg        stream_cancel,
    output reg [15:0] stream_id,
    output reg [31:0] stream_offset,
    output      [7:0] stream_data,
    output            stream_valid,
    input             stream_ready,

    // UART interface
    input  uart_rx,
    output uart_tx
);

localparam integer STR_LEN = 77; // number of characters in the config string
localparam [8*STR_LEN-1:0] CONF_STR = "Tang-Phosphor;-;O12,OSD key,Right+Select,Select+Start,Select+RB;-;V,v20260927";

// Remove SPI parameters and add UART parameters
localparam CLK_FREQ = FREQ;
localparam BAUD_RATE = 2_000_000;

localparam [7:0] EXT_COMMAND = 8'h10;
localparam [7:0] EXT_VERSION = 8'h01;
localparam [7:0] EXT_CAPABILITIES = 8'h00;
localparam [7:0] EXT_READ32 = 8'h01;
localparam [7:0] EXT_WRITE32 = 8'h02;
localparam [7:0] EXT_SET_BAUD = 8'h03;
localparam [7:0] EXT_WRITE_BLOCK = 8'h04;
localparam [7:0] BLOCK_COMMAND = 8'h12;
localparam integer BLOCK_MAX_WORDS = 64;
localparam [7:0] STREAM_COMMAND = 8'h11;
localparam [7:0] STREAM_VERSION = 8'h01;
localparam [7:0] STREAM_START = 8'h01;
localparam [7:0] STREAM_DATA = 8'h02;
localparam [7:0] STREAM_END = 8'h04;
localparam [7:0] STREAM_CANCEL = 8'h08;
localparam [15:0] STREAM_CREDIT = 16'd1024;

function [15:0] crc16_byte;
    input [15:0] crc;
    input [7:0] data;
    integer bit_index;
    reg [15:0] value;
    begin
        value = crc ^ {data, 8'b0};
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
            value = value[15] ? (value << 1) ^ 16'h1021 : value << 1;
        crc16_byte = value;
    end
endfunction

function [15:0] stream_response_crc;
    input [7:0] status;
    input [7:0] flags;
    input [15:0] identifier;
    input [31:0] next_offset;
    input [15:0] credit;
    reg [15:0] crc;
    begin
        crc = crc16_byte(16'hffff, STREAM_COMMAND);
        crc = crc16_byte(crc, STREAM_VERSION);
        crc = crc16_byte(crc, status);
        crc = crc16_byte(crc, flags);
        crc = crc16_byte(crc, identifier[15:8]);
        crc = crc16_byte(crc, identifier[7:0]);
        crc = crc16_byte(crc, next_offset[31:24]);
        crc = crc16_byte(crc, next_offset[23:16]);
        crc = crc16_byte(crc, next_offset[15:8]);
        crc = crc16_byte(crc, next_offset[7:0]);
        crc = crc16_byte(crc, credit[15:8]);
        crc = crc16_byte(crc, credit[7:0]);
        stream_response_crc = crc;
    end
endfunction

function [15:0] debug_response_crc;
    input [7:0] opcode;
    input [7:0] status;
    input [15:0] transaction;
    input [31:0] address;
    input [31:0] value;
    reg [15:0] crc;
    begin
        crc = crc16_byte(16'hffff, EXT_COMMAND);
        crc = crc16_byte(crc, EXT_VERSION);
        crc = crc16_byte(crc, opcode | 8'h80);
        crc = crc16_byte(crc, status);
        crc = crc16_byte(crc, transaction[15:8]);
        crc = crc16_byte(crc, transaction[7:0]);
        crc = crc16_byte(crc, address[31:24]);
        crc = crc16_byte(crc, address[23:16]);
        crc = crc16_byte(crc, address[15:8]);
        crc = crc16_byte(crc, address[7:0]);
        crc = crc16_byte(crc, value[31:24]);
        crc = crc16_byte(crc, value[23:16]);
        crc = crc16_byte(crc, value[15:8]);
        crc = crc16_byte(crc, value[7:0]);
        debug_response_crc = crc;
    end
endfunction

reg overlay_reg = 1;
assign overlay = overlay_reg;

reg [7:0] rom_loading_reg = LOADING_STATE;
assign rom_loading = rom_loading_reg;

// UART receiver signals
wire [7:0] rx_data_slow;
wire [7:0] rx_data_fast;
wire rx_valid_slow;
wire rx_valid_fast;
reg [7:0] rx_data = 8'd0;
reg rx_valid = 1'b0;

// UART transmitter signals
reg [7:0] tx_data;
reg tx_valid;
wire tx_ready;
wire tx_busy_slow;
wire tx_busy_fast;
wire tx_busy;
wire uart_tx_slow;
wire uart_tx_fast;
reg baud_fast;

// The selected receiver's byte is registered, so the receiver select is not
// in front of the command decoder.  The cycle of latency is invisible: a byte
// arrives at most once per character time, at least 148 clocks at 5 Mbaud.
always @(posedge clk) begin
    rx_data <= baud_fast ? rx_data_fast : rx_data_slow;
    rx_valid <= baud_fast ? rx_valid_fast : rx_valid_slow;
end
assign tx_busy = baud_fast ? tx_busy_fast : tx_busy_slow;
assign uart_tx = baud_fast ? uart_tx_fast : uart_tx_slow;

// synchronize uart_rx to clk
reg uart_rx_r = 1, uart_rx_rr = 1;
always @(posedge clk) begin
    uart_rx_r <= uart_rx;
    uart_rx_rr <= uart_rx_r;
end

// Instantiate UART modules
async_receiver #(
    .ClkFrequency(CLK_FREQ),
    .Baud(BAUD_RATE)
) uart_receiver_slow (
    .clk(clk),
    .RxD(uart_rx_rr),
    .RxD_data(rx_data_slow),
    .RxD_data_ready(rx_valid_slow)
);

async_receiver #(
    .ClkFrequency(CLK_FREQ),
    .Baud(5_000_000)
) uart_receiver_fast (
    .clk(clk),
    .RxD(uart_rx_rr),
    .RxD_data(rx_data_fast),
    .RxD_data_ready(rx_valid_fast)
);

async_transmitter #(
    .ClkFrequency(CLK_FREQ),
    .Baud(BAUD_RATE)
) uart_transmitter_slow (
    .clk(clk),
    .TxD(uart_tx_slow),
    .TxD_data(tx_data),
    .TxD_start(tx_valid && !baud_fast),
    .TxD_busy(tx_busy_slow)
);

async_transmitter #(
    .ClkFrequency(CLK_FREQ),
    .Baud(5_000_000)
) uart_transmitter_fast (
    .clk(clk),
    .TxD(uart_tx_fast),
    .TxD_data(tx_data),
    .TxD_start(tx_valid && baud_fast),
    .TxD_busy(tx_busy_fast)
);
assign tx_ready = ~tx_busy;

// Command processing state machine
localparam RECV_IDLE         = 7'b0000001; // waiting for command
localparam RECV_LEN1         = 7'b0000010; // receiving length msb
localparam RECV_LEN2         = 7'b0000100; // receiving length lsb
localparam RECV_CMD          = 7'b0001000; // receiving command
localparam RECV_PARAM        = 7'b0010000; // receiving parameters
localparam RECV_RESPONSE_REQ = 7'b0100000; // sending response
localparam RECV_RESPONSE_ACK = 7'b1000000; // waiting for response sending to finish 
localparam RECV_BLOCK_WRITE  = 8'b10000000; // replaying a validated block write
reg [7:0] recv_state = RECV_IDLE;

// UART command buffer
reg [7:0] cmd_reg;
reg [15:0] len_reg;
reg [31:0] data_reg;
reg [23:0] rom_remain;
reg [15:0] data_cnt;
reg [3:0] kbd_len;

reg [7:0] ext_version;
reg [7:0] ext_opcode;
reg [15:0] ext_sequence;
reg [31:0] ext_address;
reg [31:0] ext_value;
reg [15:0] ext_crc;
reg [15:0] ext_crc_received;

// Block writes buffer up to 64 words and replay them onto the debug bus only
// after the whole frame's CRC, version, opcode, length, and alignment pass,
// so a damaged frame never reaches core registers.
(* syn_ramstyle = "block_ram" *) reg [31:0] block_buffer [0:BLOCK_MAX_WORDS-1];
reg block_buffer_write;
reg [5:0] block_buffer_write_address;
reg [31:0] block_buffer_write_data;
reg [31:0] block_buffer_read_data;
reg [15:0] block_payload_end;
reg [6:0] block_word_count;
reg block_length_ok;
reg [6:0] block_replay_index;
reg block_replay_primed;
reg [31:0] block_replay_address;
wire [5:0] block_buffer_read_address = block_replay_primed ?
    block_replay_index[5:0] + 1'b1 : block_replay_index[5:0];

always @(posedge clk) begin
    if (block_buffer_write)
        block_buffer[block_buffer_write_address] <= block_buffer_write_data;
    block_buffer_read_data <= block_buffer[block_buffer_read_address];
end

reg [7:0] response_opcode;
reg [7:0] response_status;
reg [15:0] response_sequence;
reg [31:0] response_address;
reg [31:0] response_data;
wire [15:0] response_crc = debug_response_crc(
    response_opcode, response_status, response_sequence,
    response_address, response_data
);

reg [7:0] stream_flags_rx;
reg [15:0] stream_id_rx;
reg [31:0] stream_offset_rx;
reg [15:0] stream_length_rx;
reg [15:0] stream_crc_rx;
reg [15:0] stream_crc_received;
// The receive buffer is a synchronous-read block RAM.  Writes are registered
// one cycle after their UART byte, and the read port always addresses the byte
// that will be presented next, so the registered output behaves as the former
// combinational first-word-fall-through read without placing the receive
// state machine or a 1024-entry fabric multiplexer on the stream data path.
(* syn_ramstyle = "block_ram" *) reg [7:0] stream_buffer [0:1023];
reg stream_buffer_write;
reg [9:0] stream_buffer_write_address;
reg [7:0] stream_buffer_write_data;
reg [7:0] stream_buffer_read_data;
// Frame bounds are fixed once the length's low byte arrives; resolve them
// then instead of adding the payload length on every later byte.
reg [16:0] stream_crc_high_index;
reg [16:0] stream_crc_low_index;
reg stream_frame_length_ok;
reg stream_buffer_active;
reg [9:0] stream_read_index;
reg [10:0] stream_buffer_length;
reg [31:0] stream_expected_offset;
reg [15:0] stream_active_id;
reg stream_session_active;
reg stream_ack_pending;

reg [7:0] stream_response_status;
reg [7:0] stream_response_flags;
reg [15:0] stream_response_id;
reg [31:0] stream_response_next_offset;
reg [15:0] stream_response_credit;
wire [15:0] stream_response_crc_value = stream_response_crc(
    stream_response_status, stream_response_flags, stream_response_id,
    stream_response_next_offset, stream_response_credit
);

assign stream_valid = stream_buffer_active;
assign stream_data = stream_buffer_read_data;

// The read index returns to zero whenever the buffer is inactive, so byte 0 is
// already registered when a validated DATA frame raises stream_valid.
wire [9:0] stream_buffer_read_address =
    stream_buffer_active && stream_ready ? stream_read_index + 1'b1 : stream_read_index;

always @(posedge clk) begin
    if (stream_buffer_write)
        stream_buffer[stream_buffer_write_address] <= stream_buffer_write_data;
    stream_buffer_read_data <= stream_buffer[stream_buffer_read_address];
end

// Add new registers for textdisp interface
reg [7:0] x_wr;
reg [7:0] y_wr;
reg [7:0] char_wr;
reg we;

// Add these registers for cursor management
reg [7:0] cursor_x;
reg [7:0] cursor_y;

reg [7:0] response_type;
reg response_req;
reg response_ack;

// mgmt_* multiplex
reg mgmt_rx;
reg [15:0] mgmt_address_rx;
reg [15:0] mgmt_address_tx;
assign mgmt_address = mgmt_rx ? mgmt_address_rx : mgmt_address_tx;

localparam FDD_READY = 0;
localparam FDD_READ_WAIT = 1;
localparam FDD_DONE_WAIT = 2;

reg [1:0] fdd_state;
reg fdd_read_start, fdd_read_finish, fdd_write_finish;

// The TangCore bl616-fpga UART protocol
//
// Since 0.9, we've introduce a data frame to avoid spurious messages:
//
//         0xAA frame_len[15:0] payload_of_frame_len_bytes
//
// Command payloads from BL616 to FPGA:
// 0x01                       get core ID (response type 0x01, see below), frame_len = 1
// 0x02                       get core config string (response type 0x02, see below)
// 0x03 x[31:0]               set core config status
// 0x04 x[7:0] y[7:0]         move overlay text cursor to (x, y)
// 0x05 <string>              display string from cursor (len implied by frame header, =frame_len-1)
// 0x06 loading_state[7:0]    set loading state (0: core running, non-0: loading)
// 0x07 <data>                load data to rom_do (len implied by frame header)
// 0x08 x[7:0]                x[0]: turn overlay on/off
// 0x09 hid1[15:0] hid2[15:0] send USB joystick state to FPGA
// 0x0a <data_sector>         send a sector (512 bytes) of data to floppy data FIFO
// 0x0b addr[15:0] data[15:0] write to disk management interface (mgmt_address and mgmt_writedata)
// 0x0c <scancode>            send PS/2 scancode (len specified by frame header)
// 0x0d <string>              debug printf. core ignores this.
// 0x10 <extended request>    versioned debug/control request with CRC-16
// 0x11 <stream frame>        credit-based stream control/data with CRC-16
// 0x12 <block write>         validated 1-64 word register write with CRC-16
//
// Response payloads from FPGA to BL616:
// 0x01 core_id[7:0]          core ID
// 0x02 <string>              core config string (len specified by frame header)
// 0x03 joy1[15:0] joy2[15:0] every 20ms, send DS2/SNES joypad state to BL616
// 0x04 lba[15:0] <data_512>  write a sector to disk
// 0x05 lba[15:0]             read a sector from disk (followed by command 0x0a)
// 0x10 <extended response>   versioned debug/control response with CRC-16
// 0x11 <stream ack>          stream status, next offset, and receive credit

// Frame-position comparisons, registered for timing. data_cnt, len_reg,
// block_payload_end and the stream CRC indices change only on rx_valid
// cycles, and a UART delivers at most one byte per character time (at least
// 148 clocks at 5 Mbaud), so each flag already holds its operands' current
// comparison whenever the next byte arrives.
reg data_cnt_last;          // data_cnt + 2 == len_reg
reg data_cnt_before_block;  // data_cnt < block_payload_end
reg data_cnt_at_block;      // data_cnt == block_payload_end
reg data_cnt_before_crc;    // data_cnt < stream_crc_high_index
reg data_cnt_at_crc_high;   // data_cnt == stream_crc_high_index
reg data_cnt_at_crc_low;    // data_cnt == stream_crc_low_index

always @(posedge clk) begin
    data_cnt_last <= data_cnt + 16'd2 == len_reg;
    data_cnt_before_block <= data_cnt < block_payload_end;
    data_cnt_at_block <= data_cnt == block_payload_end;
    data_cnt_before_crc <= {1'b0, data_cnt} < stream_crc_high_index;
    data_cnt_at_crc_high <= {1'b0, data_cnt} == stream_crc_high_index;
    data_cnt_at_crc_low <= {1'b0, data_cnt} == stream_crc_low_index;
end

// UART RX: command processing
always @(posedge clk) begin
    if (!resetn) begin
        recv_state <= RECV_IDLE;
        cmd_reg <= 0;
        data_reg <= 0;
        rom_loading_reg <= 0;
        rom_remain <= 0;
        core_config <= 0;
        data_cnt <= 0;
        x_wr <= 0;
        y_wr <= 0;
        char_wr <= 0;
        we <= 0;
        cursor_x <= 0;
        cursor_y <= 0;
        response_req <= 0;
        debug_valid <= 0;
        debug_write <= 0;
        debug_address <= 0;
        debug_wdata <= 0;
        debug_crc_errors <= 0;
        debug_bad_requests <= 0;
        stream_start <= 0;
        stream_end <= 0;
        stream_cancel <= 0;
        stream_id <= 0;
        stream_offset <= 0;
        stream_buffer_active <= 0;
        stream_read_index <= 0;
        stream_buffer_length <= 0;
        stream_buffer_write <= 0;
        stream_buffer_write_address <= 0;
        stream_buffer_write_data <= 0;
        stream_crc_high_index <= 0;
        stream_crc_low_index <= 0;
        stream_frame_length_ok <= 0;
        block_buffer_write <= 0;
        block_buffer_write_address <= 0;
        block_buffer_write_data <= 0;
        block_payload_end <= 0;
        block_word_count <= 0;
        block_length_ok <= 0;
        block_replay_index <= 0;
        block_replay_primed <= 0;
        block_replay_address <= 0;
        stream_expected_offset <= 0;
        stream_active_id <= 0;
        stream_session_active <= 0;
        stream_ack_pending <= 0;
    end else begin
        rom_do_valid <= 0;
        we <= 0;
        mgmt_write <= 0;
        fdd_read_finish <= 0;
        mgmt_rx <= 0;
        kbd_data_valid <= 0;
        debug_valid <= 0;
        debug_write <= 0;
        stream_start <= 0;
        stream_end <= 0;
        stream_cancel <= 0;
        stream_buffer_write <= 0;
        block_buffer_write <= 0;

        if (stream_buffer_active && stream_ready) begin
            stream_offset <= stream_offset + 1'b1;
            if ({1'b0, stream_read_index} + 1'b1 == stream_buffer_length) begin
                stream_buffer_active <= 0;
                stream_read_index <= 0;
                stream_expected_offset <= stream_expected_offset + stream_buffer_length;
                stream_response_next_offset <= stream_expected_offset + stream_buffer_length;
                stream_response_credit <= STREAM_CREDIT;
                stream_ack_pending <= 1;
            end else begin
                stream_read_index <= stream_read_index + 1'b1;
            end
        end

        if (stream_ack_pending && recv_state == RECV_IDLE && !rx_valid) begin
            stream_ack_pending <= 0;
            response_type <= STREAM_COMMAND;
            response_req <= ~response_req;
            recv_state <= RECV_RESPONSE_ACK;
        end

        case (recv_state)

            RECV_IDLE: if (rx_valid && rx_data == 8'hAA) begin
                recv_state <= RECV_LEN1;
            end

            RECV_LEN1: if (rx_valid) begin
                len_reg[15:8] <= rx_data;
                if (rx_data < 8)                      // max frame length 2047
                    recv_state <= RECV_LEN2;
                else
                    recv_state <= RECV_IDLE;
            end

            RECV_LEN2: if (rx_valid) begin
                len_reg[7:0] <= rx_data;
                recv_state <= RECV_CMD;
            end

            RECV_CMD: if (rx_valid) begin
                cmd_reg <= rx_data;
                if (rx_data == 1 || rx_data == 2)
                    recv_state <= RECV_RESPONSE_REQ;    // request sending core id / config string
                else if (rx_data == EXT_COMMAND) begin
                    ext_crc <= crc16_byte(16'hffff, EXT_COMMAND);
                    if (len_reg != 16'd15)
                        debug_bad_requests <= debug_bad_requests + 1'b1;
                    recv_state <= (len_reg > 1) ? RECV_PARAM : RECV_IDLE;
                end
                else if (rx_data == STREAM_COMMAND) begin
                    stream_crc_rx <= crc16_byte(16'hffff, STREAM_COMMAND);
                    recv_state <= (len_reg > 1) ? RECV_PARAM : RECV_IDLE;
                end
                else if (rx_data == BLOCK_COMMAND) begin
                    ext_crc <= crc16_byte(16'hffff, BLOCK_COMMAND);
                    // Payload bytes precede the two CRC bytes.
                    block_payload_end <= len_reg - 16'd3;
                    recv_state <= (len_reg > 1) ? RECV_PARAM : RECV_IDLE;
                end
                else if (len_reg > 1)
                    recv_state <= RECV_PARAM;
                else
                    recv_state <= RECV_IDLE;
                data_cnt <= 0;
            end
            
            RECV_PARAM: if (rx_valid) begin
                data_reg <= {data_reg[23:0], rx_data};
                data_cnt <= data_cnt + 1;
                // e.g. set_overlay x[7:0], the 1st param byte is the last 
                //      (data_cnt == 0, len_reg == 2)
                if (data_cnt_last)
                    recv_state <= RECV_IDLE;
                
                case (cmd_reg)
                    3: begin
                        if (data_cnt == 3) begin    // Received 4 bytes
                            core_config <= {data_reg[23:0], rx_data};
                        end
                    end
                    4: case (data_cnt)              // cursor
                        0: cursor_x <= rx_data;
                        1: cursor_y <= rx_data;
                        default: ;
                    endcase
                    5: begin                        // print
                        x_wr <= cursor_x;
                        y_wr <= cursor_y;
                        char_wr <= rx_data;
                        if (cursor_x < 32) begin
                            cursor_x <= cursor_x + 1;
                            we <= 1;
                        end
                    end
                    6: begin
                        rom_loading_reg <= rx_data;
                        recv_state <= RECV_IDLE;    // Single byte command
                    end
                    7: begin
                        rom_do <= rx_data;
                        rom_do_valid <= 1;      // pulse data valid
                    end
                    8: begin
                        overlay_reg <= rx_data[0];
                    end
                    9: begin
                        case (data_cnt)
                            0: hid1[15:8] <= rx_data;
                            1: hid1[7:0] <= rx_data;
                            2: hid2[15:8] <= rx_data;
                            3: hid2[7:0] <= rx_data;
                            default: ;
                        endcase
                    end
                    'ha: begin                      // send read data to disk controller
                        mgmt_rx <= 1;
                        mgmt_address_rx <= 16'hf20f;
                        mgmt_writedata <= rx_data;
                        mgmt_write <= '1;
                        if (data_cnt == 511) 
                            fdd_read_finish <= 1;
                    end
                    'hb: begin                      // write disk controller register
                        mgmt_rx <= 1;
                        case (data_cnt)
                            0: mgmt_address_rx[15:8] <= rx_data;
                            1: mgmt_address_rx[7:0] <= rx_data;
                            2: mgmt_writedata[15:8] <= rx_data;
                            3: begin
                                mgmt_writedata[7:0] <= rx_data;
                                mgmt_write <= '1;
                            end
                            default: ;
                        endcase
                    end
                    'hc: begin                      // send PS/2 scancode to PCXT
                        kbd_data <= rx_data;
                        kbd_data_valid <= 1;
                    end
                    EXT_COMMAND: begin
                        if (data_cnt < 12)
                            ext_crc <= crc16_byte(ext_crc, rx_data);
                        case (data_cnt)
                            0: ext_version <= rx_data;
                            1: ext_opcode <= rx_data;
                            2: ext_sequence[15:8] <= rx_data;
                            3: ext_sequence[7:0] <= rx_data;
                            4: ext_address[31:24] <= rx_data;
                            5: ext_address[23:16] <= rx_data;
                            6: ext_address[15:8] <= rx_data;
                            7: begin
                                ext_address[7:0] <= rx_data;
                                debug_address <= {ext_address[31:8], rx_data};
                            end
                            8: ext_value[31:24] <= rx_data;
                            9: ext_value[23:16] <= rx_data;
                            10: ext_value[15:8] <= rx_data;
                            11: begin
                                ext_value[7:0] <= rx_data;
                                debug_wdata <= {ext_value[31:8], rx_data};
                            end
                            12: ext_crc_received[15:8] <= rx_data;
                            13: if (len_reg == 16'd15) begin
                                ext_crc_received[7:0] <= rx_data;
                                response_type <= EXT_COMMAND;
                                response_opcode <= ext_opcode;
                                response_sequence <= ext_sequence;
                                response_address <= ext_address;
                                if (ext_crc != {ext_crc_received[15:8], rx_data}) begin
                                    response_status <= 8'd3;
                                    response_data <= 0;
                                    debug_crc_errors <= debug_crc_errors + 1'b1;
                                end else if (ext_version != EXT_VERSION) begin
                                    response_status <= 8'd1;
                                    response_data <= 0;
                                    debug_bad_requests <= debug_bad_requests + 1'b1;
                                end else if (ext_opcode == EXT_CAPABILITIES) begin
                                    response_status <= 0;
                                    response_data <= 32'h0000_001f;
                                end else if (ext_opcode == EXT_READ32) begin
                                    response_status <= 0;
                                    response_data <= debug_rdata;
                                    debug_valid <= 1;
                                end else if (ext_opcode == EXT_WRITE32) begin
                                    response_status <= 0;
                                    response_data <= ext_value;
                                    debug_valid <= 1;
                                    debug_write <= 1;
                                end else if (ext_opcode == EXT_SET_BAUD &&
                                             (ext_value == 32'd2000000 ||
                                              ext_value == 32'd5000000)) begin
                                    response_status <= 0;
                                    response_data <= ext_value;
                                end else begin
                                    response_status <= 8'd2;
                                    response_data <= 0;
                                    debug_bad_requests <= debug_bad_requests + 1'b1;
                                end
                                response_req <= ~response_req;
                                recv_state <= RECV_RESPONSE_ACK;
                            end
                            default: ;
                        endcase
                    end
                    BLOCK_COMMAND: begin
                        if (data_cnt_before_block)
                            ext_crc <= crc16_byte(ext_crc, rx_data);
                        case (data_cnt)
                            0: ext_version <= rx_data;
                            1: ext_opcode <= rx_data;
                            2: ext_sequence[15:8] <= rx_data;
                            3: ext_sequence[7:0] <= rx_data;
                            4: ext_address[31:24] <= rx_data;
                            5: ext_address[23:16] <= rx_data;
                            6: ext_address[15:8] <= rx_data;
                            7: ext_address[7:0] <= rx_data;
                            8: begin
                                block_word_count <= rx_data[6:0];
                                block_length_ok <= rx_data != 0 &&
                                    rx_data <= BLOCK_MAX_WORDS &&
                                    len_reg == 16'd12 + {6'b0, rx_data, 2'b0};
                            end
                            default: ;
                        endcase
                        // Data bytes start at payload offset 9; every fourth
                        // byte completes one big-endian word.
                        if (data_cnt >= 9 && data_cnt_before_block &&
                            data_cnt < 9 + 4 * BLOCK_MAX_WORDS && data_cnt[1:0] == 2'd0) begin
                            block_buffer_write <= 1;
                            block_buffer_write_address <= 6'((data_cnt - 16'd9) >> 2);
                            block_buffer_write_data <= {data_reg[23:0], rx_data};
                        end
                        if (data_cnt_at_block)
                            ext_crc_received[15:8] <= rx_data;
                        if (data_cnt_last) begin
                            response_type <= EXT_COMMAND;
                            response_opcode <= ext_opcode;
                            response_sequence <= ext_sequence;
                            response_address <= ext_address;
                            response_data <= {25'b0, block_word_count};
                            if (len_reg < 16'd12) begin
                                // Too short for the header and CRC; drop it
                                // like a malformed-length extended request.
                                debug_bad_requests <= debug_bad_requests + 1'b1;
                            end else if (ext_crc != {ext_crc_received[15:8], rx_data}) begin
                                response_status <= 8'd3;
                                debug_crc_errors <= debug_crc_errors + 1'b1;
                                response_req <= ~response_req;
                                recv_state <= RECV_RESPONSE_ACK;
                            end else if (ext_version != EXT_VERSION) begin
                                response_status <= 8'd1;
                                debug_bad_requests <= debug_bad_requests + 1'b1;
                                response_req <= ~response_req;
                                recv_state <= RECV_RESPONSE_ACK;
                            end else if (ext_opcode != EXT_WRITE_BLOCK || !block_length_ok ||
                                         ext_address[1:0] != 2'b00) begin
                                response_status <= 8'd2;
                                debug_bad_requests <= debug_bad_requests + 1'b1;
                                response_req <= ~response_req;
                                recv_state <= RECV_RESPONSE_ACK;
                            end else begin
                                response_status <= 0;
                                block_replay_index <= 0;
                                block_replay_primed <= 0;
                                block_replay_address <= ext_address;
                                recv_state <= RECV_BLOCK_WRITE;
                            end
                        end
                    end
                    STREAM_COMMAND: begin
                        if (data_cnt <= 9 || data_cnt_before_crc)
                            stream_crc_rx <= crc16_byte(stream_crc_rx, rx_data);

                        case (data_cnt)
                            0: ext_version <= rx_data;
                            1: stream_flags_rx <= rx_data;
                            2: stream_id_rx[15:8] <= rx_data;
                            3: stream_id_rx[7:0] <= rx_data;
                            4: stream_offset_rx[31:24] <= rx_data;
                            5: stream_offset_rx[23:16] <= rx_data;
                            6: stream_offset_rx[15:8] <= rx_data;
                            7: stream_offset_rx[7:0] <= rx_data;
                            8: stream_length_rx[15:8] <= rx_data;
                            9: begin
                                stream_length_rx[7:0] <= rx_data;
                                stream_crc_high_index <=
                                    17'd10 + {1'b0, stream_length_rx[15:8], rx_data};
                                stream_crc_low_index <=
                                    17'd11 + {1'b0, stream_length_rx[15:8], rx_data};
                                stream_frame_length_ok <=
                                    len_reg == {stream_length_rx[15:8], rx_data} + 16'd13 &&
                                    {stream_length_rx[15:8], rx_data} <= STREAM_CREDIT;
                            end
                            default: begin
                                if (data_cnt_before_crc &&
                                    data_cnt < 10 + STREAM_CREDIT) begin
                                    stream_buffer_write <= 1;
                                    stream_buffer_write_address <= data_cnt[9:0] - 10'd10;
                                    stream_buffer_write_data <= rx_data;
                                end else if (data_cnt_at_crc_high)
                                    stream_crc_received[15:8] <= rx_data;
                                else if (data_cnt_at_crc_low) begin
                                    stream_crc_received[7:0] <= rx_data;
                                    stream_response_flags <= stream_flags_rx;
                                    stream_response_id <= stream_id_rx;
                                    stream_response_next_offset <= stream_expected_offset;
                                    stream_response_credit <= STREAM_CREDIT;

                                    if (!stream_frame_length_ok) begin
                                        stream_response_status <= 8'd2;
                                        stream_ack_pending <= 1;
                                        debug_bad_requests <= debug_bad_requests + 1'b1;
                                    end else if (stream_crc_rx !=
                                                 {stream_crc_received[15:8], rx_data}) begin
                                        stream_response_status <= 8'd3;
                                        stream_ack_pending <= 1;
                                        debug_crc_errors <= debug_crc_errors + 1'b1;
                                    end else if (ext_version != STREAM_VERSION) begin
                                        stream_response_status <= 8'd1;
                                        stream_ack_pending <= 1;
                                        debug_bad_requests <= debug_bad_requests + 1'b1;
                                    end else if (stream_flags_rx == STREAM_START &&
                                                 stream_length_rx == 0) begin
                                        stream_response_status <= 0;
                                        stream_response_next_offset <= 0;
                                        stream_session_active <= 1;
                                        stream_active_id <= stream_id_rx;
                                        stream_expected_offset <= 0;
                                        stream_id <= stream_id_rx;
                                        stream_offset <= 0;
                                        stream_start <= 1;
                                        stream_ack_pending <= 1;
                                    end else if (stream_flags_rx == STREAM_DATA &&
                                                 stream_length_rx != 0 &&
                                                 stream_session_active &&
                                                 stream_id_rx == stream_active_id &&
                                                 stream_offset_rx == stream_expected_offset &&
                                                 !stream_buffer_active) begin
                                        stream_response_status <= 0;
                                        stream_response_credit <= 0;
                                        stream_buffer_active <= 1;
                                        stream_buffer_length <= stream_length_rx[10:0];
                                        stream_read_index <= 0;
                                        stream_id <= stream_id_rx;
                                        stream_offset <= stream_offset_rx;
                                    end else if (stream_flags_rx == STREAM_END &&
                                                 stream_length_rx == 0 &&
                                                 stream_session_active &&
                                                 stream_id_rx == stream_active_id &&
                                                 stream_offset_rx == stream_expected_offset) begin
                                        stream_response_status <= 0;
                                        stream_response_next_offset <= stream_expected_offset;
                                        stream_response_credit <= 0;
                                        stream_session_active <= 0;
                                        stream_id <= stream_id_rx;
                                        stream_offset <= stream_offset_rx;
                                        stream_end <= 1;
                                        stream_ack_pending <= 1;
                                    end else if (stream_flags_rx == STREAM_CANCEL &&
                                                 stream_length_rx == 0) begin
                                        stream_response_status <= 0;
                                        stream_response_credit <= 0;
                                        stream_session_active <= 0;
                                        stream_buffer_active <= 0;
                                        stream_read_index <= 0;
                                        stream_id <= stream_id_rx;
                                        stream_offset <= stream_offset_rx;
                                        stream_cancel <= 1;
                                        stream_ack_pending <= 1;
                                    end else begin
                                        stream_response_status <= 8'd2;
                                        stream_ack_pending <= 1;
                                        debug_bad_requests <= debug_bad_requests + 1'b1;
                                    end
                                end
                            end
                        endcase
                    end
                    default: begin
                        // unknown command: consume all data and return
                    end
                endcase
            end

            RECV_RESPONSE_REQ:                      // request to send config string
                case (cmd_reg)
                    1,2: begin                      // 1: core ID, 2: config string
                        response_type <= cmd_reg;
                        response_req <= ~response_req;
                        recv_state <= RECV_RESPONSE_ACK;
                    end
                    default:
                        recv_state <= RECV_IDLE;
                endcase

            RECV_RESPONSE_ACK:                      // wait for TX to finish
                if (response_req == response_ack) begin
                    recv_state <= RECV_IDLE;
                end

            // One word per cycle from the validated block buffer.  The read
            // port leads the replay index by one word once primed.
            RECV_BLOCK_WRITE:
                if (!block_replay_primed) begin
                    block_replay_primed <= 1;
                end else begin
                    debug_valid <= 1;
                    debug_write <= 1;
                    debug_address <= block_replay_address;
                    debug_wdata <= block_buffer_read_data;
                    block_replay_address <= block_replay_address + 32'd4;
                    block_replay_index <= block_replay_index + 1'b1;
                    if (block_replay_index + 1'b1 == block_word_count) begin
                        response_req <= ~response_req;
                        recv_state <= RECV_RESPONSE_ACK;
                    end
                end
        endcase
        
    end
end

localparam SEND_IDLE = 0;

localparam SEND_CORE_ID = 1;        // doubles as response type in message header
localparam SEND_CONFIG_STRING = 2;
localparam SEND_JOYPAD = 3;
localparam SEND_FDD_WRITE = 4;
localparam SEND_FDD_READ = 5;

localparam SEND_HEADER = 6;
localparam SEND_DONE = 7;
localparam SEND_DEBUG = 8;
localparam SEND_BAUD_WAIT = 9;
localparam SEND_STREAM_ACK = 10;

reg [3:0] send_state, send_state_next;
reg [7:0] resp_type;
localparam integer FDD_WRITE_LAST_INDEX = 512 + 1;
localparam integer SEND_INDEX_COUNT =
    (STR_LEN > FDD_WRITE_LAST_INDEX + 1) ? STR_LEN : FDD_WRITE_LAST_INDEX + 1;
localparam integer SEND_INDEX_WIDTH = $clog2(SEND_INDEX_COUNT);
localparam [SEND_INDEX_WIDTH-1:0] FDD_WRITE_LAST =
    SEND_INDEX_WIDTH'(FDD_WRITE_LAST_INDEX);
reg [SEND_INDEX_WIDTH-1:0] send_idx;
localparam integer JOY_UPDATE_INTERVAL = FREQ / 50; // 20ms interval for 50Hz
localparam integer JOY_TIMER_WIDTH = $clog2(JOY_UPDATE_INTERVAL + 1);
localparam [JOY_TIMER_WIDTH-1:0] JOY_UPDATE_RELOAD =
    JOY_TIMER_WIDTH'(JOY_UPDATE_INTERVAL);
reg [JOY_TIMER_WIDTH-1:0] joy_timer;
reg [15:0] joy1_reg;
reg [15:0] joy2_reg;
reg [15:0] resp_frame_len;
reg baud_wait_seen_busy;

// UART TX: command responses, joystick updates and FDD requests
always @(posedge clk) begin
    if (!resetn) begin
        joy_timer <= 0;
        send_state <= 0;
        tx_valid <= 0;
        response_ack <= 0;
        baud_fast <= 0;
        baud_wait_seen_busy <= 0;
    end else begin
        tx_valid <= 0;
        mgmt_read <= 0;
        fdd_read_start <= 0;
        fdd_write_finish <= 0;
        
        // Joypad state transmission logic
        joy_timer <= joy_timer == 0 ? 0 : joy_timer - 1;

        // UART transmission state machine
        case (send_state)
            SEND_IDLE: begin
                send_idx <= 0;
                if (joy_timer == 0 && (joy1 != joy1_reg || joy2 != joy2_reg)) begin
                    joy_timer <= JOY_UPDATE_RELOAD;
                    joy1_reg <= joy1;
                    joy2_reg <= joy2;
                    send_state_next <= SEND_JOYPAD;
                    resp_type <= SEND_JOYPAD;
                    send_state <= SEND_HEADER;
                    resp_frame_len <= 5;
                end else if (fdd_request[1] && fdd_state == FDD_READY) begin
                    send_state_next <= SEND_FDD_WRITE;
                    resp_type <= SEND_FDD_WRITE;
                    send_state <= SEND_HEADER;
                    mgmt_address_tx <= 16'hf200;    // read {drive, sector}
                    resp_frame_len <= 515;
                end else if (fdd_request[0] && fdd_state == FDD_READY) begin
                    send_state_next <= SEND_FDD_READ;
                    resp_type <= SEND_FDD_READ;
                    send_state <= SEND_HEADER;
                    mgmt_address_tx <= 16'hf200;    // read {drive, sector}
                    resp_frame_len <= 3;
                end else if (response_req != response_ack) begin
                    if (response_type == EXT_COMMAND) begin
                        send_state_next <= SEND_DEBUG;
                        resp_type <= EXT_COMMAND;
                        send_state <= SEND_HEADER;
                        resp_frame_len <= 16;
                    end else if (response_type == STREAM_COMMAND) begin
                        send_state_next <= SEND_STREAM_ACK;
                        resp_type <= STREAM_COMMAND;
                        send_state <= SEND_HEADER;
                        resp_frame_len <= 14;
                    end else if (response_type == 2) begin
                        send_state_next <= SEND_CONFIG_STRING;
                        resp_type <= SEND_CONFIG_STRING;
                        send_state <= SEND_HEADER;
                        resp_frame_len <= STR_LEN + 1;
                    end else if (response_type == 1) begin
                        send_state_next <= SEND_CORE_ID;
                        resp_type <= SEND_CORE_ID;
                        send_state <= SEND_HEADER;
                        resp_frame_len <= 2;
                    end
                end
            end

            SEND_HEADER: begin              // 4 byte header: 0xAA, resp_frame_len[15:0], resp_type[7:0]
                if (tx_ready && ~tx_valid) begin
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    case (send_idx[1:0])
                        0: tx_data <= 8'hAA;
                        1: tx_data <= resp_frame_len[15:8];
                        2: tx_data <= resp_frame_len[7:0];
                        3: begin
                            tx_data <= resp_type;
                            send_state <= send_state_next;
                            send_idx <= 0;
                        end
                        default: ;
                    endcase
                end
            end

            SEND_CORE_ID: begin
                if (tx_ready && ~tx_valid) begin
                    tx_data <= CORE_ID[7:0];
                    tx_valid <= 1;
                    send_state <= SEND_IDLE;
                    response_ack <= response_req;
                end
            end

            SEND_CONFIG_STRING: begin
                if (tx_ready && ~tx_valid) begin
                    tx_data <= CONF_STR[8*(STR_LEN - send_idx - 1) +: 8];
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    if (send_idx == STR_LEN-1) begin
                        send_state <= SEND_IDLE;
                        response_ack <= response_req;
                    end
                end
            end

            SEND_JOYPAD: begin
                if (tx_ready && ~tx_valid) begin
                    case (send_idx)
                        0: tx_data <= joy1_reg[15:8]; // Joy1 high byte
                        1: tx_data <= joy1_reg[7:0];  // Joy1 low byte
                        2: tx_data <= joy2_reg[15:8]; // Joy2 high byte
                        3: tx_data <= joy2_reg[7:0];  // Joy2 low byte
                        default: ;
                    endcase
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    if (send_idx == 3) begin
                        send_state <= SEND_IDLE;
                    end
                end
            end

            SEND_DEBUG: begin
                if (tx_ready && ~tx_valid) begin
                    case (send_idx)
                        0: tx_data <= EXT_VERSION;
                        1: tx_data <= response_opcode | 8'h80;
                        2: tx_data <= response_status;
                        3: tx_data <= response_sequence[15:8];
                        4: tx_data <= response_sequence[7:0];
                        5: tx_data <= response_address[31:24];
                        6: tx_data <= response_address[23:16];
                        7: tx_data <= response_address[15:8];
                        8: tx_data <= response_address[7:0];
                        9: tx_data <= response_data[31:24];
                        10: tx_data <= response_data[23:16];
                        11: tx_data <= response_data[15:8];
                        12: tx_data <= response_data[7:0];
                        13: tx_data <= response_crc[15:8];
                        14: tx_data <= response_crc[7:0];
                        default: tx_data <= 0;
                    endcase
                    tx_valid <= 1;
                    send_idx <= send_idx + 1'b1;
                    if (send_idx == 14) begin
                        if (response_opcode == EXT_SET_BAUD && response_status == 0) begin
                            send_state <= SEND_BAUD_WAIT;
                            baud_wait_seen_busy <= 0;
                        end else begin
                            send_state <= SEND_IDLE;
                            response_ack <= response_req;
                        end
                    end
                end
            end

            SEND_BAUD_WAIT: begin
                if (tx_busy)
                    baud_wait_seen_busy <= 1;
                else if (baud_wait_seen_busy) begin
                    baud_fast <= (response_data == 32'd5000000);
                    response_ack <= response_req;
                    send_state <= SEND_IDLE;
                end
            end

            SEND_STREAM_ACK: begin
                if (tx_ready && ~tx_valid) begin
                    case (send_idx)
                        0: tx_data <= STREAM_VERSION;
                        1: tx_data <= stream_response_status;
                        2: tx_data <= stream_response_flags;
                        3: tx_data <= stream_response_id[15:8];
                        4: tx_data <= stream_response_id[7:0];
                        5: tx_data <= stream_response_next_offset[31:24];
                        6: tx_data <= stream_response_next_offset[23:16];
                        7: tx_data <= stream_response_next_offset[15:8];
                        8: tx_data <= stream_response_next_offset[7:0];
                        9: tx_data <= stream_response_credit[15:8];
                        10: tx_data <= stream_response_credit[7:0];
                        11: tx_data <= stream_response_crc_value[15:8];
                        12: tx_data <= stream_response_crc_value[7:0];
                        default: tx_data <= 0;
                    endcase
                    tx_valid <= 1;
                    send_idx <= send_idx + 1'b1;
                    if (send_idx == 12) begin
                        send_state <= SEND_IDLE;
                        response_ack <= response_req;
                    end
                end
            end

            // fdd write. Send {drive, sector} followed by 512 bytes data to bl616
            SEND_FDD_WRITE: begin
                if (tx_ready && ~tx_valid) begin
                    case (send_idx)
                        0: tx_data <= mgmt_readdata[15:8];  // sector number
                        1: begin
                            tx_data <= mgmt_readdata[7:0];  // sector number
                            mgmt_address_tx <= 16'hf20f;    // start reading FIFO data
                        end
                        default: begin 
                            tx_data <= mgmt_readdata[7:0];  // send FIFO data
                            mgmt_read <= '1;                // advance FIFO pointer
                        end
                    endcase
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    if (send_idx == FDD_WRITE_LAST) begin
                        send_state <= SEND_DONE;
                        fdd_write_finish <= 1;              // notify FDD state machine
                    end
                end
            end

            // FDD read. Just second the sector number. BL616 will send the data later via command 0x0b.
            SEND_FDD_READ: begin
                if (tx_ready && ~tx_valid) begin
                    case (send_idx)
                        0: tx_data <= mgmt_readdata[15:8];
                        1: tx_data <= mgmt_readdata[7:0];
                        default: ;
                    endcase
                    tx_valid <= 1;
                    send_idx <= send_idx + 1;
                    if (send_idx == 1) begin
                        send_state <= SEND_DONE;
                        fdd_read_start <= 1;                // notify FDD state machine
                    end
                end
            end

            SEND_DONE: send_state <= SEND_IDLE;     // extra state for fdd_state to transition
        endcase
    end
end

// FDD state machine. UART TX only serves FDD requests when fdd_state == FDD_READY.
reg [3:0] fdd_cnt;
always @(posedge clk) begin
    if (!resetn) begin
        fdd_state <= FDD_READY;
    end else case (fdd_state)
        FDD_READY: begin
            if (fdd_read_start) begin
                fdd_state <= FDD_READ_WAIT;
            end else if (fdd_write_finish) begin
                fdd_state <= FDD_DONE_WAIT;
                fdd_cnt <= 15;
            end
        end
        FDD_READ_WAIT: begin
            if (fdd_read_finish) begin
                fdd_state <= FDD_DONE_WAIT;
                fdd_cnt <= 15;
            end
        end
        FDD_DONE_WAIT: begin            // delay 15 cycles before we serve floppy requests again
            fdd_cnt <= fdd_cnt - 1;
            if (fdd_cnt == 0) begin
                fdd_state <= FDD_READY;
            end
        end
    endcase
end

// text display
`ifndef SIM
wire [31:0] reg_char_di = {8'b0, x_wr, y_wr, char_wr};
wire [3:0] reg_char_we = {4{we}};

textdisp #(.COLOR_LOGO(COLOR_LOGO)) disp (
    .clk(clk), .hclk(hclk), .resetn(resetn),
    .x(overlay_x), .y(overlay_y), .color(overlay_color),
    .reg_char_di(reg_char_di), .reg_char_we(reg_char_we)
);
`endif

endmodule
