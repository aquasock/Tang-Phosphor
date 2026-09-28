`timescale 1ns/1ps

module phosphor_ui_control_tb;
logic clk = 0;
logic resetn = 0;
logic request_valid = 0;
logic request_write = 0;
logic [31:0] request_address = 0;
logic [31:0] request_wdata = 0;
logic pause_requested;
logic ui_visible;
logic playlist;
logic [7:0] current_track;
logic [7:0] track_count;
logic [7:0] window_start;
logic [31:0] lengths_0_3;
logic [31:0] lengths_4_7;
logic [7:0] length_8;
logic [8:0] text_address = 0;
logic [7:0] text_data;
logic artwork_valid;
logic [13:0] artwork_address = 0;
logic [7:0] artwork_data;

always #5 clk = ~clk;

phosphor_ui_control dut (
    .clk(clk), .resetn(resetn),
    .request_valid(request_valid), .request_write(request_write),
    .request_address(request_address), .request_wdata(request_wdata),
    .pause_requested(pause_requested), .ui_visible(ui_visible),
    .playlist(playlist), .current_track(current_track),
    .track_count(track_count), .window_start(window_start),
    .lengths_0_3(lengths_0_3), .lengths_4_7(lengths_4_7),
    .length_8(length_8), .text_address(text_address), .text_data(text_data),
    .artwork_valid(artwork_valid), .artwork_address(artwork_address),
    .artwork_data(artwork_data)
);

task automatic write_reg(input logic [31:0] address, input logic [31:0] data);
begin
    @(negedge clk);
    request_address = address;
    request_wdata = data;
    request_valid = 1;
    request_write = 1;
    @(negedge clk);
    request_valid = 0;
    request_write = 0;
end
endtask

initial begin
    repeat (3) @(negedge clk);
    resetn = 1;

    write_reg(32'h78, 1);
    if (!pause_requested)
        $fatal(1, "pause control did not latch");

    write_reg(32'h80, 32'h0003_0904);
    write_reg(32'h84, 32'h0807_0605);
    write_reg(32'h88, 32'h0c0b_0a09);
    write_reg(32'h94, 32'h0d00_0000);
    write_reg(32'h100, 32'h5445_5354);
    write_reg(32'h200, 32'h4c41_5354);
    text_address = 0;
    #1;
    if (text_data === 8'h54)
        $fatal(1, "inactive text bank became visible before commit");

    write_reg(32'h7c, 32'h8000_0003);
    if (!ui_visible || !playlist || current_track != 4 || track_count != 9 ||
        window_start != 3 || lengths_0_3 != 32'h0807_0605 ||
        lengths_4_7 != 32'h0c0b_0a09 || length_8 != 8'h0d)
        $fatal(1, "atomic UI state commit failed");
    text_address = 0;
    repeat (2) @(posedge clk);
    #1;
    if (text_data != "T")
        $fatal(1, "committed text byte 0 mismatch");
    text_address = 3;
    repeat (2) @(posedge clk);
    #1;
    if (text_data != "T")
        $fatal(1, "committed text byte 3 mismatch");
    text_address = 9'd256;
    repeat (2) @(posedge clk);
    #1;
    if (text_data != "L")
        $fatal(1, "ninth text slot mismatch");

    write_reg(32'h1000, 32'he31c_00ff);
    if (artwork_valid)
        $fatal(1, "artwork became valid before commit");
    write_reg(32'h98, 32'h8000_0001);
    artwork_address = 0;
    repeat (2) @(posedge clk);
    #1;
    if (!artwork_valid || artwork_data != 8'he3)
        $fatal(1, "artwork bank commit failed");
    write_reg(32'h98, 0);
    if (artwork_valid)
        $fatal(1, "artwork clear failed");

    write_reg(32'h7c, 32'h0000_0002);
    if (ui_visible || !playlist || current_track != 4)
        $fatal(1, "visibility-only update disturbed committed state");

    $display("PASS Phosphor UI atomic metadata, artwork, and playback controls");
    $finish;
end

endmodule
