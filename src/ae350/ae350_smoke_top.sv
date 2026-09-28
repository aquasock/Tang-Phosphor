// Tang-Phosphor standalone AE350 proof-of-life image.
// SPDX-License-Identifier: GPL-3.0-only

module ae350_smoke_top (
    input  wire sys_clk,
    input  wire UART_RXD,
    output wire UART_TXD
);

wire pll_lock;
wire core_clk;
wire bus_clk;
logic [7:0] reset_counter = 8'hff;
logic resetn = 1'b0;
wire cpu_started;
wire debug_valid;
wire debug_write;
wire [31:0] debug_address;
wire [31:0] debug_wdata;

ae350_pll cpu_pll (
    .lock(pll_lock),
    .cpu_clk(core_clk),
    .bus_clk(bus_clk),
    .clkin(sys_clk)
);

always_ff @(posedge bus_clk or negedge pll_lock) begin
    if (!pll_lock) begin
        reset_counter <= 8'hff;
        resetn <= 1'b0;
    end else if (!resetn) begin
        if (reset_counter == 0)
            resetn <= 1'b1;
        else
            reset_counter <= reset_counter - 1'b1;
    end
end

ae350_soc_smoke soc (
    .bus_clk(bus_clk),
    .core_clk(core_clk),
    .resetn(resetn),
    .cpu_started(cpu_started)
);

// Reuse the proven TangCore UART framing so the running smoke image can be
// checked without a scope. CORE_ID 0350 tags this diagnostic image, although
// the legacy core-ID response transmits only its low byte (50). Reading any
// debug address returns 1 only after the AE350 firmware completes its AHB write.
iosys_bl616 #(
    .CORE_ID(16'h0350),
    .FREQ(75_000_000)
) tangcore_io (
    .clk(bus_clk),
    .hclk(bus_clk),
    .resetn(resetn),
    .overlay_x(8'b0),
    .overlay_y(8'b0),
    .joy1(12'b0),
    .joy2(12'b0),
    .mgmt_readdata(16'b0),
    .fdd_request(2'b0),
    .debug_valid(debug_valid),
    .debug_write(debug_write),
    .debug_address(debug_address),
    .debug_wdata(debug_wdata),
    .debug_rdata({31'b0, cpu_started}),
    .stream_ready(1'b1),
    .uart_rx(UART_RXD),
    .uart_tx(UART_TXD)
);

endmodule
