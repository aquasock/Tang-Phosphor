// SPDX-License-Identifier: GPL-3.0-only
//
// Self-checking test for the socket layer, the scan mapper, the frame store
// and the bank swap, plus an end-to-end check that the panel path runs through
// the new structure.
//
// Each piece is checked against an expectation written independently of the
// RTL: the mapper against ((x - X0) / K, (y - Y0) / K) computed here, the
// socket layer against the pin numbering recorded in core-reference.md, and
// the panel model against the SSD1331 sequence it already proved on hardware.
//
// The top-level check decodes the SPI pins out of PMOD0's raw socket pins, so
// a wrong interleave or a wrongly applied orientation fails here rather than
// on a bench.
//
// Stimulus changes at the falling edge and is sampled after the rising edge.
// Driving a clocked always_ff from an initial block at the same time as the
// edge races it and silently drops writes, which is how the first version of
// this test failed: a lost write and a lost swap pulse, not RTL bugs.
//
// The panel's first frame is expected to be blank.  The renderer fills the
// bank nobody is reading and the swap only lands at a frame boundary, so the
// content appears on the second frame; the pixel check therefore looks at the
// second frame's first pixel, which also proves the swap end to end.
`timescale 1ns/1ps

module ui_mirror_tb;
    localparam int INIT_LEN = 44;
    localparam int W = 96;
    localparam int H = 64;

    logic clk = 1'b0;
    always #10 clk = ~clk;              // 50 MHz

    int failures = 0;

    task automatic note_fail(input string what);
        failures = failures + 1;
        $display("FAIL %s", what);
    endtask

    // The frame the host model predicts, computed here independently of the
    // renderer so a drift between them fails in simulation rather than on a
    // bench: tools/ui_mirror_check.py judges hardware with this same function.
    function automatic logic [15:0] exp_cell_pixel(input int px, input int py);
        int col, in_col, row, in_row;
        begin
            col    = px / 6;
            in_col = px % 6;
            row    = py / 8;
            in_row = py % 8;
            exp_cell_pixel = {1'b0, row[2:0], 1'b0, col[3:0], in_col[2:0], in_row[2:0], 1'b0};
        end
    endfunction

    // signature <- signature * 5 + pixel (mod 2^32), matching ui_checksum.sv.
    function automatic logic [31:0] exp_frame_fold;
        logic [31:0] acc;
        begin
            acc = 32'd0;
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                    acc = acc * 32'd5 + {16'b0, exp_cell_pixel(x, y)};
            exp_frame_fold = acc;
        end
    endfunction

    task automatic expect_eq(input string what, input int got, input int want);
        if (got !== want) begin
            failures = failures + 1;
            $display("FAIL %s: got %0d want %0d", what, got, want);
        end
    endtask

    logic rst = 1'b1;

    // ==================================================================
    // 1. Socket layer: interleave and orientation.
    // ==================================================================
    logic       flip;
    logic [7:0] lane_o, lane_oe, lane_i;
    logic [7:0] io_o, io_oe, io_i;

    pmod_slot slot (
        .flipped (flip),
        .lane_o  (lane_o),
        .lane_oe (lane_oe),
        .lane_i  (lane_i),
        .io_o    (io_o),
        .io_oe   (io_oe),
        .io_i    (io_i)
    );

    task automatic check_socket;
        // Drive direction: Digilent lane k must reach Sipeed IO 2k for k<4 and
        // 2(k-4)+1 for k>=4.
        flip = 1'b0;
        for (int k = 0; k < 8; k++) begin
            int unsigned phys;
            phys = (k < 4) ? (2 * k) : (2 * (k - 4) + 1);
            lane_o    = 8'h00;
            lane_o[k] = 1'b1;
            lane_oe   = 8'hff;
            #1;
            for (int b = 0; b < 8; b++)
                expect_eq($sformatf("normal lane %0d -> io %0d", k, b),
                          (io_o[b] === 1'b1) ? 1 : 0, (b == phys) ? 1 : 0);
            expect_eq($sformatf("normal lane %0d enable", k),
                      (io_oe === 8'hff) ? 1 : 0, 1);
        end

        // Flipped swaps the module's two rows: lane 0 must reach io 1.
        flip    = 1'b1;
        lane_o  = 8'h01;                // lane 0 only
        lane_oe = 8'hff;
        #1;
        expect_eq("flipped lane 0 drives io 1", (io_o[1] === 1'b1) ? 1 : 0, 1);
        expect_eq("flipped lane 0 leaves io 0", (io_o[0] === 1'b1) ? 1 : 0, 0);

        lane_o = 8'h10;                 // lane 4 only
        #1;
        expect_eq("flipped lane 4 drives io 0", (io_o[0] === 1'b1) ? 1 : 0, 1);
        expect_eq("flipped lane 4 leaves io 1", (io_o[1] === 1'b1) ? 1 : 0, 0);

        // Read direction: io 1 is lane 4 normally and lane 0 flipped.
        flip = 1'b0;
        io_i = 8'h02;
        #1;
        expect_eq("normal io 1 reads as lane 4", (lane_i[4] === 1'b1) ? 1 : 0, 1);
        expect_eq("normal io 1 not lane 0",      (lane_i[0] === 1'b1) ? 1 : 0, 0);

        flip = 1'b1;
        #1;
        expect_eq("flipped io 1 reads as lane 0", (lane_i[0] === 1'b1) ? 1 : 0, 1);
        expect_eq("flipped io 1 not lane 4",      (lane_i[4] === 1'b1) ? 1 : 0, 0);

        flip = 1'b0;
        io_i = 8'h01;                   // io 0
        #1;
        expect_eq("normal io 0 reads as lane 0", (lane_i[0] === 1'b1) ? 1 : 0, 1);
        flip = 1'b1;
        #1;
        expect_eq("flipped io 0 reads as lane 4", (lane_i[4] === 1'b1) ? 1 : 0, 1);
        flip = 1'b0;
        io_i = 8'h00;
        #1;
    endtask

    // ==================================================================
    // 2. Scan mapper: three integer factors against a written-out model.
    // ==================================================================
    logic [11:0] ox1, oy1, ox8, oy8, ox11, oy11;
    logic        in1, in8, in11;
    logic [6:0]  sx1, sx8, sx11;
    logic [5:0]  sy1, sy8, sy11;

    ui_scanout #(.K(1), .W(W), .H(H), .X0(0), .Y0(0))
    sc1 (.clk(clk), .rst(rst), .out_x(ox1), .out_y(oy1),
         .in_image(in1), .src_x(sx1), .src_y(sy1));

    ui_scanout #(.K(8), .W(W), .H(H), .X0(16), .Y0(44))
    sc8 (.clk(clk), .rst(rst), .out_x(ox8), .out_y(oy8),
         .in_image(in8), .src_x(sx8), .src_y(sy8));

    ui_scanout #(.K(11), .W(W), .H(H), .X0(112), .Y0(8))
    sc11 (.clk(clk), .rst(rst), .out_x(ox11), .out_y(oy11),
          .in_image(in11), .src_x(sx11), .src_y(sy11));

    // Free-running rasters, one pixel per clock, wrapping like a real timing
    // generator: x to 0 on the last pixel of a line, y to 0 on the last line.
    always_ff @(posedge clk) begin
        if (rst) begin
            ox1 <= 12'd0;  oy1 <= 12'd0;
            ox8 <= 12'd0;  oy8 <= 12'd0;
            ox11 <= 12'd0; oy11 <= 12'd0;
        end else begin
            ox1  <= (ox1 == 12'd95) ? 12'd0 : ox1 + 12'd1;
            oy1  <= (ox1 == 12'd95) ? ((oy1 == 12'd63) ? 12'd0 : oy1 + 12'd1) : oy1;
            ox8  <= (ox8 == 12'd799) ? 12'd0 : ox8 + 12'd1;
            oy8  <= (ox8 == 12'd799) ? ((oy8 == 12'd599) ? 12'd0 : oy8 + 12'd1) : oy8;
            ox11 <= (ox11 == 12'd1279) ? 12'd0 : ox11 + 12'd1;
            oy11 <= (ox11 == 12'd1279) ? ((oy11 == 12'd719) ? 12'd0 : oy11 + 12'd1) : oy11;
        end
    end

    int scanned = 0;
    int n_inside = 0;

    // The mapper's registers describe the coordinate presented one output
    // pixel earlier, so the source expectation is written for that coordinate
    // while in_image is checked against the coordinate presented now.  A dense
    // raster is the strictest case: every coordinate lasts one pixel.
    task automatic check_mapper(
        input string       name,
        input int          K, input int x0, input int y0,
        input logic [11:0] px, py,          // the coordinate the mapping describes
        input logic [11:0] cx, cy,          // the coordinate presented now
        input logic        inv,
        input logic [6:0]  sxv, input logic [5:0] syv
    );
        int want_in;
        int prev_in;
        want_in = (cx >= x0) && (cx <= x0 + K * W - 1) &&
                  (cy >= y0) && (cy <= y0 + K * H - 1);
        prev_in = (px >= x0) && (px <= x0 + K * W - 1) &&
                  (py >= y0) && (py <= y0 + K * H - 1);

        if ((inv ? 1 : 0) !== want_in) begin
            failures = failures + 1;
            $display("FAIL %s in_image at (%0d,%0d): got %0d want %0d",
                     name, cx, cy, inv, want_in);
        end

        scanned = scanned + 1;
        if (prev_in) begin
            n_inside = n_inside + 1;
            if (sxv !== 7'((px - x0) / K) || syv !== 6'((py - y0) / K)) begin
                failures = failures + 1;
                $display("FAIL %s src for (%0d,%0d): got (%0d,%0d) want (%0d,%0d)",
                         name, px, py, sxv, syv, (px - x0) / K, (py - y0) / K);
            end
        end
    endtask

    // ==================================================================
    // 3. Frame store and bank swap.
    // ==================================================================
    logic        fs_we;
    logic        fs_wb, fs_rb;
    logic [6:0]  fs_wx, fs_rx;
    logic [5:0]  fs_wy, fs_ry;
    logic [15:0] fs_wpx, fs_rpx;

    ui_frame_store #(.W(W), .H(H)) store (
        .clk(clk), .we(fs_we), .wr_bank(fs_wb), .wr_x(fs_wx), .wr_y(fs_wy), .wr_px(fs_wpx),
        .rd_bank(fs_rb), .rd_x(fs_rx), .rd_y(fs_ry), .rd_px(fs_rpx)
    );

    logic sw_done, sw_tick, sw_bank, sw_enable;
    ui_swap #(.OUTPUTS(1)) swap (
        .clk(clk), .rst(rst), .render_done(sw_done), .frame_tick(sw_tick),
        .bank(sw_bank), .render_enable(sw_enable)
    );

    task automatic frame_store_check;
        // The same coordinate in both banks must be independent, and the row
        // multiply must be right: (95,63) is the last pixel of a bank.
        @(negedge clk);
        fs_we = 1'b1; fs_wb = 1'b0; fs_wx = 7'd5;  fs_wy = 6'd7;  fs_wpx = 16'h1234;
        @(posedge clk);

        @(negedge clk);
        fs_wb = 1'b1; fs_wpx = 16'hABCD;
        @(posedge clk);

        @(negedge clk);
        fs_wb = 1'b0; fs_wx = 7'd95; fs_wy = 6'd63; fs_wpx = 16'hBEEF;
        @(posedge clk);

        @(negedge clk);
        fs_we = 1'b0;

        fs_rb = 1'b0; fs_rx = 7'd5;  fs_ry = 6'd7;
        @(posedge clk); #1;
        expect_eq("bank 0 pixel", fs_rpx, 16'h1234);

        fs_rb = 1'b1;
        @(posedge clk); #1;
        expect_eq("bank 1 pixel", fs_rpx, 16'hABCD);

        fs_rb = 1'b0; fs_rx = 7'd95; fs_ry = 6'd63;
        @(posedge clk); #1;
        expect_eq("bank 0 last pixel", fs_rpx, 16'hBEEF);

        // The second bank must not have inherited that last-pixel write.
        fs_rb = 1'b1;
        @(posedge clk); #1;
        expect_eq("bank 1 last pixel untouched", fs_rpx, 16'h0000);

        fs_rb = 1'b0; fs_rx = 7'd0; fs_ry = 6'd0;
    endtask

    task automatic swap_check;
        expect_eq("swap idle enables renderer", sw_enable, 1'b1);
        expect_eq("swap starts on bank 0", sw_bank, 1'b0);

        // Renderer finishes: held off until the output crosses a frame.
        @(negedge clk);
        sw_done = 1'b1;
        @(posedge clk);
        @(negedge clk);
        sw_done = 1'b0;
        @(posedge clk); #1;
        expect_eq("swap holds renderer off", sw_enable, 1'b0);
        expect_eq("swap bank unchanged while pending", sw_bank, 1'b0);

        // Frame boundary: the swap lands and the renderer is released.
        @(negedge clk);
        sw_tick = 1'b1;
        @(posedge clk);
        @(negedge clk);
        sw_tick = 1'b0; #1;
        expect_eq("swap flips bank on frame tick", sw_bank, 1'b1);
        expect_eq("swap releases renderer", sw_enable, 1'b1);
    endtask

    // ==================================================================
    // 4. End to end: the panel path through the socket layer.
    // ==================================================================
    wire [7:0] io0, io1;

    // The core takes its clocks as inputs so this test can drive them; the top
    // level only adds the vendor PLLs, which no simulator here can elaborate.
    logic [15:0] core_por = 16'hffff;
    logic        core_resetn = 1'b0;
    logic        second_tick = 1'b0;

    // Synthetic second frame boundary, the role the transmitter plays in
    // hardware.  Pulsed well inside one panel frame so the swap is never
    // waiting on it.
    initial begin
        forever begin
            #2000 second_tick = 1'b1;
            #40   second_tick = 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (core_por != 16'd0) core_por <= core_por - 16'd1;
        else                   core_resetn <= 1'b1;
    end

    pmod_mirror_core #(.HDMI_BACKEND(1'b0), .TRANSPORT(1'b0)) core (
        .clk_pixel    (clk),
        .uart_rx      (1'b1),
        .uart_tx      (),
        .frame_tick_in(second_tick),
        .clk_pixel_x5 (clk),      // the TMDS serializers are not under test
        .resetn       (core_resetn),
        .pmod0_io     (io0),
        .pmod1_io     (io1),
        .tmds_clock   (),
        .tmds         (),
        // EXPOSE_STATE is clear here, so the core's own register bank supplies
        // the socket declaration and the hold and these are unused.
        .i_pmod0_personality (4'd0),
        .i_pmod1_personality (4'd0),
        .i_pmod0_flipped     (1'b0),
        .i_pmod1_flipped     (1'b0),
        .i_render_hold       (1'b0)
    );

    // Decode the SSD1331 pins out of the raw socket pins using the normal
    // seating map, so a wrong interleave shows up as a broken panel model.
    wire cs_n   = io0[0];       // lane 0
    wire mosi   = io0[2];       // lane 1
    wire sck    = io0[6];       // lane 3
    wire dc     = io0[1];       // lane 4
    wire vccen  = io0[5];       // lane 6
    wire pmoden = io0[7];       // lane 7

    localparam int MAX_BYTES = 256;
    logic [7:0] got [0:MAX_BYTES-1];
    logic       got_dc [0:MAX_BYTES-1];
    int         nbytes = 0;
    logic [7:0] sh = 8'h00;
    int         nbits = 0;
    logic       sck_q = 1'b1;

    int         frame_count = 0;
    int         since_window = 0;

    // The first pixel of every frame, as it was actually transmitted.  The menu
    // renderer's frame is fixed and begins at (0,0) with the cell word for that
    // coordinate, 0x0000; a frame's last pixel is 0x77DE.  A frame that begins
    // with 0x77DE is the signature of the address window handing straight into
    // the pixel loop instead of waiting -- the one-clock-early launch the mirror
    // check found on hardware before entry 56.  Asserting the exact start value
    // over many frames is what keeps that regression caught.
    localparam int MAX_CAPTURED = 24;
    logic [15:0] first_px [0:MAX_CAPTURED-1];
    logic        first_px_seen [0:MAX_CAPTURED-1];
    int          n_captured = 0;
    logic [7:0] px_hi = 8'h00, px_lo = 8'h00;
    logic       px_captured = 1'b0;

    always @(posedge clk) begin
        sck_q <= sck;
        if (!cs_n && sck && !sck_q) begin     // rising edge samples MOSI
            sh = {sh[6:0], mosi};
            nbits = nbits + 1;
            if (nbits == 8) begin
                if (nbytes < MAX_BYTES) begin
                    got[nbytes]    = sh;
                    got_dc[nbytes] = dc;
                end
                nbytes = nbytes + 1;
                nbits  = 0;

                // A command byte 0x15 is the frame's column-address window.
                if (dc == 0 && sh == 8'h15) begin
                    frame_count  = frame_count + 1;
                    since_window = 0;
                end else if (frame_count >= 3) begin
                    since_window = since_window + 1;
                    // The window is six bytes counting the 0x15 itself, so the
                    // first pixel's high byte is the sixth byte after it.
                    if (since_window == 6) px_hi = sh;
                    if (since_window == 7) begin
                        px_lo       = sh;
                        px_captured = 1'b1;
                        if (frame_count < MAX_CAPTURED) begin
                            first_px[frame_count]      = {px_hi, sh};
                            first_px_seen[frame_count] = 1'b1;
                        end
                    end
                end
            end
        end
    end

    task automatic panel_check;
        if (nbytes < INIT_LEN + 9) begin
            failures = failures + 1;
            $display("FAIL panel: only %0d bytes seen", nbytes);
            return;
        end
        expect_eq("panel init 0xFD", got[0],  8'hFD);
        expect_eq("panel init 0x12", got[1],  8'h12);
        expect_eq("panel init 0xAE", got[2],  8'hAE);
        expect_eq("panel display on", got[INIT_LEN], 8'hAF);
        expect_eq("panel window column cmd", got[INIT_LEN + 1], 8'h15);
        expect_eq("panel window row cmd",    got[INIT_LEN + 4], 8'h75);
        expect_eq("panel pixel is data", got_dc[INIT_LEN + 7], 1'b1);
        if (vccen !== 1'b1)  note_fail("panel VCCEN high by pixel time");
        if (pmoden !== 1'b1) note_fail("panel PMODEN high by pixel time");

        // Frame 3 is the first that can carry the menu frame: the renderer fills
        // the back bank, the swap lands at the end of frame 1, and each backend
        // latches its read bank at its own next frame boundary, so the panel
        // picks the new bank up at frame 3.
        expect_eq("panel reached frame 3", frame_count >= 3 ? 1 : 0, 1);
        // The two bytes that follow the address window must be emitted as data,
        // which is what proves the pixel stream comes out of the frame store and
        // follows the window.  The pixel's value is checked against the menu
        // model in the first-pixel loop below; a full per-pixel comparison of
        // the panel stream is the mirror check's job on hardware.
        expect_eq("panel pixel high byte is data", got_dc[INIT_LEN + 7], 1'b1);
        expect_eq("panel pixel low byte is data",  got_dc[INIT_LEN + 8], 1'b1);
        if (!px_captured) note_fail("panel pixel never captured");

        // Every captured frame must start with the menu frame's (0,0) pixel.
        // A frame starting with the previous frame's last pixel (0x77DE) is the
        // one-clock-early launch: the address window handing into the loop.
        for (int i = 0; i < MAX_CAPTURED; i++) begin
            if (!first_px_seen[i]) continue;
            n_captured = n_captured + 1;
            if (first_px[i] !== 16'h0000) begin
                failures = failures + 1;
                $display("FAIL panel: frame %0d first pixel 0x%04x is not the expected 0x0000",
                         i, first_px[i]);
            end
        end
        if (n_captured < 8) begin
            failures = failures + 1;
            $display("FAIL panel: only %0d frames captured; at least 8 are needed",
                     n_captured);
        end
    endtask

    // ==================================================================
    // Run.
    // ==================================================================
    int prev_x1, prev_y1, prev_x8, prev_y8, prev_x11, prev_y11;

    initial begin
        sw_done = 1'b0; sw_tick = 1'b0;
        fs_we = 1'b0; fs_wb = 1'b0; fs_rb = 1'b0;
        for (int i = 0; i < MAX_CAPTURED; i++) first_px_seen[i] = 1'b0;
        fs_wx = 7'd0; fs_wy = 6'd0; fs_wpx = 16'h0000;
        fs_rx = 7'd0; fs_ry = 6'd0;

        repeat (4) @(posedge clk);
        rst <= 1'b0;

        // 1. Socket layer.
        check_socket();
        if (failures == 0)
            $display("PASS socket layer: interleave and orientation");

        // 2. Scan mapper over one full frame at each factor.
        @(negedge clk);
        prev_x1 = ox1; prev_y1 = oy1;
        for (int i = 0; i < 96 * 64; i++) begin
            @(negedge clk);
            check_mapper("K=1", 1, 0, 0, prev_x1[11:0], prev_y1[11:0], ox1, oy1, in1, sx1, sy1);
            prev_x1 = ox1; prev_y1 = oy1;
        end

        @(negedge clk);
        prev_x8 = ox8; prev_y8 = oy8;
        for (int i = 0; i < 800 * 600; i++) begin
            @(negedge clk);
            check_mapper("K=8", 8, 16, 44, prev_x8[11:0], prev_y8[11:0], ox8, oy8, in8, sx8, sy8);
            prev_x8 = ox8; prev_y8 = oy8;
        end

        @(negedge clk);
        prev_x11 = ox11; prev_y11 = oy11;
        for (int i = 0; i < 1280 * 720; i++) begin
            @(negedge clk);
            check_mapper("K=11", 11, 112, 8, prev_x11[11:0], prev_y11[11:0], ox11, oy11, in11, sx11, sy11);
            prev_x11 = ox11; prev_y11 = oy11;
        end

        if (failures == 0)
            $display("PASS scan mapper: %0d coordinates, %0d inside the image", scanned, n_inside);

        // 3. Frame store and swap.
        frame_store_check();
        swap_check();
        if (failures == 0)
            $display("PASS frame store: both banks, row multiply, swap handshake");

        // 4. End to end.
        wait (px_captured);
        // Let enough panel frames go by before judging the first pixels that the
        // swap has landed and the panel is steady on the menu frame.
        #200ms;
        panel_check();
        if (failures == 0)
            $display("PASS panel path: init list and frame 2 pixels through the socket layer");

        // 5. Renderer liveness, now that the panel is running.  The window
        //    must exceed one panel frame or zero renders would mean nothing.
        begin
            int renders = 0;
            int ticks   = 0;
            for (int i = 0; i < 8_000_000; i++) begin
                @(posedge clk);
                if (core.render_done)        renders = renders + 1;
                if (core.oled.panel.frame_start) ticks = ticks + 1;
            end
            $display("DBG liveness window: renders=%0d panel_ticks=%0d", renders, ticks);
            if (renders >= 2 && ticks >= 2)
                $display("PASS renderer liveness: %0d frames, %0d panel ticks", renders, ticks);
            else begin
                failures = failures + 1;
                $display("FAIL renderer liveness: %0d frames, %0d panel ticks in 8M cycles",
                         renders, ticks);
            end
        end

        // 6. The host model the mirror check uses, checked against the RTL.
        //    The tool judges hardware with this frame function; if it drifts
        //    from the renderer the gate fails a correct board, so the model is
        //    verified here and not only on the bench.
        begin
            logic [31:0] exp = exp_frame_fold();
            wait (core.render_done);
            repeat (4) @(posedge clk);
            if (core.source_signature !== exp) begin
                failures = failures + 1;
                $display("FAIL source model: measured 0x%08x modelled 0x%08x",
                         core.source_signature, exp);
            end else begin
                $display("PASS source model: signature 0x%08x matches the host frame", exp);
            end
        end

        if (failures != 0) begin
            $display("ui_mirror: %0d FAILURES", failures);
            $fatal(1);
        end
        $display("ui_mirror: all checks passed");
        $finish;
    end

    // Bound the run so a stuck design fails instead of hanging.
    initial begin
        #1200ms;
        $display("FAIL ui_mirror: timeout after 1200 ms of simulated time");
        $fatal(1);
    end
endmodule
