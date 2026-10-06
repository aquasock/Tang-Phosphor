`timescale 1ns/1ps

// The player bank's two control words must not alias.  Until register ABI 1.8
// cpu_mode was bit 0 of the socket control word at 0xc0, so selecting the CPU
// for a track released both PMOD sockets, and declaring a socket sent the
// stream raw into the FPGA player.  This checks each word only moves its own
// fields, and that both read back.
module debug_regs_tb;
logic clk = 0;
logic resetn = 0;
logic request_valid = 0;
logic request_write = 0;
logic [31:0] request_address = 0;
logic [31:0] request_wdata = 0;
logic [3:0] pmod0_personality;
logic [3:0] pmod1_personality;
logic pmod0_flipped;
logic pmod1_flipped;
logic render_hold;
logic cpu_mode;
logic [31:0] request_rdata;
int failures = 0;

always #5 clk = ~clk;

debug_regs dut (
    .clk(clk), .resetn(resetn), .frame_tick(1'b0),
    .request_valid(request_valid), .request_write(request_write),
    .request_address(request_address), .request_wdata(request_wdata),
    .transport_crc_errors(32'd0), .transport_bad_requests(32'd0),
    .stream_sessions(32'd0), .stream_bytes(32'd0), .stream_ends(32'd0),
    .stream_cancels(32'd0), .stream_last_offset(32'd0), .stream_crc32(32'd0),
    .controller1(12'd0), .controller2(12'd0), .hid1(16'd0), .hid2(16'd0),
    .controller_status(6'd0), .player_state(4'd0),
    .audio_format_valid(1'b0), .playback_active(1'b0),
    .audio_sample_rate(32'd0), .pcm_fifo_level(15'd0),
    .samples_played(32'd0), .audio_underruns(32'd0), .audio_error(8'd0),
    .hdmi_audio_rate(32'd0), .detected_format(3'd0),
    .pause_requested(1'b0), .ui_visible(1'b0), .ui_playlist(1'b0),
    .ui_current_track(8'd0), .ui_track_count(8'd0), .ui_window_start(8'd0),
    .elapsed_seconds(32'd0), .duration_seconds(32'd0),
    .boundary_count(32'd0), .boundary_gap_samples(32'd0),
    .audible_stream_id(16'd0),
    .src_signature(32'd0), .hdmi_signature(32'd0), .oled_signature(32'd0),
    .render_frames(32'd0), .oled_frames(32'd0), .hdmi_frames(32'd0),
    .source_bank(1'b0), .render_pattern(3'd0), .enc_count(32'd0),
    .enc_raw(4'd0), .enc_button(1'b0), .enc_switch(1'b0),
    .link_frames(32'd0), .link_bad_checksum(32'd0), .link_truncated(32'd0),
    .link_mods(8'd0), .link_key0(8'd0), .link_key1(8'd0),
    .pmod0_personality(pmod0_personality),
    .pmod1_personality(pmod1_personality),
    .pmod0_flipped(pmod0_flipped), .pmod1_flipped(pmod1_flipped),
    .render_hold(render_hold), .cpu_mode(cpu_mode),
    .request_rdata(request_rdata)
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
    @(negedge clk);
end
endtask

// The read path is four registers deep; the transport waits far longer.
task automatic read_reg(input logic [31:0] address, output logic [31:0] data);
begin
    @(negedge clk);
    request_address = address;
    repeat (6) @(negedge clk);
    data = request_rdata;
end
endtask

task automatic expect_state(input string label, input logic [3:0] p0,
                            input logic [3:0] p1, input logic f0, input logic f1,
                            input logic hold, input logic cpu);
begin
    if (pmod0_personality !== p0 || pmod1_personality !== p1 ||
        pmod0_flipped !== f0 || pmod1_flipped !== f1 ||
        render_hold !== hold || cpu_mode !== cpu) begin
        $display("FAIL %s: pmod0=%0d pmod1=%0d flip=%b%b hold=%b cpu=%b, expected pmod0=%0d pmod1=%0d flip=%b%b hold=%b cpu=%b",
                 label, pmod0_personality, pmod1_personality, pmod1_flipped,
                 pmod0_flipped, render_hold, cpu_mode, p0, p1, f1, f0, hold, cpu);
        failures++;
    end
end
endtask

task automatic expect_read(input string label, input logic [31:0] address,
                           input logic [31:0] expected);
    logic [31:0] value;
begin
    read_reg(address, value);
    if (value !== expected) begin
        $display("FAIL %s: read 0x%08x from 0x%02x, expected 0x%08x",
                 label, value, address, expected);
        failures++;
    end
end
endtask

initial begin
    repeat (3) @(negedge clk);
    resetn = 1;
    @(negedge clk);

    expect_state("power-on", 4'd0, 4'd0, 1'b0, 1'b0, 1'b0, 1'b0);
    expect_read("register ABI", 32'h04, 32'h0001_0008);
    expect_read("cpu_mode at power-on", 32'ha8, 32'd0);

    // The standard OLED and encoder declaration, as entry 64 wrote it.
    write_reg(32'hc0, 32'h0000_2410);
    expect_state("declare sockets", 4'd1, 4'd4, 1'b0, 1'b1, 1'b0, 1'b0);

    // Selecting the CPU for a track must leave the declaration standing.
    write_reg(32'ha8, 32'd1);
    expect_state("select CPU", 4'd1, 4'd4, 1'b0, 1'b1, 1'b0, 1'b1);
    expect_read("cpu_mode set", 32'ha8, 32'd1);
    expect_read("control after CPU select", 32'hc0, 32'h0000_2410);

    // Redeclaring, holding included, must leave the CPU selected.
    write_reg(32'hc0, 32'h0000_2411);
    expect_state("redeclare with hold", 4'd1, 4'd4, 1'b0, 1'b1, 1'b1, 1'b1);
    write_reg(32'hc0, 32'h0000_0000);
    expect_state("release sockets", 4'd0, 4'd0, 1'b0, 1'b0, 1'b0, 1'b1);
    expect_read("cpu_mode after release", 32'ha8, 32'd1);

    // Only bit 0 of 0xa8 is meaningful, and clearing it touches nothing else.
    write_reg(32'hc0, 32'h0000_1230);
    write_reg(32'ha8, 32'hffff_fffe);
    expect_state("clear CPU", 4'd3, 4'd2, 1'b1, 1'b0, 1'b0, 1'b0);
    expect_read("cpu_mode cleared", 32'ha8, 32'd0);

    // Reset returns both words to their safe state.
    write_reg(32'ha8, 32'd1);
    resetn = 0;
    repeat (2) @(negedge clk);
    resetn = 1;
    @(negedge clk);
    expect_state("after reset", 4'd0, 4'd0, 1'b0, 1'b0, 1'b0, 1'b0);

    if (failures != 0) begin
        $display("debug_regs_tb: %0d failures", failures);
        $fatal(1);
    end
    $display("debug_regs_tb: PASS (cpu_mode and socket control are independent and read back)");
    $finish;
end
endmodule
