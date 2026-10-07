// SPDX-License-Identifier: GPL-3.0-only
// Eight interleaved lanes, each a true dual-port 32768x9 timestamp plane.
// Explicit normal-write DPX9B avoids Gowin's unsupported 138K read-before-
// write inference. Both ports' inputs are registered ahead of the blocks, so
// address, enable and data pins are driven from flip-flops across all 128
// blocks, and a fabric register follows the sixteen-block read mux. Both
// ports have three-cycle read latency and one-cycle write latency, equal on
// both ports. The caller excludes cross-port read/write address-region
// collisions (UG300 section 3.1) on the unregistered inputs.
module scope_phosphor_ram (
    input logic clk,
    input logic [14:0] a_addr, b_addr,
    input logic a_read, b_read,
    input logic [7:0] a_we,
    input logic [8:0] a_data [0:7],
    output logic [8:0] a_q [0:7],
    output logic [8:0] b_q [0:7]
);
    logic [14:0] a_addr_q=0, b_addr_q=0;
    logic a_read_q=0, b_read_q=0;
    logic [7:0] a_we_q=0;
    logic [8:0] a_data_q [0:7];
    logic a_read_d=0, b_read_d=0;
    always_ff @(posedge clk) begin
        a_addr_q<=a_addr; b_addr_q<=b_addr;
        a_read_q<=a_read; b_read_q<=b_read; a_we_q<=a_we;
        for(integer g=0;g<8;g++) a_data_q[g]<=a_data[g];
        a_read_d<=a_read_q; b_read_d<=b_read_q;
    end
    for (genvar g=0;g<8;g++) begin : bank
// Hardware primitives are the default: Gowin does not define SYNTHESIS.
// Simulation benches explicitly request the portable behavioral model.
`ifndef SCOPE_RAM_BEHAVIORAL
        wire [17:0] raw_a[0:15], raw_b[0:15];
        logic [3:0] select_a,select_b;
        always_ff @(posedge clk) begin
            if(a_read_q) select_a<=a_addr_q[14:11];
            if(b_read_q) select_b<=b_addr_q[14:11];
            if(a_read_d) a_q[g]<=raw_a[select_a][8:0];
            if(b_read_d) b_q[g]<=raw_b[select_b][8:0];
        end
        for(genvar block_index=0;block_index<16;block_index++) begin : block_ram
            DPX9B #(
                .BIT_WIDTH_0(9),.BIT_WIDTH_1(9),
                .READ_MODE0(1'b0),.READ_MODE1(1'b0),
                .WRITE_MODE0(2'b00),.WRITE_MODE1(2'b00),
                .BLK_SEL_0(3'b0),.BLK_SEL_1(3'b0),.RESET_MODE("SYNC")
            ) ram (
                .DOA(raw_a[block_index]),.DOB(raw_b[block_index]),
                .DIA({9'd0,a_data_q[g]}),.DIB(18'd0),
                .ADA({a_addr_q[10:0],3'b0}),.ADB({b_addr_q[10:0],3'b0}),
                .BLKSELA(3'd0),.BLKSELB(3'd0),
                .WREA(a_we_q[g]),.WREB(1'b0),
                .CEA((a_read_q||a_we_q[g]) && a_addr_q[14:11]==4'(block_index)),
                .CEB(b_read_q && b_addr_q[14:11]==4'(block_index)),
                .CLKA(clk),.CLKB(clk),.OCEA(1'b1),.OCEB(1'b1),
                .RESETA(1'b0),.RESETB(1'b0)
            );
        end
`else
        logic [8:0] mem [0:32767];
        logic [8:0] raw_a,raw_b;
        always_ff @(posedge clk) begin
            if(a_we_q[g]) mem[a_addr_q]<=a_data_q[g];
            else if(a_read_q) raw_a<=mem[a_addr_q];
            if(b_read_q) raw_b<=mem[b_addr_q];
            if(a_read_d) a_q[g]<=raw_a;
            if(b_read_d) b_q[g]<=raw_b;
        end
`endif
    end
endmodule
