// This file is part of Tang-Phosphor.
//
// The AE350 primitive integration is based on LiteX's Gowin AE350 wrapper:
// Copyright (c) 2024 Gwenhael Goavec-Merou <gwenhael@enjoy-digital.fr>
// Copyright (c) 2024-2026 Florent Kermarrec <florent@enjoy-digital.fr>
// SPDX-License-Identifier: BSD-2-Clause

// Minimal AE350 system used to prove reset-vector fetches and CPU-to-fabric
// writes before the USB host is connected. The four-word ROM performs:
//
//   lui  t0, 0xe8000       # Extended AHB peripheral aperture
//   addi t1, zero, 1
//   sw   t1, 0(t0)         # Enable the fabric heartbeat
//   j    .
//
// The ROM is intentionally combinational and tiny. Production firmware will
// use BSRAM once the hard-core integration has passed this gate.
module ae350_soc_smoke (
    input  wire bus_clk,
    input  wire core_clk,
    input  wire resetn,
    output logic cpu_started
);

wire [31:0] rom_haddr;
logic [31:0] rom_hrdata;
wire [1:0]  rom_htrans;
wire        rom_hwrite;

wire [31:0] exts_haddr;
wire [2:0]  exts_hburst;
wire [3:0]  exts_hprot;
wire        exts_hsel;
wire [2:0]  exts_hsize;
wire [1:0]  exts_htrans;
wire [31:0] exts_hwdata;
wire        exts_hwrite;

logic fabric_write_pending;

always_comb begin
    unique case (rom_haddr[3:2])
        2'd0: rom_hrdata = 32'he80002b7; // lui  t0, 0xe8000
        2'd1: rom_hrdata = 32'h00100313; // addi t1, zero, 1
        2'd2: rom_hrdata = 32'h0062a023; // sw   t1, 0(t0)
        default: rom_hrdata = 32'h0000006f; // jal zero, 0
    endcase
end

