// SPDX-License-Identifier: GPL-3.0-only
//
// Dual-clock registered link between the AE350 RAM bridge (beside the AE350
// macro, on the 75 MHz bus clock) and the Gowin DDR3 controller's native
// port (beside the DDR3 pins, on the 100 MHz controller user clock).  The
// two ends sit at opposite sides of the die and run on unrelated clocks, so
// every crossing is a reset-capable dual-clock FIFO with Gray-coded
// pointers (async_fifo_rst): commands go forward on bclk -> cclk and read
// lines return on cclk -> bclk.  Nothing combinational crosses either way.
//
//   command   bridge -> fwd_fifo -> controller, issued with cmd_ready /
//             wr_data_rdy
//   response  rd_data -> rsp_fifo -> bridge
//
// Commands stay in order through the FIFO and the controller executes them
// in order, so a read sent after a write to the same line returns the new
// data.  The bridge keeps at most one read outstanding and always accepts
// its response, so the response FIFO never holds more than one entry in
// steady state; rsp_ready (the bridge's read-wait flag) pops it.  The bridge
// issues at most one command per cycle while the forward FIFO has space,
// which the FIFO's registered wready provides.
//
// Both FIFOs clear on the same slow CPU reset: the bridge side resets on
// rst directly and the controller side on the two-stage synchronized copy,
// so no stale command or response survives a CPU restart.

module ae350_ram_link #(
    parameter int DEPTH_BITS = 3
) (
    input  logic         bclk,          // bridge/bus clock (75 MHz)
    input  logic         rst,           // bridge-side reset (bclk)
    input  logic         cclk,          // controller user clock (100 MHz)

    // Bridge side (bclk).
    input  logic         cmd_valid,
    input  logic         cmd_write,
    input  logic [24:0]  cmd_line,
    input  logic [255:0] cmd_data,
    input  logic [31:0]  cmd_mask,      // 1 = byte written
    output logic         cmd_ready,     // forward FIFO has space
    output logic         idle,          // forward FIFO empty (diagnostic)
    output logic         rsp_valid,
    output logic [255:0] rsp_data,
    input  logic         rsp_ready,     // bridge accepts the response

    // Gowin DDR3 controller native port (cclk).
    input  logic         ctrl_cmd_ready,
    output logic [2:0]   ctrl_cmd,
    output logic         ctrl_cmd_en,
    output logic [28:0]  ctrl_addr,
    input  logic         ctrl_wr_data_rdy,
    output logic [255:0] ctrl_wr_data,
    output logic         ctrl_wr_data_en,
    output logic         ctrl_wr_data_end,
    output logic [31:0]  ctrl_wr_data_mask,
    input  logic [255:0] ctrl_rd_data,
    input  logic         ctrl_rd_data_valid
);

    localparam int W = 1 + 25 + 32 + 256;   // {write, line, mask, data}

    // Reset for the controller (cclk) side, synchronized from the bridge
    // reset.  rst is a slow level held for many cycles, so two flip-flop
    // stages are safe.
    logic [1:0] rst_cclk_sync /* synthesis syn_srlstyle = "registers" */ = 2'b11;
    always_ff @(posedge cclk)
        rst_cclk_sync <= {rst_cclk_sync[0], rst};
    wire cclk_rst = rst_cclk_sync[1];

    // ------------------------------------------------------------------
    // Forward command FIFO (bclk -> cclk).  The command is packed behind a
    // bridge-side register so the wide field is stable for the whole FIFO
    // write, as in the original single-clock link.
    // ------------------------------------------------------------------
    logic [W-1:0] a_cmd;
    logic         a_cmd_valid;
    wire a_send = cmd_valid && cmd_ready;

    always_ff @(posedge bclk) begin
        if (a_send)
            a_cmd <= {cmd_write, cmd_line, cmd_mask, cmd_data};
        a_cmd_valid <= a_send;
        if (rst)
            a_cmd_valid <= 1'b0;
    end

    logic [W-1:0] fwd_rdata;
    logic         fwd_rvalid;
    logic         fwd_rempty;
    logic         fwd_wready;

    wire b_issue = fwd_rvalid && ctrl_cmd_ready &&
                   (!fwd_rdata[W-1] || ctrl_wr_data_rdy);

    async_fifo_rst #(
        .WIDTH      (W),
        .DEPTH_BITS (DEPTH_BITS)
    ) fwd_fifo (
        .wclk   (bclk),
        .wrst   (rst),
        .wdata  (a_cmd),
        .wvalid (a_cmd_valid),
        .wready (fwd_wready),
        .rclk   (cclk),
        .rrst   (cclk_rst),
        .rdata  (fwd_rdata),
        .rvalid (fwd_rvalid),
        .rempty (fwd_rempty),
        .rready (b_issue)
    );

    // The bridge sees a ready only while the forward FIFO has space and the
    // bridge-side command register is empty, so the one-cycle command
    // pipeline plus the FIFO never exceeds the FIFO depth.
    assign cmd_ready = fwd_wready && !a_cmd_valid;

    // ------------------------------------------------------------------
    // Controller side: issue commands from the FIFO head.
    // ------------------------------------------------------------------
    wire [W-1:0] b_head       = fwd_rdata;
    wire         b_head_write = b_head[W-1];
    wire [24:0]  b_head_line  = b_head[W-2 -: 25];
    wire [31:0]  b_head_mask  = b_head[287:256];

    assign ctrl_cmd          = b_head_write ? 3'b000 : 3'b001;
    assign ctrl_cmd_en       = b_issue;
    assign ctrl_addr         = {1'b0, b_head_line, 3'b000};
    assign ctrl_wr_data      = b_head[255:0];
    assign ctrl_wr_data_en   = b_issue && b_head_write;
    assign ctrl_wr_data_end  = b_issue && b_head_write;
    assign ctrl_wr_data_mask = ~b_head_mask;

    // ------------------------------------------------------------------
    // Response FIFO (cclk -> bclk).
    // ------------------------------------------------------------------
    async_fifo_rst #(
        .WIDTH      (256),
        .DEPTH_BITS (2)
    ) rsp_fifo (
        .wclk   (cclk),
        .wrst   (cclk_rst),
        .wdata  (ctrl_rd_data),
        .wvalid (ctrl_rd_data_valid),
        .wready (),
        .rclk   (bclk),
        .rrst   (rst),
        .rdata  (rsp_data),
        .rvalid (rsp_valid),
        .rempty (),
        .rready (rsp_ready)
    );

    // ------------------------------------------------------------------
    // idle: the forward FIFO is empty (diagnostic only).  The read-side
    // empty flag is synchronized back to the bridge clock, so it is
    // approximate and lagging, which is sufficient for the debug state word.
    // ------------------------------------------------------------------
    logic [1:0] fwd_empty_sync /* synthesis syn_srlstyle = "registers" */ = 2'b11;
    always_ff @(posedge bclk)
        fwd_empty_sync <= {fwd_empty_sync[0], fwd_rempty};
    assign idle = fwd_empty_sync[1];

endmodule
