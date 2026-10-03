// SPDX-License-Identifier: GPL-3.0-only
//
// Self-checking test for the slice-1 menu renderer.
//
// Everything here is checked against an expectation computed in this file, not
// read back out of the DUT:
//
//   * raster order       -- write N is at (N % 96, N / 96), 6144 writes a frame
//   * pixel derivation   -- each pixel equals the cell-index word for its own
//                           coordinate, computed independently here
//   * distinctness       -- within one frame, no two of the 6144 pixels carry
//                           the same word (the frame repeats frame to frame)
//   * back-bank targeting-- every write lands in the bank the outputs are not
//                           reading, and the target alternates frame to frame
//   * handshake          -- a frame starts only while the swap is idle, and
//                           only after the swap has acknowledged the previous
//                           render_done (render_enable low) and completed (high)
//   * hold               -- with hold asserted between frames, no frame starts
//
// A real ui_swap drives render_enable and bank, so the handshake under test is
// the one that runs in hardware rather than a stimulus that assumes its shape.

`timescale 1ns/1ps

module ui_menu_renderer_tb;
    localparam int W = 96;
    localparam int H = 64;
    localparam int PIXELS = W * H;

    logic clk = 1'b0;
    always #10 clk = ~clk;              // 20 ns period

    int failures = 0;

    task automatic fail(input string what);
        failures = failures + 1;
        $display("FAIL %s", what);
    endtask

    // ---- independent model of the proof frame -------------------------
    function automatic logic [15:0] exp_pixel(input int px, input int py);
        int col, in_col, row, in_row;
        begin
            col    = px / 6;
            in_col = px % 6;
            row    = py / 8;
            in_row = py % 8;
            exp_pixel = {1'b0, row[2:0], 1'b0, col[3:0], in_col[2:0], in_row[2:0], 1'b0};
        end
    endfunction

    // ---- DUT and the real swap ----------------------------------------
    logic rst = 1'b1;
    logic hold = 1'b0;
    logic bank, render_enable;
    logic we, wr_bank, render_done;
    logic [6:0]  wr_x;
    logic [5:0]  wr_y;
    logic [15:0] wr_px;

    ui_menu_renderer #(.W(W), .H(H)) dut (
        .clk           (clk),
        .rst           (rst),
        .bank          (bank),
        .render_enable (render_enable),
        .hold          (hold),
        .we            (we),
        .wr_bank       (wr_bank),
        .wr_x          (wr_x),
        .wr_y          (wr_y),
        .wr_px         (wr_px),
        .render_done   (render_done)
    );

    logic frame_tick;
    ui_swap #(.OUTPUTS(1)) swap (
        .clk           (clk),
        .rst           (rst),
        .render_done   (render_done),
        .frame_tick    (frame_tick),
        .bank          (bank),
        .render_enable (render_enable)
    );

    // One output frame tick every 32 cycles, well inside a 6144-cycle frame.
    int tick_ctr = 0;
    always @(posedge clk) begin
        frame_tick = (tick_ctr == 31);
        tick_ctr   = (tick_ctr == 31) ? 0 : tick_ctr + 1;
    end

    // ---- write monitor -------------------------------------------------
    // Blocking updates so the initial block's polling observes them directly.
    int  widx        = 0;      // pixel index within the current frame
    int  frame_no    = 0;      // frames started
    int  done_count  = 0;      // frames completed (render_done pulses)
    int  wr_total    = 0;      // writes since time zero, for the hold test
    int  seen_stamp [0:65535]; // frame number in which a pixel word was last seen
    int  frames_seen     = 0;
    int  writes_since_done = 0; // pixels written since the last render_done
    logic bank_prev  = 1'b0;
    logic need_ack   = 1'b0;   // render_done raised; owe an enable cycle
    logic saw_low    = 1'b0;   // render_enable has been low since that pulse

    always @(posedge clk) begin
        if (rst) begin
            widx        = 0;
            frame_no    = 0;
            done_count  = 0;
            wr_total    = 0;
            frames_seen = 0;
            writes_since_done = 0;
            need_ack    = 1'b0;
            saw_low     = 1'b0;
        end else begin
            if (we) begin
                int ex = widx % W;
                int ey = widx / W;
                logic [15:0] epx = exp_pixel(ex, ey);

                if (wr_x !== ex[6:0])
                    fail($sformatf("x at idx %0d: got %0d want %0d", widx, wr_x, ex));
                if (wr_y !== ey[5:0])
                    fail($sformatf("y at idx %0d: got %0d want %0d", widx, wr_y, ey));
                if (wr_px !== epx)
                    fail($sformatf("px at (%0d,%0d): got %04x want %04x", ex, ey, wr_px, epx));
                if (wr_bank !== ~bank)
                    fail($sformatf("write to the displayed bank at idx %0d", widx));

                // A frame may only begin while the swap is idle and, after the
                // first frame, only once the previous render_done was seen.
                if (widx == 0) begin
                    frame_no = frame_no + 1;
                    if (render_enable !== 1'b1)
                        fail("frame started while the swap was not idle");
                    if (need_ack && !saw_low)
                        fail("frame started before the swap acknowledged render_done");
                    if (frames_seen > 0 && wr_bank === bank_prev)
                        fail("consecutive frames targeted the same bank");
                    bank_prev   = wr_bank;
                    frames_seen = frames_seen + 1;
                    need_ack    = 1'b0;
                    saw_low     = 1'b0;
                end

                // Distinct within a frame: the same word may only recur in a
                // later frame, which is why the stamp is the frame number.
                if (seen_stamp[wr_px] == frame_no)
                    fail($sformatf("pixel word %04x written twice in frame %0d", wr_px, frame_no));
                seen_stamp[wr_px] = frame_no;

                widx     = (widx == PIXELS - 1) ? 0 : widx + 1;
                wr_total = wr_total + 1;
                writes_since_done = writes_since_done + 1;
            end

            if (!render_enable && need_ack) saw_low = 1'b1;

            if (render_done) begin
                // render_done is registered, so it rides the cycle after the
                // last write: a whole frame must have landed since the last
                // one, and the index must have wrapped to zero.
                if (writes_since_done != PIXELS)
                    fail($sformatf("render_done after %0d pixels, want %0d", writes_since_done, PIXELS));
                if (widx != 0)
                    fail($sformatf("render_done at idx %0d, not a frame boundary", widx));
                done_count = done_count + 1;
                writes_since_done = 0;
                need_ack   = 1'b1;
                saw_low    = 1'b0;
            end
        end
    end

    // ---- sequence ------------------------------------------------------
    initial begin
        rst = 1'b1;
        repeat (5) @(negedge clk);
        rst = 1'b0;

        // Let three frames run end to end.
        while (done_count < 3) @(negedge clk);

        if (wr_total != 3 * PIXELS)
            fail($sformatf("three frames wrote %0d pixels, want %0d", wr_total, 3 * PIXELS));
        if (frames_seen != 3)
            fail($sformatf("saw %0d frame starts, want 3", frames_seen));

        // Hold between frames: no pixel may be written while the renderer is
        // frozen.  Set hold in the idle gap right after a completed frame.
        hold = 1'b1;
        begin
            int w_before = wr_total;
            repeat (15000) @(negedge clk);   // > two full frames
            if (wr_total != w_before)
                fail($sformatf("renderer wrote %0d pixels while held", wr_total - w_before));
        end
        hold = 1'b0;

        // Releasing hold must let the next frame run.
        begin
            int done_before = done_count;
            while (done_count == done_before) @(negedge clk);
        end

        if (failures == 0)
            $display("PASS ui_menu_renderer: %0d frames, %0d pixels, raster order, back-bank targeting, handshake and hold all correct",
                     frames_seen, wr_total);
        else
            $display("ui_menu_renderer: %0d failures", failures);

        if (failures != 0) $fatal(1);
        $finish;
    end

    initial begin
        #50ms;
        $display("FAIL ui_menu_renderer: timeout");
        $fatal(1);
    end
endmodule
