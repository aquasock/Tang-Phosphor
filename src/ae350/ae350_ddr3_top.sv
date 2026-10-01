// SPDX-License-Identifier: GPL-3.0-only
//
// Tang-Phosphor AE350 + DDR3 image: the A25 runs programs from the board's
// 1 GiB x32 DDR3, loaded from the SD card through Tang-Control.  The whole
// AE350/DDR3 subsystem lives in ae350_subsystem (shared with the merged
// player image); this top adds the transport at its own 50 MHz board clock.
//
// Tang-Control debug map: reads of 0x000-0x3bc return the AE350 register
// block (see ae350_exts_regs.sv), 0x3c0-0x3fc the stream/status view (see
// ae350_subsystem.sv).

module ae350_ddr3_top (
    input  logic        clk,
    input  logic        uart_rx,
    output logic        uart_tx,

    output logic [14:0] ddr_addr,
    output logic [2:0]  ddr_bank,
    output logic        ddr_cs,
    output logic        ddr_ras,
    output logic        ddr_cas,
    output logic        ddr_we,
    output logic        ddr_ck,
    output logic        ddr_ck_n,
    output logic        ddr_cke,
    output logic        ddr_odt,
    output logic        ddr_reset_n,
    output logic [3:0]  ddr_dm,
    inout  wire  [31:0] ddr_dq,
    inout  wire  [3:0]  ddr_dqs,
    inout  wire  [3:0]  ddr_dqs_n
);

    // Board-clock power-on reset (about 1.3 ms) for the transport.
    logic [15:0] por_count = '1;
    logic        por_n = 1'b0;

    always_ff @(posedge clk) begin
        if (por_count != 0)
            por_count <= por_count - 16'd1;
        por_n <= por_count == 0;
    end

    logic        stream_start, stream_end, stream_cancel;
    logic [7:0]  stream_data;
    logic        stream_valid, stream_ready;

    logic        debug_valid, debug_write;
    logic [31:0] debug_address, debug_wdata, debug_rdata;

    ae350_subsystem subsystem (
        .clk           (clk),
        .tclk          (clk),
        .ddr_addr      (ddr_addr),
        .ddr_bank      (ddr_bank),
        .ddr_cs        (ddr_cs),
        .ddr_ras       (ddr_ras),
        .ddr_cas       (ddr_cas),
        .ddr_we        (ddr_we),
        .ddr_ck        (ddr_ck),
        .ddr_ck_n      (ddr_ck_n),
        .ddr_cke       (ddr_cke),
        .ddr_odt       (ddr_odt),
        .ddr_reset_n   (ddr_reset_n),
        .ddr_dm        (ddr_dm),
        .ddr_dq        (ddr_dq),
        .ddr_dqs       (ddr_dqs),
        .ddr_dqs_n     (ddr_dqs_n),
        .stream_start  (stream_start),
        .stream_end    (stream_end),
        .stream_cancel (stream_cancel),
        .stream_data   (stream_data),
        .stream_valid  (stream_valid),
        .stream_ready  (stream_ready),
        .play_start    (),
        .play_end      (),
        .play_cancel   (),
        .play_data     (),
        .play_valid    (),
        .play_ready    (1'b1),
        .play_id       (),
        .debug_valid   (debug_valid),
        .debug_write   (debug_write),
        .debug_address (debug_address),
        .debug_wdata   (debug_wdata),
        .debug_rdata   (debug_rdata)
    );

    // CORE_ID 0x0353 tags this image; Tang-Control reports its low byte.
    iosys_bl616 #(
        .CORE_ID (16'h0353),
        .FREQ    (50_000_000)
    ) u_iosys (
        .clk           (clk),
        .hclk          (clk),
        .resetn        (por_n),
        .overlay_x     (8'd0),
        .overlay_y     (8'd0),
        .joy1          (12'd0),
        .joy2          (12'd0),
        .mgmt_readdata (16'd0),
        .fdd_request   (2'd0),
        .debug_valid   (debug_valid),
        .debug_write   (debug_write),
        .debug_address (debug_address),
        .debug_wdata   (debug_wdata),
        .debug_rdata   (debug_rdata),
        .stream_start  (stream_start),
        .stream_end    (stream_end),
        .stream_cancel (stream_cancel),
        .stream_data   (stream_data),
        .stream_valid  (stream_valid),
        .stream_ready  (stream_ready),
        .uart_rx       (uart_rx),
        .uart_tx       (uart_tx)
    );

endmodule
