// SPDX-License-Identifier: GPL-3.0-only
// Reconfigure the existing 24 MHz-input PLL for native 44.1/48 kHz audio.
// CS4344 DS613F2 recommends >=10 zero frames before a clock change. Here
// 0.5 ms of silence precedes reset, and 300 ms of zero frames follow lock.
module i2s_clock_control #(
    parameter integer PRE_MUTE_CYCLES = 37_125,
    parameter integer RESET_CYCLES = 7_425,
    parameter integer SETTLE_CYCLES = 22_275_000
) (
    input logic clk,
    input logic resetn,
    input logic requested_48k,
    input logic [1:0] pll_locked,
    output logic pll_reset,
    output logic [6:0] mdsel, odsel,
    output logic [2:0] mdsel_frac, odsel_frac,
    output logic active_48k,
    output logic running,
    output logic ready
);
    localparam logic [2:0] RESET = 0, LOCK = 1, SETTLE = 2, RUN = 3, MUTE = 4;
    logic [2:0] state = RESET;
    logic [24:0] timer;
    logic [1:0] lock_meta /* synthesis syn_srlstyle = "registers" */;
    logic [1:0] lock_sync /* synthesis syn_srlstyle = "registers" */;

    // UG306 5.1: dynamic integer = 128 - divider; fraction = 7 - eighths.
    // 48k:   VCO 24*32 = 768 MHz; /62.5 = 12.288 MHz.
    // 44.1k: VCO 24*36.75 = 882 MHz; /78.125 = 11.2896 MHz.
    assign mdsel = active_48k ? 7'd96 : 7'd92;
    assign mdsel_frac = active_48k ? 3'd7 : 3'd1;
    assign odsel = active_48k ? 7'd66 : 7'd50;
    assign odsel_frac = active_48k ? 3'd3 : 3'd6;
    assign pll_reset = state == RESET;
    assign running = resetn && &lock_sync && !pll_reset &&
                     (state == SETTLE || state == RUN || state == MUTE);
    assign ready = running && state == RUN && requested_48k == active_48k;

    always_ff @(posedge clk) begin
        if (!resetn) begin
            state <= RESET;
            timer <= 25'(RESET_CYCLES - 1);
            active_48k <= 1;
            lock_meta <= 0;
            lock_sync <= 0;
        end else begin
            lock_meta <= pll_locked;
            lock_sync <= lock_meta;
            if (state != RESET && state != MUTE && requested_48k != active_48k) begin
                state <= MUTE;
                timer <= 25'(PRE_MUTE_CYCLES - 1);
            end else case (state)
                RESET: begin
                    if (requested_48k != active_48k) begin
                        active_48k <= requested_48k;
                        timer <= 25'(RESET_CYCLES - 1);
                    end else if (timer == 0) state <= LOCK;
                    else timer <= timer - 1'b1;
                end
                LOCK: if (&lock_sync) begin
                    state <= SETTLE;
                    timer <= 25'(SETTLE_CYCLES - 1);
                end
                SETTLE: begin
                    if (!(&lock_sync)) state <= LOCK;
                    else if (timer == 0) state <= RUN;
                    else timer <= timer - 1'b1;
                end
                RUN: if (!(&lock_sync)) state <= LOCK;
                MUTE: begin
                    if (timer == 0) begin
                        state <= RESET;
                        active_48k <= requested_48k;
                        timer <= 25'(RESET_CYCLES - 1);
                    end else timer <= timer - 1'b1;
                end
                default: begin
                    state <= RESET;
                    timer <= 25'(RESET_CYCLES - 1);
                end
            endcase
        end
    end
endmodule
