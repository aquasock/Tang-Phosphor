`timescale 1ns/1ps
// Decode at the DAC's rising SCLK edge, independently of the TX shift logic.
module i2s_tx_tb;
    logic clk = 0;
    always #40.690104 clk = ~clk;
    logic resetn = 0;
    logic ref_clk = 0;
    always #6.734007 ref_clk = ~ref_clk;
    wire [31:0] clock_count;
    wire [2:0] clock_status;
    i2s_clock_probe #(.WINDOW_CYCLES(74_250)) probe (
        .clk_ref(ref_clk), .clk_mclk(clk), .resetn(resetn),
        .pll_locked(2'b11), .count(clock_count), .status(clock_status)
    );
    logic [15:0] left_in = 16'h8000, right_in = 16'h7fff;
    wire sclk, lrck, sd, tick;
    i2s_tx dut (.clk_mclk(clk), .resetn(resetn),
        .sample_left(left_in), .sample_right(right_in),
        .sclk(sclk), .lrck(lrck), .sdata(sd), .sample_tick(tick));

    logic [15:0] expected_left = 0, expected_right = 0;
    integer captures = 0, mclks = 0, last_capture = 0;
    always @(posedge clk) begin
        if (!resetn) begin
            expected_left = 0;
            expected_right = 0;
            mclks = 0;
            last_capture = 0;
        end else begin
            mclks++;
            if (tick) begin
                if (last_capture != 0 && mclks - last_capture != 256)
                    $fatal(1, "frame is not 256 MCLK cycles");
                last_capture = mclks;
                captures++;
                expected_left = left_in;
                expected_right = right_in;
            end
        end
    end

    integer slot = -1, bits_checked = 0;
    logic last_lrck = 0;
    logic [31:0] expected_word;
    time last_rising_sclk = 0;
    always @(posedge sclk) begin
        if (resetn) begin
            if (last_rising_sclk != 0 &&
                ($time - last_rising_sclk < 324 || $time - last_rising_sclk > 327))
                $fatal(1, "SCLK is not MCLK / 4");
            last_rising_sclk = $time;
            if (lrck != last_lrck) begin
                if (slot != 31) $fatal(1, "channel has %0d slots", slot + 1);
                slot = 0;
            end else slot++;
            if (slot > 31) $fatal(1, "LRCK did not change after 32 bits");
            last_lrck = lrck;
            // One delay bit, sixteen significant bits, then fifteen zeros.
            expected_word = {1'b0, lrck ? expected_right : expected_left, 15'b0};
            if (sd !== expected_word[31-slot])
                $fatal(1, "LRCK=%b slot=%0d data=%b expected=%b",
                       lrck, slot, sd, expected_word[31-slot]);
            bits_checked++;
        end
    end

    // Changes to SD or LRCK are permitted only at falling SCLK edges.
    logic old_sclk = 0, old_lrck = 0, old_sd = 0;
    always @(posedge clk) begin
        #1;
        if (resetn && (sd != old_sd || lrck != old_lrck) &&
            !(old_sclk && !sclk))
            $fatal(1, "data or word-select changed off the falling edge");
        old_sclk = sclk;
        old_lrck = lrck;
        old_sd = sd;
    end

    // A complete output-only personality, through the real socket mapping.
    logic enable = 0;
    wire [7:0] lane_o, lane_oe, lane_i, io_o, io_oe, io_i;
    tri [7:0] pins;
    pmod_i2s2_tone tone (.clk_mclk(clk), .enable(enable),
        .lane_o(lane_o), .lane_oe(lane_oe));
    pmod_slot socket (.flipped(1'b0), .lane_o(lane_o), .lane_oe(lane_oe),
        .lane_i(lane_i), .io_o(io_o), .io_oe(io_oe), .io_i(io_i));
    pmod_io_buf buf_i (.o(io_o), .oe(io_oe), .i(io_i), .io(pins));

    task automatic check_tones(input integer count);
        logic [31:0] lword, rword;
        logic [15:0] lexpected, rexpected;
        for (integer f = 0; f < count; f++) begin
            @(negedge pins[2]); // LRCK: the beginning of a left frame
            lword = 0;
            rword = 0;
            for (integer b = 0; b < 32; b++) begin
                @(posedge pins[4]); // SCLK
                if (pins[2] !== 0) $fatal(1, "left polarity or slot mapping");
                lword = {lword[30:0], pins[6]};
            end
            for (integer b = 0; b < 32; b++) begin
                @(posedge pins[4]);
                if (pins[2] !== 1) $fatal(1, "right polarity or slot mapping");
                rword = {rword[30:0], pins[6]};
            end
            lexpected = f % 48 < 24 ? 16'h2000 : 16'he000;
            rexpected = f % 24 < 12 ? 16'h2000 : 16'he000;
            if (lword !== {1'b0, lexpected, 15'b0} ||
                rword !== {1'b0, rexpected, 15'b0})
                $fatal(1, "tone frame %0d: L=%h R=%h", f, lword, rword);
            if (lane_oe != 8'h0f || io_oe != 8'h55)
                $fatal(1, "ADC row is being driven");
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        resetn = 1;
        // Change both inputs within frames: a mixed left/right pair fails.
        fork
            begin
                repeat (27000) begin
                    @(negedge clk);
                    left_in = 16'($random);
                    right_in = 16'($random);
                end
            end
            begin
                enable = 1;
                check_tones(96);
                // Withdraw mid-frame, then ensure a clean restart.
                repeat (37) @(negedge clk);
                enable = 0;
                #1;
                if (lane_oe != 0 || io_oe != 0)
                    $fatal(1, "withdrawn socket still driven");
                repeat (5) @(negedge clk);
                enable = 1;
                check_tones(4);
            end
        join
        @(negedge clk);
        resetn = 0;
        #1;
        if (sclk || lrck || sd || tick) $fatal(1, "reset did not stop TX");
        slot = -1;
        last_lrck = 0;
        last_rising_sclk = 0;
        repeat (3) @(negedge clk);
        resetn = 1;
        repeat (600) @(negedge clk);
        wait (clock_status[2]);
        #1;
        if (clock_status != 3'd7 || clock_count < 12284 || clock_count > 12292)
            $fatal(1, "clock probe: status=%h, count=%0d", clock_status, clock_count);
        if (captures < 100 || bits_checked < 6400)
            $fatal(1, "insufficient frame coverage");
        $display("PASS i2s_tx: coherent PCM pairs, delay bit, 24-bit padding, clock ratios, clock measurement, socket release and 1/2 kHz tones");
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "timeout");
    end
endmodule
