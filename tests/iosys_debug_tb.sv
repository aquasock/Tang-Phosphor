`timescale 1ns/1ps

module iosys_debug_tb;

localparam integer CLOCK_HZ = 40_000_000;

reg clk = 0;
always #12.5 clk = ~clk;

reg resetn = 0;
reg uart_rx = 1;
wire uart_tx;
wire debug_valid;
wire debug_write;
wire [31:0] debug_address;
wire [31:0] debug_wdata;
reg [31:0] scratch = 0;
wire [31:0] debug_rdata = (debug_address == 32'h20) ? scratch : 32'h5450_4830;

wire overlay;
wire [14:0] overlay_color;
wire [15:0] hid1;
wire [15:0] hid2;
reg [11:0] joy1 = 0;
reg [11:0] joy2 = 0;
reg [1:0] fdd_request = 0;
wire [7:0] rom_loading;
wire [7:0] rom_do;
wire rom_do_valid;
wire [15:0] mgmt_address;
wire mgmt_read;
wire mgmt_write;
wire [15:0] mgmt_writedata;
wire [15:0] mgmt_readdata = (mgmt_address == 16'hf200) ? 16'h1234 : 16'h005a;
wire [7:0] kbd_data;
wire kbd_data_valid;
wire [31:0] core_config;
wire [31:0] debug_crc_errors;
wire [31:0] debug_bad_requests;
wire stream_start;
wire stream_end;
wire stream_cancel;
wire [15:0] stream_id;
wire [31:0] stream_offset;
wire [7:0] stream_data;
wire stream_valid;
reg [31:0] stream_word = 0;
integer stream_byte_count = 0;
integer stream_start_count = 0;
integer stream_end_count = 0;
integer mgmt_read_count = 0;
reg stream_ready = 1;
integer bus_writes = 0;
integer cycle = 0;
integer bus_cycle [0:127];
reg [31:0] bus_address [0:127];
reg [31:0] bus_data [0:127];

iosys_bl616 #(.FREQ(CLOCK_HZ), .CORE_ID(16'h0050)) dut (
    .clk(clk), .hclk(clk), .resetn(resetn),
    .overlay(overlay), .overlay_x(8'b0), .overlay_y(8'b0),
    .overlay_color(overlay_color), .joy1(joy1), .joy2(joy2),
    .hid1(hid1), .hid2(hid2),
    .rom_loading(rom_loading), .rom_do(rom_do), .rom_do_valid(rom_do_valid),
    .mgmt_address(mgmt_address), .mgmt_read(mgmt_read), .mgmt_readdata(mgmt_readdata),
    .mgmt_write(mgmt_write), .mgmt_writedata(mgmt_writedata), .fdd_request(fdd_request),
    .kbd_data(kbd_data), .kbd_data_valid(kbd_data_valid),
    .core_config(core_config),
    .debug_valid(debug_valid), .debug_write(debug_write),
    .debug_address(debug_address), .debug_wdata(debug_wdata),
    .debug_rdata(debug_rdata), .debug_crc_errors(debug_crc_errors),
    .debug_bad_requests(debug_bad_requests),
    .stream_start(stream_start), .stream_end(stream_end),
    .stream_cancel(stream_cancel), .stream_id(stream_id),
    .stream_offset(stream_offset), .stream_data(stream_data),
    .stream_valid(stream_valid), .stream_ready(stream_ready),
    .uart_rx(uart_rx), .uart_tx(uart_tx)
);

always @(posedge clk)
    if (debug_valid && debug_write && debug_address == 32'h20)
        scratch <= debug_wdata;

// Record every register write and the cycle on which it occurred.
always @(posedge clk) begin
    cycle <= cycle + 1;
    if (debug_valid && debug_write) begin
        bus_cycle[bus_writes % 128] <= cycle;
        bus_address[bus_writes % 128] <= debug_address;
        bus_data[bus_writes % 128] <= debug_wdata;
        bus_writes <= bus_writes + 1;
    end
end

always @(posedge clk) begin
    if (stream_start)
        stream_start_count <= stream_start_count + 1;
    if (stream_end)
        stream_end_count <= stream_end_count + 1;
    if (mgmt_read)
        mgmt_read_count <= mgmt_read_count + 1;
    if (stream_valid && stream_ready) begin
        stream_word <= {stream_word[23:0], stream_data};
        stream_byte_count <= stream_byte_count + 1;
    end
end

`ifdef TRACE_TEST
always @(posedge clk) begin
    if (dut.rx_valid)
        $display("RX state=%02x data=%02x count=%0d", dut.recv_state, dut.rx_data, dut.data_cnt);
    if (dut.tx_valid)
        $display("TX state=%0d data=%02x", dut.send_state, dut.tx_data);
