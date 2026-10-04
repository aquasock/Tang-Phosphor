// Testbench for the TinyTang keyboard link receiver.
//
// Drives the receiver's input line exactly as the keyboard's UART would, at a
// small clock/baud ratio so the simulation stays fast, and checks that valid
// frames are latched, and that every malformed frame is rejected and counted
// rather than half-applied.
`timescale 1ns/1ps

module keylink_rx_tb;

    // 10 clocks per bit: the same integer relationship the real design has
    // (99 at 74.25 MHz / 750 kbaud), just smaller.
    localparam integer CLK_HZ = 750_000;
    localparam integer BAUD   = 75_000;
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;

    logic clk = 1'b0;
    always #1 clk = ~clk;

    logic resetn = 1'b0;
    logic rx = 1'b1;                       // line idles high

    logic [7:0]  o_modifiers;
    logic [7:0]  o_keys [6];
    logic        o_valid;
    logic [31:0] o_frames, o_bad_checksum, o_bad_length, o_truncated;

    keylink_rx #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (BAUD)
    ) dut (
        .clk (clk), .resetn (resetn), .rx (rx),
        .o_modifiers (o_modifiers), .o_keys (o_keys), .o_valid (o_valid),
        .o_frames (o_frames), .o_bad_checksum (o_bad_checksum),
        .o_bad_length (o_bad_length), .o_truncated (o_truncated)
    );

    int errors = 0;

    // o_valid is a one-cycle pulse, so latch it and check the latch after the
    // frame rather than probing the pulse at some arbitrary later cycle.
    logic valid_seen = 1'b0;
    always_ff @(posedge clk) if (o_valid) valid_seen <= 1'b1;
    task automatic clear_valid(); valid_seen = 1'b0; endtask

    // ------------------------------------------------------------ line model
    task automatic send_byte(input [7:0] b);
        rx = 1'b0;                                  // start
        repeat (CLKS_PER_BIT) @(posedge clk);
        for (int i = 0; i < 8; i++) begin           // 8 data bits, LSB first
            rx = b[i];
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
        rx = 1'b1;                                  // stop
        repeat (CLKS_PER_BIT) @(posedge clk);
    endtask

    // Build a frame from a payload and send it.  corrupt flips the checksum.
    task automatic send_frame(input [7:0] payload [8], input bit corrupt,
                              input bit bad_len);
        logic [7:0] s;
        s = 8'hA5 + (bad_len ? 8'd7 : 8'd8) + payload[0] + payload[1]
          + payload[2] + payload[3] + payload[4] + payload[5]
          + payload[6] + payload[7];
        send_byte(8'hA5);
        send_byte(bad_len ? 8'd7 : 8'd8);
        for (int i = 0; i < 8; i++) send_byte(payload[i]);
        send_byte(corrupt ? s + 8'd1 : s);
    endtask

    task automatic idle(input int bytes);
        rx = 1'b1;
        repeat (bytes * CLKS_PER_BIT * 12) @(posedge clk);
    endtask

    task automatic check(input string what, input bit cond);
        if (!cond) begin
            errors++;
            $display("FAIL: %s", what);
        end
    endtask

    // ------------------------------------------------------------------ test
    logic [7:0] p [8];

    initial begin
        repeat (10) @(posedge clk);
        resetn = 1'b1;
        repeat (10) @(posedge clk);

        // --- 1. a valid frame: LeftShift + 'A' ---------------------------
        p = '{8'h02, 8'h00, 8'h04, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
        clear_valid();
        send_frame(p, 1'b0, 1'b0);
        repeat (6) @(posedge clk);
        check("valid frame raised o_valid", valid_seen === 1'b1);
        check("modifiers latched", o_modifiers === 8'h02);
        check("keycode latched", o_keys[0] === 8'h04);
        check("frame counted", o_frames === 32'd1);
        check("no error counters moved",
              o_bad_checksum === 0 && o_bad_length === 0 && o_truncated === 0);
        idle(4);

        // --- 2. a second frame: all keys released ------------------------
        p = '{8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
        clear_valid();
        send_frame(p, 1'b0, 1'b0);
        repeat (6) @(posedge clk);
        check("release frame raised o_valid", valid_seen === 1'b1);
        check("release latched", o_modifiers === 8'h00 && o_keys[0] === 8'h00);
        check("frames is 2", o_frames === 32'd2);
        idle(4);

        // --- 3. a frame with a bad checksum is dropped -------------------
        p = '{8'h02, 8'h00, 8'h04, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
        clear_valid();
        send_frame(p, 1'b1, 1'b0);
        repeat (6) @(posedge clk);
        check("bad checksum did not latch", o_modifiers === 8'h00);
        check("bad checksum raised no o_valid", valid_seen === 1'b0);
        check("bad checksum counted", o_bad_checksum === 32'd1);
        check("frames still 2", o_frames === 32'd2);
        idle(4);

        // --- 4. a frame with the wrong length is refused -----------------
        p = '{8'h02, 8'h00, 8'h04, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
        send_frame(p, 1'b0, 1'b1);
        repeat (6) @(posedge clk);
        check("bad length counted", o_bad_length === 32'd1);
        check("bad length did not latch", o_modifiers === 8'h00);
        idle(4);

        // --- 5. a frame that stops half way is abandoned and counted -----
        send_byte(8'hA5);
        send_byte(8'd8);
        send_byte(8'h02);
        idle(6);
        check("truncated frame counted", o_truncated >= 32'd1);

        // --- 6. ... and the link still works afterwards ------------------
        p = '{8'h01, 8'h00, 8'h05, 8'h06, 8'h00, 8'h00, 8'h00, 8'h00};
        clear_valid();
        send_frame(p, 1'b0, 1'b0);
        repeat (6) @(posedge clk);
        check("recovered after truncation", valid_seen === 1'b1 && o_modifiers === 8'h01);
        check("two keys latched", o_keys[0] === 8'h05 && o_keys[1] === 8'h06);
        check("frames is 3", o_frames === 32'd3);
        check("no checksum errors", o_bad_checksum === 32'd1);

        if (errors == 0)
            $display("PASS keylink: frames latched, malformed frames rejected and counted, link recovers");
        else
            $display("FAIL keylink: %0d check(s) failed", errors);
        $finish;
    end

endmodule
