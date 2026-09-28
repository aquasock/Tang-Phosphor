`timescale 1ns/1ps

module phosphor_time_digits_tb;
logic clk = 0;
logic resetn = 0;
logic [31:0] seconds_value = 0;
logic [23:0] digits;

always #5 clk = ~clk;

phosphor_time_digits dut (
    .clk(clk), .resetn(resetn), .seconds_value(seconds_value), .digits(digits)
);

initial begin
    repeat (3) @(negedge clk);
    resetn = 1;
    seconds_value = 32'd3723;
    repeat (80) @(negedge clk);
    if (digits !== 24'h010203)
        $fatal(1, "01:02:03 conversion was %h", digits);

    seconds_value = 32'hffff_ffff;
    repeat (180) @(negedge clk);
    if (digits !== 24'h995959)
        $fatal(1, "bounded 99:59:59 conversion was %h", digits);

    $display("PASS Phosphor sequential HH:MM:SS conversion");
    $finish;
end
endmodule