// AHB write data follows its address/control phase by one bus cycle.
always_ff @(posedge bus_clk or negedge resetn) begin
    if (!resetn) begin
        fabric_write_pending <= 1'b0;
        cpu_started <= 1'b0;
    end else begin
        if (fabric_write_pending && exts_hwdata[0])
            cpu_started <= 1'b1;

        fabric_write_pending <= exts_hsel && exts_htrans[1] && exts_hwrite &&
            (exts_haddr[31:16] == 16'he800);
    end
end

AE350_SOC cpu (
    .POR_N(1'b1),
    .HW_RSTN(resetn),
    .CORE_CLK(core_clk),
    .DDR_CLK(bus_clk),
    .AHB_CLK(bus_clk),
    .APB_CLK(bus_clk),
    .DBG_TCK(1'b1),
    .RTC_CLK(bus_clk),
    .CORE_CE(1'b1),
    .AXI_CE(1'b1),
    .DDR_CE(1'b1),
    .AHB_CE(1'b1),
    .APB_CE(8'b00000001),
    .APB2AHB_CE(1'b1),
    .PRESETN(),
    .HRESETN(),
    .DDR_RSTN(),

    .GP_INT(16'b0),
    .DMA_REQ(8'b0),
    .DMA_ACK(),
    .CORE0_WFI_MODE(),
    .WAKEUP_IN(1'b0),
    .RTC_WAKEUP(),
    .SCAN_TEST(1'b0),
    .SCAN_EN(1'b0),
    .SCAN_IN(20'hfffff),
    .SCAN_OUT(),
    .TEST_CLK(1'b0),
    .TEST_MODE(1'b0),
    .TEST_RSTN(1'b1),

    .INTEG_TCK(1'b1),
    .INTEG_TDI(1'b1),
    .INTEG_TMS(1'b1),
    .INTEG_TRST(1'b0),
    .INTEG_TDO(),

    .PGEN_CHAIN_I(1'b1),
    .PRDYN_CHAIN_O(),
    .EMA(3'b011),
    .EMAW(2'b01),
    .EMAS(1'b0),
    .RET1N(1'b1),
    .RET2N(1'b1),

    .ROM_HADDR(rom_haddr),
    .ROM_HRDATA(rom_hrdata),
    .ROM_HREADY(1'b1),
    .ROM_HRESP(1'b0),
    .ROM_HTRANS(rom_htrans),
    .ROM_HWRITE(rom_hwrite),

    .APB_PADDR(),
    .APB_PENABLE(),
    .APB_PRDATA(32'b0),
    .APB_PREADY(1'b1),
    .APB_PSEL(),
    .APB_PWDATA(),
    .APB_PWRITE(),
    .APB_PSLVERR(1'b0),
    .APB_PPROT(),
    .APB_PSTRB(),

    .EXTS_HRDATA({31'b0, cpu_started}),
    .EXTS_HREADYIN(1'b1),
    .EXTS_HRESP(1'b0),
    .EXTS_HADDR(exts_haddr),
    .EXTS_HBURST(exts_hburst),
    .EXTS_HPROT(exts_hprot),
    .EXTS_HSEL(exts_hsel),
    .EXTS_HSIZE(exts_hsize),
    .EXTS_HTRANS(exts_htrans),
    .EXTS_HWDATA(exts_hwdata),
    .EXTS_HWRITE(exts_hwrite),

    .EXTM_HADDR(32'b0),
    .EXTM_HBURST(3'b0),
    .EXTM_HPROT(4'b0),
    .EXTM_HRDATA(),
    .EXTM_HREADY(1'b1),
    .EXTM_HREADYOUT(),
    .EXTM_HRESP(),
    .EXTM_HSEL(1'b0),
    .EXTM_HSIZE(3'b0),
    .EXTM_HTRANS(2'b0),
    .EXTM_HWDATA(64'b0),
    .EXTM_HWRITE(1'b0),

    .DDR_HADDR(),
    .DDR_HBURST(),
    .DDR_HPROT(),
    .DDR_HRDATA(64'b0),
    .DDR_HREADY(1'b1),
    .DDR_HRESP(1'b0),
    .DDR_HSIZE(),
    .DDR_HTRANS(),
    .DDR_HWDATA(),
    .DDR_HWRITE(),

    .TMS_IN(1'b1),
    .TRST_IN(1'b1),
    .TDI_IN(1'b0),
    .TDO_OUT(),
    .TDO_OE(),

    .SPI2_HOLDN_IN(1'b0),
    .SPI2_WPN_IN(1'b0),
    .SPI2_CLK_IN(1'b0),
    .SPI2_CSN_IN(1'b0),
    .SPI2_MISO_IN(1'b0),
    .SPI2_MOSI_IN(1'b0),
    .SPI2_HOLDN_OUT(),
    .SPI2_HOLDN_OE(),
    .SPI2_WPN_OUT(),
    .SPI2_WPN_OE(),
    .SPI2_CLK_OUT(),
    .SPI2_CLK_OE(),
    .SPI2_CSN_OUT(),
    .SPI2_CSN_OE(),
    .SPI2_MISO_OUT(),
    .SPI2_MISO_OE(),
    .SPI2_MOSI_OUT(),
    .SPI2_MOSI_OE(),

    .I2C_SCL_IN(1'b0),
    .I2C_SDA_IN(1'b0),
    .I2C_SCL(),
    .I2C_SDA(),

    .UART1_TXD(),
    .UART1_RTSN(),
    .UART1_RXD(1'b0),
    .UART1_CTSN(1'b0),
    .UART1_DSRN(1'b0),
    .UART1_DCDN(1'b0),
    .UART1_RIN(1'b0),
    .UART1_DTRN(),
    .UART1_OUT1N(),
    .UART1_OUT2N(),
    .UART2_TXD(),
    .UART2_RTSN(),
    .UART2_RXD(1'b0),
    .UART2_CTSN(1'b1),
    .UART2_DCDN(1'b1),
    .UART2_DSRN(1'b1),
    .UART2_RIN(1'b1),
    .UART2_DTRN(),
    .UART2_OUT1N(),
    .UART2_OUT2N(),

    .CH0_PWM(),
    .CH0_PWMOE(),
    .CH1_PWM(),
    .CH1_PWMOE(),
    .CH2_PWM(),
    .CH2_PWMOE(),
    .CH3_PWM(),
    .CH3_PWMOE(),
    .GPIO_IN(32'b0),
    .GPIO_OE(),
    .GPIO_OUT()
);

endmodule
