// SPDX-License-Identifier: GPL-3.0-only
//
// Registered link between the AE350 RAM bridge (beside the AE350 macro) and
// the Gowin DDR3 controller's native port (beside the DDR3 pins), which sit
// at opposite sides of the die.  Both ends run on the controller's user
// clock.
//
// Every signal that crosses the die leaves a register and lands in a
// register, with STAGES further registers in between and no logic on the
// way, so the crossing is a bare-wire timing path whatever the placement.
// Nothing combinational returns across the die either: the bridge may send
// one command per cycle while it holds a credit, and the memory side returns
// a credit as each command is issued to the controller.
//
//   command   bridge -> a_cmd -> fwd x STAGES -> b_fifo (DEPTH entries)
//                        -> controller, issued with cmd_ready/wr_data_rdy
//   credit    issue  -> b_credit -> bwd x STAGES -> a_credit_in -> a_credits
//   response  rd_data -> b_rsp -> bwd x STAGES -> a_rsp -> bridge
//
// Commands stay in order through the FIFO and the controller executes them
// in order, so a read sent after a write to the same line returns the new
// data.  The bridge keeps at most one read outstanding and always accepts its
// response, so the response path needs no flow control.
//
// Register names carry the side they belong to (a_ at the bridge, b_ at the
// controller, fwd_/bwd_ in transit); the merged image's floorplan places the
// a_ and b_ registers by name.