end
`endif

function automatic [15:0] crc_byte(input [15:0] initial_crc, input [7:0] data);
    integer i;
    reg [15:0] crc;
    begin
        crc = initial_crc ^ {data, 8'b0};
        for (i = 0; i < 8; i = i + 1)
            crc = crc[15] ? (crc << 1) ^ 16'h1021 : crc << 1;
        crc_byte = crc;
    end
endfunction

task automatic send_byte(input [7:0] value);
    begin
        @(negedge clk);
        dut.uart_receiver_slow.RxD_data = value;
        dut.uart_receiver_fast.RxD_data = value;
        dut.uart_receiver_slow.RxD_data_ready = 1'b1;
        dut.uart_receiver_fast.RxD_data_ready = 1'b1;
        @(negedge clk);
        dut.uart_receiver_slow.RxD_data_ready = 1'b0;
        dut.uart_receiver_fast.RxD_data_ready = 1'b0;
    end
endtask

task automatic check_joypad_response(
    input [15:0] expected_joy1,
    input [15:0] expected_joy2
);
    integer i;
    reg [7:0] bytes [0:7];
    begin
        for (i = 0; i < 8; i = i + 1)
            receive_byte(bytes[i]);
        if (bytes[0] !== 8'haa || bytes[1] !== 0 || bytes[2] !== 5 ||
            bytes[3] !== 3 || {bytes[4], bytes[5]} !== expected_joy1 ||
            {bytes[6], bytes[7]} !== expected_joy2)
            $fatal(1, "FAIL joypad response");
    end
endtask

task automatic check_fdd_write_response;
    integer i;
    reg [7:0] value;
    begin
        receive_byte(value);
        if (value !== 8'haa)
            $fatal(1, "FAIL FDD write sync");
        receive_byte(value);
        if (value !== 8'h02)
            $fatal(1, "FAIL FDD write length high");
        receive_byte(value);
        if (value !== 8'h03)
            $fatal(1, "FAIL FDD write length low");
        receive_byte(value);
        if (value !== 8'h04)
            $fatal(1, "FAIL FDD write response type");
        receive_byte(value);
        if (value !== 8'h12)
            $fatal(1, "FAIL FDD write sector high");
        receive_byte(value);
        if (value !== 8'h34)
            $fatal(1, "FAIL FDD write sector low");
        for (i = 0; i < 512; i = i + 1) begin
            receive_byte(value);
            if (value !== 8'h5a)
                $fatal(1, "FAIL FDD write data byte %0d", i);
        end
    end
endtask

task automatic send_stream_request(
    input [7:0] flags,
    input [15:0] identifier,
    input [31:0] offset,
    input [15:0] length,
    input [31:0] data
);
    integer i;
    reg [7:0] byte_value;
    reg [15:0] crc;
    begin
        repeat (4) @(posedge clk);
        crc = crc_byte(16'hffff, 8'h11);
        crc = crc_byte(crc, 8'h01);
        crc = crc_byte(crc, flags);
        crc = crc_byte(crc, identifier[15:8]);
        crc = crc_byte(crc, identifier[7:0]);
        crc = crc_byte(crc, offset[31:24]);
        crc = crc_byte(crc, offset[23:16]);
        crc = crc_byte(crc, offset[15:8]);
        crc = crc_byte(crc, offset[7:0]);
        crc = crc_byte(crc, length[15:8]);
        crc = crc_byte(crc, length[7:0]);

        send_byte(8'haa); send_byte((length + 13) >> 8);
        send_byte(length + 13); send_byte(8'h11);
        send_byte(8'h01); send_byte(flags);
        send_byte(identifier[15:8]); send_byte(identifier[7:0]);
        send_byte(offset[31:24]); send_byte(offset[23:16]);
        send_byte(offset[15:8]); send_byte(offset[7:0]);
        send_byte(length[15:8]); send_byte(length[7:0]);
        for (i = 0; i < length; i = i + 1) begin
            byte_value = data[8*(length-i)-1 -: 8];
            crc = crc_byte(crc, byte_value);
            send_byte(byte_value);
        end
        send_byte(crc[15:8]); send_byte(crc[7:0]);
    end
endtask

task automatic check_stream_response(
    input [7:0] flags,
    input [7:0] status,
    input [15:0] identifier,
    input [31:0] next_offset,
    input [15:0] credit
);
    integer i;
    reg [7:0] bytes [0:16];
    reg [15:0] crc;
    begin
        for (i = 0; i < 17; i = i + 1)
            receive_byte(bytes[i]);
        if (bytes[0] !== 8'haa || bytes[1] !== 0 || bytes[2] !== 14 ||
            bytes[3] !== 8'h11 || bytes[4] !== 1 || bytes[5] !== status ||
            bytes[6] !== flags || {bytes[7], bytes[8]} !== identifier ||
            {bytes[9], bytes[10], bytes[11], bytes[12]} !== next_offset ||
            {bytes[13], bytes[14]} !== credit) begin
            $display("FAIL stream response fields");
            $fatal(1);
        end
        crc = 16'hffff;
        for (i = 3; i <= 14; i = i + 1)
            crc = crc_byte(crc, bytes[i]);
        if ({bytes[15], bytes[16]} !== crc)
            $fatal(1, "FAIL stream response CRC");
    end
endtask

task automatic receive_byte(output [7:0] value);
    begin
        @(posedge dut.tx_valid);
        value = dut.tx_data;
    end
endtask

task automatic send_request(
    input [7:0] opcode,
    input [15:0] transaction,
    input [31:0] address,
    input [31:0] data,
    input corrupt_crc
);
    reg [15:0] crc;
    begin
        // Allow the response-acknowledge state to return to idle between
        // back-to-back transactions.
        repeat (4) @(posedge clk);
        crc = crc_byte(16'hffff, 8'h10);
        crc = crc_byte(crc, 8'h01);
        crc = crc_byte(crc, opcode);
        crc = crc_byte(crc, transaction[15:8]);
        crc = crc_byte(crc, transaction[7:0]);
        crc = crc_byte(crc, address[31:24]);
        crc = crc_byte(crc, address[23:16]);
        crc = crc_byte(crc, address[15:8]);
        crc = crc_byte(crc, address[7:0]);
        crc = crc_byte(crc, data[31:24]);
        crc = crc_byte(crc, data[23:16]);
        crc = crc_byte(crc, data[15:8]);
        crc = crc_byte(crc, data[7:0]);
        if (corrupt_crc)
            crc = crc ^ 16'h0001;

        send_byte(8'haa); send_byte(8'h00); send_byte(8'h0f); send_byte(8'h10);
        send_byte(8'h01); send_byte(opcode);
        send_byte(transaction[15:8]); send_byte(transaction[7:0]);
        send_byte(address[31:24]); send_byte(address[23:16]);
        send_byte(address[15:8]); send_byte(address[7:0]);
        send_byte(data[31:24]); send_byte(data[23:16]);
        send_byte(data[15:8]); send_byte(data[7:0]);
        send_byte(crc[15:8]); send_byte(crc[7:0]);
    end
endtask

function automatic [31:0] block_word(input [7:0] seed, input integer index);
    block_word = {seed, index[7:0], ~index[7:0], seed ^ index[7:0]};
endfunction

// corrupt: 0 none, 1 CRC, 2 header count exceeds the carried words
task automatic send_block_request(
    input [7:0] opcode,
    input [15:0] transaction,
    input [31:0] address,
    input [7:0] count,
    input [7:0] seed,
    input integer corrupt
);
    integer i, j, words;
    reg [15:0] crc;
    reg [15:0] frame_length;
    reg [31:0] value;
    reg [7:0] header [0:8];
    begin
        repeat (4) @(posedge clk);
        words = corrupt == 2 ? count - 1 : count;
        frame_length = 12 + 4 * words;
        header[0] = 8'h01; header[1] = opcode;
        header[2] = transaction[15:8]; header[3] = transaction[7:0];
        header[4] = address[31:24]; header[5] = address[23:16];
        header[6] = address[15:8]; header[7] = address[7:0];
        header[8] = count;
        crc = crc_byte(16'hffff, 8'h12);
        send_byte(8'haa); send_byte(frame_length[15:8]);
        send_byte(frame_length[7:0]); send_byte(8'h12);
        for (i = 0; i < 9; i = i + 1) begin
            crc = crc_byte(crc, header[i]);
            send_byte(header[i]);
        end
        for (i = 0; i < words; i = i + 1) begin
            value = block_word(seed, i);
            for (j = 3; j >= 0; j = j - 1) begin
                crc = crc_byte(crc, value[8*j +: 8]);
                send_byte(value[8*j +: 8]);
            end
        end
        if (corrupt == 1)
            crc = crc ^ 16'h0100;
        send_byte(crc[15:8]); send_byte(crc[7:0]);
    end
endtask

task automatic check_block_writes(
    input integer first,
    input [31:0] address,
    input integer count,
    input [7:0] seed
);
    integer i;
    begin
        if (bus_writes - first !== count)
            $fatal(1, "FAIL block write count %0d, expected %0d", bus_writes - first, count);
        for (i = 0; i < count; i = i + 1)
            if (bus_address[(first + i) % 128] !== address + 4 * i ||
                bus_data[(first + i) % 128] !== block_word(seed, i) ||
                (i != 0 && bus_cycle[(first + i) % 128] !== bus_cycle[(first + i - 1) % 128] + 1))
                $fatal(1, "FAIL block word %0d", i);
    end
endtask

task automatic check_response(
    input [7:0] opcode,
    input [7:0] status,
    input [15:0] transaction,
    input [31:0] address,
    input [31:0] data
);
    integer i;
    reg [7:0] bytes [0:18];
    reg [15:0] crc;
    begin
        for (i = 0; i < 19; i = i + 1)
            receive_byte(bytes[i]);
        if (bytes[0] !== 8'haa || bytes[1] !== 0 || bytes[2] !== 16 ||
            bytes[3] !== 8'h10 || bytes[4] !== 1 ||
            bytes[5] !== (opcode | 8'h80) || bytes[6] !== status ||
            {bytes[7], bytes[8]} !== transaction ||
            {bytes[9], bytes[10], bytes[11], bytes[12]} !== address ||
            {bytes[13], bytes[14], bytes[15], bytes[16]} !== data) begin
            $display("FAIL response fields");
            $fatal(1);
        end
        crc = 16'hffff;
        for (i = 3; i <= 16; i = i + 1)
            crc = crc_byte(crc, bytes[i]);
        if ({bytes[17], bytes[18]} !== crc) begin
            $display("FAIL response CRC");
            $fatal(1);
        end
    end
endtask

initial begin
    #500;
    resetn = 1;
    #1000;

    fork
        send_request(8'h00, 16'h1001, 0, 0, 0);
        check_response(8'h00, 0, 16'h1001, 0, 32'h0000_001f);
    join

    fork
        send_request(8'h02, 16'h1002, 32'h20, 32'h1234_5678, 0);
        check_response(8'h02, 0, 16'h1002, 32'h20, 32'h1234_5678);
    join
    if (scratch !== 32'h1234_5678)
        $fatal(1, "FAIL scratch write");

    fork
        send_request(8'h01, 16'h1003, 32'h20, 0, 0);
        check_response(8'h01, 0, 16'h1003, 32'h20, 32'h1234_5678);
    join

    fork
        send_request(8'h01, 16'h1004, 0, 0, 1);
        check_response(8'h01, 3, 16'h1004, 0, 0);
    join
    if (debug_crc_errors !== 1)
        $fatal(1, "FAIL CRC error counter");

    fork
        send_request(8'h03, 16'h1005, 0, 32'd5000000, 0);
        check_response(8'h03, 0, 16'h1005, 0, 32'd5000000);
    join
    repeat (8) @(posedge clk);
    if (dut.baud_fast !== 1)
        $fatal(1, "FAIL baud switch");

    fork
        send_stream_request(8'h01, 16'h0055, 0, 0, 0);
        check_stream_response(8'h01, 0, 16'h0055, 0, 16'd1024);
    join
    fork
        send_stream_request(8'h02, 16'h0055, 0, 4, 32'hdead_beef);
        check_stream_response(8'h02, 0, 16'h0055, 4, 16'd1024);
    join
    fork
        send_stream_request(8'h04, 16'h0055, 4, 0, 0);
        check_stream_response(8'h04, 0, 16'h0055, 4, 0);
    join
    repeat (4) @(posedge clk);
    if (stream_start_count !== 1 || stream_end_count !== 1 ||
        stream_byte_count !== 4 || stream_word !== 32'hdead_beef)
        $fatal(1, "FAIL stream sink data");

    // Validated block writes replay back-to-back onto the register bus.
    begin : block_writes
        integer first, crc_errors, bad_requests;
        first = bus_writes;
        fork
            send_block_request(8'h04, 16'h2001, 32'h100, 3, 8'h31, 0);
            check_response(8'h04, 0, 16'h2001, 32'h100, 3);
        join
        check_block_writes(first, 32'h100, 3, 8'h31);

        first = bus_writes;
        fork
            send_block_request(8'h04, 16'h2002, 32'h1000, 64, 8'h64, 0);
            check_response(8'h04, 0, 16'h2002, 32'h1000, 64);
        join
        check_block_writes(first, 32'h1000, 64, 8'h64);

        crc_errors = debug_crc_errors;
        bad_requests = debug_bad_requests;
        first = bus_writes;
        fork
            send_block_request(8'h04, 16'h2003, 32'h100, 4, 8'h01, 1);
            check_response(8'h04, 3, 16'h2003, 32'h100, 4);
        join
        fork
            send_block_request(8'h04, 16'h2004, 32'h100, 0, 8'h02, 0);
            check_response(8'h04, 2, 16'h2004, 32'h100, 0);
        join
        fork
            send_block_request(8'h04, 16'h2005, 32'h100, 65, 8'h03, 0);
            check_response(8'h04, 2, 16'h2005, 32'h100, 65);
        join
        fork
            send_block_request(8'h04, 16'h2006, 32'h100, 5, 8'h04, 2);
            check_response(8'h04, 2, 16'h2006, 32'h100, 5);
        join
        fork
            send_block_request(8'h04, 16'h2007, 32'h102, 2, 8'h05, 0);
            check_response(8'h04, 2, 16'h2007, 32'h102, 2);
        join
        fork
            send_block_request(8'h02, 16'h2008, 32'h100, 2, 8'h06, 0);
            check_response(8'h02, 2, 16'h2008, 32'h100, 2);
        join
        repeat (4) @(posedge clk);
        if (bus_writes !== first)
            $fatal(1, "FAIL rejected block frame reached the register bus");
        if (debug_crc_errors !== crc_errors + 1 || debug_bad_requests !== bad_requests + 5)
            $fatal(1, "FAIL block error counters");

        // A block write is serviced while an undrained stream buffer waits
        // for backpressure to clear, and the held stream data is unchanged.
        fork
            send_stream_request(8'h01, 16'h0056, 0, 0, 0);
            check_stream_response(8'h01, 0, 16'h0056, 0, 16'd1024);
        join
        stream_ready = 0;
        stream_byte_count = 0;
        send_stream_request(8'h02, 16'h0056, 0, 4, 32'hcafe_f00d);
        repeat (8) @(posedge clk);
        if (!stream_valid)
            $fatal(1, "FAIL stream buffer did not hold under backpressure");
        first = bus_writes;
        fork
            send_block_request(8'h04, 16'h2009, 32'h200, 8, 8'h77, 0);
            check_response(8'h04, 0, 16'h2009, 32'h200, 8);
        join
        check_block_writes(first, 32'h200, 8, 8'h77);
        if (!stream_valid || stream_byte_count !== 0)
            $fatal(1, "FAIL block write disturbed the held stream buffer");
        fork
            begin
                @(negedge clk);
                stream_ready = 1;
            end
            check_stream_response(8'h02, 0, 16'h0056, 4, 16'd1024);
        join
        repeat (4) @(posedge clk);
        if (stream_byte_count !== 4 || stream_word !== 32'hcafe_f00d)
            $fatal(1, "FAIL stream data after interleaved block write");
    end

    if (dut.JOY_UPDATE_INTERVAL != CLOCK_HZ / 50)
        $fatal(1, "FAIL joypad interval is not derived from FREQ");
    fork
        begin
            @(negedge clk);
            joy1 = 12'ha5a;
        end
        check_joypad_response(16'h0a5a, 16'h0000);
    join

    fork
        begin
            @(negedge clk);
            fdd_request = 2'b10;
            @(posedge dut.fdd_write_finish);
            @(negedge clk);
            fdd_request = 2'b00;
        end
        check_fdd_write_response();
    join
    repeat (4) @(posedge clk);
    if (mgmt_read_count !== 512)
        $fatal(1, "FAIL FDD write consumed %0d FIFO bytes", mgmt_read_count);

    $display("PASS iosys debug, block writes, controller timing, and FDD write protocol");
    $finish;
end

initial begin
    #1000000;
    $fatal(1, "FAIL simulation timeout");
end

endmodule

// Protocol simulation bypasses the already-proven bit-level UART and injects
// bytes at iosys_bl616's byte interface. These stubs keep the test focused on
// framing, CRC, transaction matching, and register-bus behavior.
module async_receiver #(
    parameter ClkFrequency = 25_000_000,
    parameter Baud = 115_200
) (
    input clk,
    input RxD,
    output reg [7:0] RxD_data = 0,
    output reg RxD_data_ready = 0,
    output RxD_idle,
    output RxD_endofpacket
);
assign RxD_idle = 1;
assign RxD_endofpacket = 0;
endmodule

module async_transmitter #(
    parameter ClkFrequency = 25_000_000,
    parameter Baud = 115_200
) (
    input clk,
    input TxD_start,
    input [7:0] TxD_data,
    output TxD,
    output reg TxD_busy = 0
);
assign TxD = 1;
always @(posedge clk)
    TxD_busy <= TxD_start;
endmodule
