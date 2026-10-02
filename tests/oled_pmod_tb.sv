// SPDX-License-Identifier: GPL-3.0-only
//
// Self-checking test for the Pmod OLEDrgb bring-up core.
//
// Models the SSD1331 side of the link: it samples MOSI on SCK's rising edge
// (SPI mode 3) and records every byte with the DC level that framed it.  It
// then checks the documented power-on ordering, the whole 44-byte
// initialisation sequence, the display-on command, the per-frame address
// window, and the first pixels of the first pattern.
`timescale 1ns/1ps

module oled_pmod_tb;
    localparam int INIT_LEN = 44;

    logic clk = 1'b0;
    always #10 clk = ~clk;              // 50 MHz

    logic cs_n, mosi, sck, dc, res_n, vccen, pmoden;

    oled_pmod_top dut (
        .sys_clk(clk),
        .oled_cs_n(cs_n), .oled_mosi(mosi), .oled_sck(sck), .oled_dc(dc),
        .oled_res_n(res_n), .oled_vccen(vccen), .oled_pmoden(pmoden)
    );

    int failures = 0;
    int cycles = 0;

    // ------------------------------------------------------------------
    // SSD1331 slave model: sample MOSI on the rising edge of SCK.
    // ------------------------------------------------------------------
    localparam int MAX_BYTES = 512;
    logic [7:0] got [0:MAX_BYTES-1];
    logic       got_dc [0:MAX_BYTES-1];
    int         nbytes = 0;
    logic [7:0] sh = 8'h00;
    int         nbits = 0;

    always @(posedge clk) cycles = cycles + 1;

    always @(posedge sck) begin
        if (!cs_n) begin
            sh    = {sh[6:0], mosi};   // MSB arrives first
            nbits = nbits + 1;
            if (nbits == 8 && nbytes < MAX_BYTES) begin
                nbits          = 0;
                got[nbytes]    = sh;   // after 8 shifts sh is exactly the byte
                got_dc[nbytes] = dc;
                nbytes         = nbytes + 1;
            end
        end
    end

    // Mode 3 requires the slave's input to be stable at the sampling edge.
    logic mosi_d1 = 1'b0, mosi_d2 = 1'b0;
    always @(posedge clk) begin
        mosi_d1 = mosi;
        mosi_d2 = mosi_d1;
    end
    always @(posedge sck) begin
        if (!cs_n && mosi !== mosi_d2) begin
            $display("FAIL: MOSI not stable at SCK rising edge (sample=%b, t-2=%b)",
                     mosi, mosi_d2);
            failures = failures + 1;
        end
    end

    // ------------------------------------------------------------------
    // Power-ordering observations.
    // ------------------------------------------------------------------
    int pmoden_cycle = -1, res_low_cycle = -1, vccen_high_cycle = -1;
    always @(posedge clk) begin
        if (pmoden === 1'b1 && pmoden_cycle < 0)      pmoden_cycle = cycles;
        if (res_n   === 1'b0 && res_low_cycle < 0)    res_low_cycle = cycles;
        if (vccen   === 1'b1 && vccen_high_cycle < 0) vccen_high_cycle = cycles;
    end

    // ------------------------------------------------------------------
    // Expectations, run after the sequence has had time to complete.
    // ------------------------------------------------------------------
    logic [7:0] init_exp [0:INIT_LEN-1];
    logic [7:0] frame_exp [0:5];
    int i, k;
    logic [7:0] want;

    initial begin
        init_exp[0]=8'hFD; init_exp[1]=8'h12; init_exp[2]=8'hAE; init_exp[3]=8'hA0;
        init_exp[4]=8'h72; init_exp[5]=8'hA1; init_exp[6]=8'h00; init_exp[7]=8'hA2;
        init_exp[8]=8'h00; init_exp[9]=8'hA4; init_exp[10]=8'hA8; init_exp[11]=8'h3F;
        init_exp[12]=8'hAD; init_exp[13]=8'h8E; init_exp[14]=8'hB0; init_exp[15]=8'h0B;
        init_exp[16]=8'hB1; init_exp[17]=8'h31; init_exp[18]=8'hB3; init_exp[19]=8'hF0;
        init_exp[20]=8'h8A; init_exp[21]=8'h64; init_exp[22]=8'h8B; init_exp[23]=8'h78;
        init_exp[24]=8'h8C; init_exp[25]=8'h64; init_exp[26]=8'hBB; init_exp[27]=8'h3A;
        init_exp[28]=8'hBE; init_exp[29]=8'h3E; init_exp[30]=8'h87; init_exp[31]=8'h06;
        init_exp[32]=8'h81; init_exp[33]=8'h91; init_exp[34]=8'h82; init_exp[35]=8'h50;
        init_exp[36]=8'h83; init_exp[37]=8'h7D; init_exp[38]=8'h2E; init_exp[39]=8'h25;
        init_exp[40]=8'h00; init_exp[41]=8'h00; init_exp[42]=8'h5F; init_exp[43]=8'h3F;
        frame_exp[0]=8'h15; frame_exp[1]=8'h00; frame_exp[2]=8'h5F;
        frame_exp[3]=8'h75; frame_exp[4]=8'h00; frame_exp[5]=8'h3F;

        // 20 ms power, 10 us reset, 25 ms VCCEN, 100 ms settle, then frames.
        #160ms;

        if (pmoden !== 1'b1) begin $display("FAIL: PMODEN low after power-up"); failures++; end
        if (vccen  !== 1'b1) begin $display("FAIL: VCCEN not high once display is on"); failures++; end
        if (res_n  !== 1'b1) begin $display("FAIL: RES not released high"); failures++; end
        if (cs_n   !== 1'b0) begin $display("FAIL: CS not held low"); failures++; end
        if (!(pmoden_cycle >= 0 && res_low_cycle > pmoden_cycle)) begin
            $display("FAIL: PMODEN must rise before RES is pulsed low"); failures++;
        end
        if (!(vccen_high_cycle > res_low_cycle)) begin
            $display("FAIL: VCCEN must come up after the reset"); failures++;
        end
        if (nbytes < INIT_LEN + 1 + 6 + 4) begin
            $display("FAIL: only %0d bytes seen, expected at least %0d",
                     nbytes, INIT_LEN + 1 + 6 + 4);
            failures++;
        end

        // The initialisation list, all commands (DC low).
        for (i = 0; i < INIT_LEN && i < nbytes; i = i + 1) begin
            if (got_dc[i] !== 1'b0 || got[i] !== init_exp[i]) begin
                $display("FAIL: init byte %0d = 0x%02x (dc=%b), expected 0x%02x",
                         i, got[i], got_dc[i], init_exp[i]);
                failures++;
            end
        end

        // Display on after the list.
        if (got[INIT_LEN] !== 8'hAF || got_dc[INIT_LEN] !== 1'b0) begin
            $display("FAIL: byte %0d = 0x%02x, expected display-on 0xAF",
                     INIT_LEN, got[INIT_LEN]);
            failures++;
        end

        // Address window of the first frame.
        for (i = 0; i < 6; i = i + 1) begin
            k = INIT_LEN + 1 + i;
            if (got_dc[k] !== 1'b0 || got[k] !== frame_exp[i]) begin
                $display("FAIL: frame byte %0d = 0x%02x (dc=%b), expected 0x%02x",
                         i, got[k], got_dc[k], frame_exp[i]);
                failures++;
            end
        end

        // First pixels of pattern 0: solid red 0xF800, DC high.
        for (i = 0; i < 4; i = i + 1) begin
            k = INIT_LEN + 1 + 6 + i;
            want = (i % 2 == 0) ? 8'hF8 : 8'h00;
            if (got_dc[k] !== 1'b1 || got[k] !== want) begin
                $display("FAIL: pixel byte %0d = 0x%02x (dc=%b), expected 0x%02x",
                         i, got[k], got_dc[k], want);
                failures++;
            end
        end

        if (failures == 0)
            $display("PASS oled_pmod: power sequence, init list, mode-3 timing and first pixels");
        else
            $fatal(1, "oled_pmod_tb: %0d failures", failures);
        $finish;
    end

    initial begin
        #400ms;
        $fatal(1, "oled_pmod_tb timeout");
    end
endmodule