module ae350_ram_link #(
    parameter int STAGES     = 1,
    parameter int DEPTH_BITS = 2
) (
    input  logic         clk,
    input  logic         rst,

    // Bridge side.
    input  logic         cmd_valid,
    input  logic         cmd_write,
    input  logic [24:0]  cmd_line,
    input  logic [255:0] cmd_data,
    input  logic [31:0]  cmd_mask,     // 1 = byte written
    output logic         cmd_ready,    // a credit is available
    output logic         idle,         // every credit is home
    output logic         rsp_valid,
    output logic [255:0] rsp_data,

    // Gowin DDR3 controller native port.
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

    localparam int DEPTH = 1 << DEPTH_BITS;
    localparam int W     = 1 + 25 + 32 + 256;   // {write, line, mask, data}

    // ------------------------------------------------------------------
    // Bridge side: command source register and credits.
    // ------------------------------------------------------------------
    logic                a_cmd_valid /* synthesis syn_srlstyle = "registers" */;
    logic [W-1:0]        a_cmd       /* synthesis syn_srlstyle = "registers" */;
    logic [DEPTH_BITS:0] a_credits;
    logic                a_ready;
    logic                a_idle;
    logic                a_credit_in /* synthesis syn_srlstyle = "registers" */;
    logic                a_rsp_valid /* synthesis syn_srlstyle = "registers" */;
    logic [255:0]        a_rsp       /* synthesis syn_srlstyle = "registers" */;

    wire a_send = cmd_valid && a_ready;

    assign cmd_ready = a_ready;
    assign idle      = a_idle;
    assign rsp_valid = a_rsp_valid;
    assign rsp_data  = a_rsp;

    // ------------------------------------------------------------------
    // Transit registers, STAGES deep in each direction; the *_far signals
    // are what the receiving side lands.
    // ------------------------------------------------------------------
    logic            b_credit    /* synthesis syn_srlstyle = "registers" */;
    logic            b_rsp_valid /* synthesis syn_srlstyle = "registers" */;
    logic [255:0]    b_rsp       /* synthesis syn_srlstyle = "registers" */;

    logic            fwd_valid_far;
    logic [W-1:0]    fwd_cmd_far;
    logic            bwd_credit_far;
    logic            bwd_rsp_valid_far;
    logic [255:0]    bwd_rsp_far;

    // Packed shift registers in a plain always_ff, not a generate block:
    // Gowin's constraint reader exhausts memory on primitive groups when the
    // netlist holds these registers under a generate scope.  With STAGES = 0
    // the registers are unused and synthesis removes them.
    localparam int SR = STAGES > 0 ? STAGES : 1;

    // syn_srlstyle keeps every stage a flip-flop: GowinSynthesis otherwise
    // folds register chains into SSRAM shift registers (see the synchronizer
    // rule in .ai/core-reference.md), which cannot be spread across the die.
    logic [SR-1:0]          fwd_valid_q     /* synthesis syn_srlstyle = "registers" */;
    logic [SR-1:0][W-1:0]   fwd_cmd_q       /* synthesis syn_srlstyle = "registers" */;
    logic [SR-1:0]          bwd_credit_q    /* synthesis syn_srlstyle = "registers" */;
    logic [SR-1:0]          bwd_rsp_valid_q /* synthesis syn_srlstyle = "registers" */;
    logic [SR-1:0][255:0]   bwd_rsp_q       /* synthesis syn_srlstyle = "registers" */;

    always_ff @(posedge clk) begin
        fwd_valid_q[0]     <= rst ? 1'b0 : a_cmd_valid;
        fwd_cmd_q[0]       <= a_cmd;
        bwd_credit_q[0]    <= rst ? 1'b0 : b_credit;
        bwd_rsp_valid_q[0] <= rst ? 1'b0 : b_rsp_valid;
        bwd_rsp_q[0]       <= b_rsp;
        for (int i = 1; i < SR; i++) begin
            fwd_valid_q[i]     <= rst ? 1'b0 : fwd_valid_q[i - 1];
            fwd_cmd_q[i]       <= fwd_cmd_q[i - 1];
            bwd_credit_q[i]    <= rst ? 1'b0 : bwd_credit_q[i - 1];
            bwd_rsp_valid_q[i] <= rst ? 1'b0 : bwd_rsp_valid_q[i - 1];
            bwd_rsp_q[i]       <= bwd_rsp_q[i - 1];
        end
    end

    assign fwd_valid_far     = STAGES == 0 ? a_cmd_valid : fwd_valid_q[SR-1];
    assign fwd_cmd_far       = STAGES == 0 ? a_cmd       : fwd_cmd_q[SR-1];
    assign bwd_credit_far    = STAGES == 0 ? b_credit    : bwd_credit_q[SR-1];
    assign bwd_rsp_valid_far = STAGES == 0 ? b_rsp_valid : bwd_rsp_valid_q[SR-1];
    assign bwd_rsp_far       = STAGES == 0 ? b_rsp       : bwd_rsp_q[SR-1];

    always_ff @(posedge clk) begin
        logic [DEPTH_BITS:0] credits;
        credits = a_credits - (DEPTH_BITS + 1)'(a_send) + (DEPTH_BITS + 1)'(a_credit_in);

        a_cmd_valid <= a_send;
        if (a_send)
            a_cmd <= {cmd_write, cmd_line, cmd_mask, cmd_data};
        a_credits   <= credits;
        a_ready     <= credits != 0;
        a_idle      <= credits == (DEPTH_BITS + 1)'(DEPTH);
        a_credit_in <= bwd_credit_far;
        a_rsp_valid <= bwd_rsp_valid_far;
        if (bwd_rsp_valid_far)
            a_rsp <= bwd_rsp_far;

        if (rst) begin
            a_cmd_valid <= 1'b0;
            a_credits   <= (DEPTH_BITS + 1)'(DEPTH);
            a_ready     <= 1'b1;
            a_idle      <= 1'b1;
            a_credit_in <= 1'b0;
            a_rsp_valid <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // Controller side: command FIFO, issue, and response capture.  The
    // credits guarantee the FIFO never overflows.
    // ------------------------------------------------------------------
    (* syn_ramstyle = "registers" *) logic [W-1:0] b_fifo [DEPTH];
    logic [DEPTH_BITS:0] b_wptr;
    logic [DEPTH_BITS:0] b_rptr;

    wire [W-1:0] b_head       = b_fifo[b_rptr[DEPTH_BITS-1:0]];
    wire         b_head_write = b_head[W-1];
    wire [24:0]  b_head_line  = b_head[W-2 -: 25];
    wire [31:0]  b_head_mask  = b_head[287:256];
    wire         b_empty      = b_wptr == b_rptr;
    wire         b_issue      = !b_empty && ctrl_cmd_ready &&
                                (!b_head_write || ctrl_wr_data_rdy);

    assign ctrl_cmd          = b_head_write ? 3'b000 : 3'b001;
    assign ctrl_cmd_en       = b_issue;
    assign ctrl_addr         = {1'b0, b_head_line, 3'b000};
    assign ctrl_wr_data      = b_head[255:0];
    assign ctrl_wr_data_en   = b_issue && b_head_write;
    assign ctrl_wr_data_end  = b_issue && b_head_write;
    assign ctrl_wr_data_mask = ~b_head_mask;

    always_ff @(posedge clk) begin
        if (fwd_valid_far) begin
            b_fifo[b_wptr[DEPTH_BITS-1:0]] <= fwd_cmd_far;
            b_wptr <= b_wptr + 1'b1;
        end
        if (b_issue)
            b_rptr <= b_rptr + 1'b1;
        b_credit    <= b_issue;
        b_rsp_valid <= ctrl_rd_data_valid;
        if (ctrl_rd_data_valid)
            b_rsp <= ctrl_rd_data;

        if (rst) begin
            b_wptr      <= '0;
            b_rptr      <= '0;
            b_credit    <= 1'b0;
            b_rsp_valid <= 1'b0;
        end
    end

endmodule
