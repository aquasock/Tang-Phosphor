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
wire [31:0] cpu_cycles;
wire [31:0] ref_cycles;
wire [31:0] cycle_samples;
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

// Reference count of the 50 MHz board oscillator, which is independent of the
// AE350 PLL. It crosses into the bus domain in Gray code so that every
// synchronized value is one the counter actually held.
logic [31:0] ref_count_sys = 32'd0;
logic [31:0] ref_gray_sys = 32'd0;
// Keep the synchronizer in flip-flops; synthesis otherwise folds the
// two-stage chain into an SSRAM shift register.
logic [31:0] ref_gray_meta /* synthesis syn_srlstyle = "registers" */;
logic [31:0] ref_gray_sync /* synthesis syn_srlstyle = "registers" */;
logic [31:0] ref_count_bus;

always_ff @(posedge sys_clk) begin
    ref_count_sys <= ref_count_sys + 1'b1;
    ref_gray_sys <= ref_count_sys ^ (ref_count_sys >> 1);
end

always_ff @(posedge bus_clk or negedge resetn) begin
    if (!resetn) begin
        ref_gray_meta <= 32'd0;
        ref_gray_sync <= 32'd0;
        ref_count_bus <= 32'd0;
    end else begin
        ref_gray_meta <= ref_gray_sys;
        ref_gray_sync <= ref_gray_meta;
        for (int bit_index = 0; bit_index < 32; bit_index++)
            ref_count_bus[bit_index] <= ^(ref_gray_sync >> bit_index);
    end
end

ae350_soc_smoke soc (
    .bus_clk(bus_clk),
    .core_clk(core_clk),
    .resetn(resetn),
    .ref_count(ref_count_bus),
    .cpu_started(cpu_started),
    .cpu_cycles(cpu_cycles),
    .ref_cycles(ref_cycles),
    .cycle_samples(cycle_samples)
);

// A debug write to 0x10 freezes one cycle-count pair so the host can read
// both halves without the CPU replacing them between UART transactions.
logic [31:0] snapshot_cpu_cycles;
logic [31:0] snapshot_ref_cycles;
logic [31:0] debug_rdata;

always_ff @(posedge bus_clk or negedge resetn) begin
    if (!resetn) begin
        snapshot_cpu_cycles <= 32'd0;
        snapshot_ref_cycles <= 32'd0;
    end else if (debug_valid && debug_write && debug_address[7:0] == 8'h10) begin
        snapshot_cpu_cycles <= cpu_cycles;
        snapshot_ref_cycles <= ref_cycles;
    end
end

always_comb begin
    unique case (debug_address[7:0])
        8'h04: debug_rdata = snapshot_cpu_cycles;
        8'h08: debug_rdata = snapshot_ref_cycles;
        8'h0c: debug_rdata = cycle_samples;
        default: debug_rdata = {31'b0, cpu_started};
    endcase
end

// Reuse the proven TangCore UART framing so the running smoke image can be
// checked without a scope. CORE_ID 0350 tags this diagnostic image, although
// the legacy core-ID response transmits only its low byte (50). Debug address
// 0 returns 1 only after the AE350 firmware completes its AHB write; 0x04 and
// 0x08 return the frozen core and 50 MHz reference counts, 0x0c the number of
// cycle-count writes, and a write to 0x10 freezes a new pair.
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
    .link_mods(8'd0),
    .link_keys(48'd0),
    .mgmt_readdata(16'b0),
    .fdd_request(2'b0),
    .debug_valid(debug_valid),
    .debug_write(debug_write),
    .debug_address(debug_address),
    .debug_wdata(debug_wdata),
    .debug_rdata(debug_rdata),
    .stream_ready(1'b1),
    .uart_rx(UART_RXD),
    .uart_tx(UART_TXD)
);

endmodule
