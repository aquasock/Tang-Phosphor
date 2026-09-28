`timescale 1ns/1ps

module phosphor_album_ui_tb;

logic clk = 0;
logic resetn = 0;
logic [10:0] x = 0;
logic [9:0] y = 0;
logic [23:0] rgb_in = 24'h123456;
logic visible = 0;
logic playlist = 1;
logic paused = 0;
logic [3:0] player_state = 3;
logic [7:0] current_track = 1;
logic [7:0] track_count = 6;
logic [7:0] window_start = 1;
logic [31:0] lengths_0_3 = 32'h0001_0101;
logic [31:0] lengths_4_7 = 32'h0101_0101;
logic [7:0] length_8 = 1;
logic [8:0] text_address;
logic [7:0] text_data;
logic artwork_valid = 0;
logic [13:0] artwork_address;
logic [7:0] artwork_data = 8'he3;
logic [31:0] samples_played = 50;
logic [35:0] total_samples = 100;
logic [31:0] elapsed_seconds = 1;
logic [31:0] duration_seconds = 2;
logic [23:0] rgb_out;

always #5 clk = ~clk;
always_comb text_data = text_address == 9'd32 ? "A" : "T";

phosphor_album_ui dut (
    .clk(clk), .resetn(resetn), .x(x), .y(y), .rgb_in(rgb_in),
    .visible(visible), .playlist(playlist), .paused(paused),
    .player_state(player_state), .current_track(current_track),
    .track_count(track_count), .window_start(window_start),
    .lengths_0_3(lengths_0_3), .lengths_4_7(lengths_4_7),
    .length_8(length_8), .text_address(text_address), .text_data(text_data),
    .artwork_valid(artwork_valid), .artwork_address(artwork_address),
    .artwork_data(artwork_data),
    .samples_played(samples_played), .total_samples(total_samples),
    .elapsed_seconds(elapsed_seconds), .duration_seconds(duration_seconds),
    .rgb_out(rgb_out)
);

task automatic settle(input integer cycles);
begin
    repeat (cycles) @(posedge clk);
    #1;
end
endtask

task automatic expect_rgb(input logic [23:0] expected, input string label_text);
begin
    if (rgb_out !== expected) begin
        $error("%s: expected %06x, got %06x", label_text, expected, rgb_out);
        $fatal;
    end
end
endtask

initial begin
    settle(2);
    resetn = 1;

    x = 10; y = 10;
    settle(8);
    expect_rgb(24'h123456, "hidden passthrough");
    if (artwork_address != 0)
        $fatal(1, "inactive cover-art address was not clamped");

    visible = 1;
    settle(8);
    expect_rgb(24'h07100c, "native screen background");

    // The simulated P has only font bit 0 set.  The shared TangCore font ROM
    // maps bit 0 to the left edge; checking both edges catches mirror errors.
    x = 186; y = 190;
    settle(8);
    expect_rgb(24'he8f0ec, "glyph left edge uses font bit zero");
    x = 200; y = 190;
    settle(8);
    expect_rgb(24'h0b1812, "glyph right edge leaves font bit seven clear");

    x = 340; y = 680;
    settle(8);
    expect_rgb(24'h07100c, "removed footer legend leaves clean background");

    x = 470; y = 160;
    settle(8);
    expect_rgb(24'h183c2a, "selected playlist row");

    x = 100; y = 570;
    settle(8);
    expect_rgb(24'he8f0ec, "dynamic track glyph");

    artwork_valid = 1;
    x = 158; y = 158;
    settle(8);
    expect_rgb(24'hff00ff, "RGB332 cover-art pixel");
    if (artwork_address != 0)
        $fatal(1, "cover-art origin address mismatch");
    artwork_valid = 0;

    // Trigger the once-per-frame progress calculation, then sample an
    // interior pixel in filled block 10 of 32 at 50 percent completion.
    x = 0; y = 0;
    settle(1);
    x = 428; y = 650;
    settle(40);
    expect_rgb(24'h38d878, "sample-derived progress fill");

    $display("PASS Phosphor album UI: visibility, selection, text, and progress");
    $finish;
end

endmodule
