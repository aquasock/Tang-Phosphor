`timescale 1ns/1ps

module stream_format_detector_tb;

logic clk = 1'b0;
logic reset = 1'b1;
logic [7:0] input_data = 0;
logic input_valid = 1'b0;
logic input_ready;
logic input_end = 1'b0;
logic [7:0] output_data;
logic output_valid;
logic output_ready;
logic output_end;
logic [2:0] detected_format;
logic format_valid;
logic format_error;
logic [2:0] ready_counter = 0;
logic [7:0] captured [0:31];
integer captured_count = 0;
integer end_count = 0;

always #5 clk = ~clk;
assign output_ready = ready_counter[1:0] != 2'b00;

always_ff @(posedge clk) begin
    if (reset)
        ready_counter <= 0;
    else
        ready_counter <= ready_counter + 1'b1;

    if (output_valid && output_ready) begin
        captured[captured_count] <= output_data;
        captured_count <= captured_count + 1;
    end
    if (output_end)
        end_count <= end_count + 1;
end

stream_format_detector dut (
    .clk(clk), .reset(reset),
    .input_data(input_data), .input_valid(input_valid),
    .input_ready(input_ready), .input_end(input_end),
    .output_data(output_data), .output_valid(output_valid),
    .output_ready(output_ready), .output_end(output_end),
    .detected_format(detected_format), .format_valid(format_valid),
    .format_error(format_error)
);

task automatic restart;
begin
    @(negedge clk);
    reset = 1'b1;
    input_valid = 1'b0;
    input_end = 1'b0;
    captured_count = 0;
    end_count = 0;
    repeat (2) @(negedge clk);
    reset = 1'b0;
end
endtask

task automatic send_byte(input logic [7:0] value);
begin
    @(negedge clk);
    input_data = value;
    input_valid = 1'b1;
    while (!input_ready)
        @(negedge clk);
    @(negedge clk);
    input_valid = 1'b0;
end
endtask

task automatic send_end;
begin
    @(negedge clk);
    input_end = 1'b1;
    @(negedge clk);
    input_end = 1'b0;
end
endtask

task automatic check_byte(input integer index, input logic [7:0] expected);
begin
    if (captured[index] !== expected)
        $fatal(1, "replayed byte %0d was %02x, expected %02x",
            index, captured[index], expected);
end
endtask

initial begin
    restart();

    // Classification consumes all twelve signature bytes before replay. The
    // output-ready cadence stalls replay and then the direct pass-through.
    send_byte("R"); send_byte("I"); send_byte("F"); send_byte("F");
    send_byte(8'h24); send_byte(8'h00); send_byte(8'h00); send_byte(8'h00);
    send_byte("W"); send_byte("A"); send_byte("V"); send_byte("E");
    send_byte(8'hde); send_byte(8'had); send_byte(8'hbe); send_byte(8'hef);
    send_end();
    wait (end_count == 1);
    if (!format_valid || format_error || detected_format !== 3'd1 ||
            captured_count !== 16)
        $fatal(1, "WAV classification/replay status was incorrect");
    check_byte(0, "R"); check_byte(1, "I"); check_byte(2, "F");
    check_byte(3, "F"); check_byte(4, 8'h24); check_byte(5, 8'h00);
    check_byte(6, 8'h00); check_byte(7, 8'h00); check_byte(8, "W");
    check_byte(9, "A"); check_byte(10, "V"); check_byte(11, "E");
    check_byte(12, 8'hde); check_byte(13, 8'had);
    check_byte(14, 8'hbe); check_byte(15, 8'hef);

    restart();
    send_byte("f"); send_byte("L"); send_byte("a"); send_byte("C");
    send_byte(8'h00); send_byte(8'h01); send_byte(8'h02); send_byte(8'h03);
    send_end();
    wait (end_count == 1);
    if (!format_valid || format_error || detected_format !== 3'd2 ||
            captured_count !== 8)
        $fatal(1, "FLAC classification/replay status was incorrect");
    check_byte(0, "f"); check_byte(1, "L"); check_byte(2, "a");
    check_byte(3, "C"); check_byte(4, 8'h00); check_byte(5, 8'h01);
    check_byte(6, 8'h02); check_byte(7, 8'h03);

    restart();
    send_byte("N"); send_byte("O"); send_byte("P"); send_byte("E");
    send_byte(8'h55);
    send_end();
    repeat (3) @(posedge clk);
    if (!format_error || format_valid || detected_format !== 0 ||
            captured_count !== 0)
        $fatal(1, "unknown input was not rejected without output");

    restart();
    send_byte("R"); send_byte("I"); send_byte("F");
    send_end();
    repeat (3) @(posedge clk);
    if (!format_error || format_valid || captured_count !== 0)
        $fatal(1, "short input was not rejected");

    // Reset is the start/cancel boundary and must remove all retained prefix.
    restart();
    send_byte("R"); send_byte("I");
    restart();
    send_byte("f"); send_byte("L"); send_byte("a"); send_byte("C");
    send_end();
    wait (end_count == 1);
    if (!format_valid || format_error || detected_format !== 3'd2 ||
            captured_count !== 4)
        $fatal(1, "reset retained stale prefix state");

    $display("PASS content classification, byte-exact replay, backpressure, EOF, and reset");
    $finish;
end

initial begin
    #1_000_000;
    $fatal(1, "FAIL stream format detector timeout");
end

endmodule
