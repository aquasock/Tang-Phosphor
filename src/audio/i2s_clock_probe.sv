// SPDX-License-Identifier: GPL-3.0-only
// Measure the actual MCLK over a reference-clock window, not the PLL's
// inferred frequency. The source counter crosses as registered Gray code.
module i2s_clock_probe #(
    parameter integer WINDOW_CYCLES = 7_425_000 // 100 ms at 74.25 MHz
) (
    input  logic        clk_ref,
    input  logic        clk_mclk,
    input  logic        resetn,
    input  logic [1:0]  pll_locked,
    output logic [31:0] count,
    output logic [2:0]  status
);
    logic [23:0] source_binary, source_gray;
    wire [23:0] source_next = source_binary + 24'd1;
    always_ff @(posedge clk_mclk or negedge resetn) begin
        if (!resetn) begin
            source_binary <= 0;
            source_gray <= 0;
        end else begin
            source_binary <= source_next;
            source_gray <= source_next ^ (source_next >> 1);
        end
    end

    logic [23:0] gray_meta /* synthesis syn_srlstyle = "registers" */;
    logic [23:0] gray_sync /* synthesis syn_srlstyle = "registers" */;
    logic [1:0] lock_meta /* synthesis syn_srlstyle = "registers" */;
    logic [1:0] lock_sync /* synthesis syn_srlstyle = "registers" */;
    logic [23:0] decoded;
    logic [$clog2(WINDOW_CYCLES)-1:0] window_count;
    logic [23:0] previous_count;
    logic measured;
    assign status = {measured, lock_sync};

    always_ff @(posedge clk_ref) begin
        if (!resetn) begin
            gray_meta <= 0;
            gray_sync <= 0;
            lock_meta <= 0;
            lock_sync <= 0;
            decoded <= 0;
            window_count <= 0;
            previous_count <= 0;
            count <= 0;
            measured <= 0;
        end else begin
            gray_meta <= source_gray;
            gray_sync <= gray_meta;
            lock_meta <= pll_locked;
            lock_sync <= lock_meta;
            // Parallel prefix parity, registered before the subtraction.
            for (integer k = 0; k < 24; k = k + 1)
                decoded[k] <= ^(gray_sync >> k);
            if (window_count == WINDOW_CYCLES - 1) begin
                window_count <= 0;
                count <= {8'b0, 24'(decoded - previous_count)};
                previous_count <= decoded;
                measured <= 1;
            end else window_count <= window_count + 1'b1;
        end
    end
endmodule
