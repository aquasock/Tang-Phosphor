// SPDX-License-Identifier: GPL-3.0-only
//
// Tang-Phosphor AE350 + DDR3 subsystem, shared by the standalone AE350 image
// (ae350_ddr3_top, transport at 50 MHz) and the merged player image
// (tang_phosphor_top, transport at 74.25 MHz).  Everything here is moved
// unchanged from the former ae350_ddr3_top body except the transport-facing
// clock: the stream and debug interfaces are synchronous to tclk, which may
// be the 50 MHz board clock (standalone) or the 74.25 MHz pixel clock
// (merged).  The AE350/DDR3 logic itself keeps its own clock domains:
//
//   clk        50 MHz board oscillator: power-on reset, both PLLs'
//              reference, and the diagnostic status counters.
//   tclk       transport domain: the stream ingress and the Tang-Control
//              debug view (stream counters, flags, register readback).
//   ui_clk     100 MHz user clock of the Gowin DDR3 controller; it also
//              clocks every AE350 bus.  Held in reset until calibration.
//   core_clk   750 MHz A25 core clock from PLL_R[0] CLKOUT1.
//
// The DDR3 controller, its 400 MHz PLL, and the x32 pin mapping follow
// Sipeed's TangMega-138K-example ddr_memory design (Apache-2.0, commit
// 06e7d8b), as proven on this board by Tang-PSX; scripts/gen-ddr3-ip.sh
// regenerates the Gowin IP locally.
//
// Tang-Control debug view (reads of 0x000-0x3bc return the AE350 register
// block, see ae350_exts_regs.sv; the view aliases every 1 KiB and the
// merged top gates it into one 1 KiB window):
//   0x3c0 R  stream sessions, 0x3c4 bytes, 0x3c8 ends, 0x3cc cancels,
//            0x3d0 overflow
//   0x3e0 R  flags: bit 0 power-on reset done, 1 AE350 PLL locked, 2 DDR3
//            PLL locked, 3 DDR3 calibrated, 4 AE350 running
//   0x3e4 R  50 MHz cycles from power-on reset to calibration
//   0x3e8 R  50 MHz uptime
//   0x3f0 W  bit 0: restart the AE350 (R: restarts requested)

module ae350_subsystem (
    input  logic        clk,
    input  logic        tclk,

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
    inout  wire  [3:0]  ddr_dqs_n,

    // Tang-Control stream (tclk domain).
    input  logic        stream_start,
    input  logic        stream_end,
    input  logic        stream_cancel,
    input  logic [7:0]  stream_data,
    input  logic        stream_valid,
    output logic        stream_ready,

    // Tang-Control debug (tclk domain).
    input  logic        debug_valid,
    input  logic        debug_write,
    input  logic [31:0] debug_address,
    input  logic [31:0] debug_wdata,
    output logic [31:0] debug_rdata
);

    // ------------------------------------------------------------------
    // Board-clock power-on reset (about 1.3 ms).
    // ------------------------------------------------------------------
    logic [15:0] por_count = '1;
    logic        por_n = 1'b0;

    always_ff @(posedge clk) begin
        if (por_count != 0)
            por_count <= por_count - 16'd1;
        por_n <= por_count == 0;
    end

    // ------------------------------------------------------------------
    // DDR3: 50 MHz -> 800 MHz VCO -> 400 MHz memory clock.  PLL_INIT runs
    // Gowin's charge-pump and loop-filter search on the dynamically
    // configured PLL, as in the vendor reference.
    // ------------------------------------------------------------------
    logic       memory_clk;
    logic       ddr_pll_lock;
    logic       ddr_pll_stop;
    logic       ddr_pll_raw_lock;
    logic       ddr_pll_rst;
    logic [5:0] ddr_pll_icpsel;
    logic [2:0] ddr_pll_lpfres;

    Gowin_PLL_MOD u_ddr_pll (
        .clkin   (clk),
        .reset   (ddr_pll_rst),
        .icpsel  (ddr_pll_icpsel),
        .lpfres  (ddr_pll_lpfres),
        .lpfcap  (2'b00),
        .enclk0  (1'b1),
        .enclk1  (1'b1),
        .enclk2  (ddr_pll_stop),
        .clkout0 (),
        .clkout1 (),
        .clkout2 (memory_clk),
        .lock    (ddr_pll_raw_lock)
    );

    PLL_INIT #(
        .CLK_PERIOD (20),
        .MULTI_FAC  (16)
    ) u_ddr_pll_init (
        .CLKIN   (clk),
        .I_RST   (!por_n),
        .O_RST   (ddr_pll_rst),
        .PLLLOCK (ddr_pll_raw_lock),
        .O_LOCK  (ddr_pll_lock),
        .ICPSEL  (ddr_pll_icpsel),
        .LPFRES  (ddr_pll_lpfres)
    );

    logic         ui_clk;
    logic         ddr_rst;
    logic         calib_done;
    logic         cmd_ready;
    logic [2:0]   cmd;
    logic         cmd_en;
    logic [28:0]  cmd_addr;
    logic         wr_data_rdy;
    logic [255:0] wr_data;
    logic         wr_data_en;
    logic         wr_data_end;
    logic [31:0]  wr_data_mask;
    logic [255:0] rd_data;
    logic         rd_data_valid;

    DDR3_Memory_Interface_Top u_ddr3 (
        .clk                 (clk),
        .memory_clk          (memory_clk),
        .pll_lock            (ddr_pll_lock),
        .pll_stop            (ddr_pll_stop),
        .rst_n               (por_n),
        .clk_out             (ui_clk),
        .ddr_rst             (ddr_rst),
        .init_calib_complete (calib_done),
        .cmd_ready           (cmd_ready),
        .cmd                 (cmd),
        .cmd_en              (cmd_en),
        .addr                (cmd_addr),
        .wr_data_rdy         (wr_data_rdy),
        .wr_data             (wr_data),
        .wr_data_en          (wr_data_en),
        .wr_data_end         (wr_data_end),
        .wr_data_mask        (wr_data_mask),
        .rd_data             (rd_data),
        .rd_data_valid       (rd_data_valid),
        .rd_data_end         (),
        .sr_req              (1'b0),
        .ref_req             (1'b0),
        .sr_ack              (),
        .ref_ack             (),
        .burst               (1'b0),
        .O_ddr_addr          (ddr_addr),
        .O_ddr_ba            (ddr_bank),
        .O_ddr_cs_n          (ddr_cs),
        .O_ddr_ras_n         (ddr_ras),
        .O_ddr_cas_n         (ddr_cas),
        .O_ddr_we_n          (ddr_we),
        .O_ddr_clk           (ddr_ck),
        .O_ddr_clk_n         (ddr_ck_n),
        .O_ddr_cke           (ddr_cke),
        .O_ddr_odt           (ddr_odt),
        .O_ddr_reset_n       (ddr_reset_n),
        .O_ddr_dqm           (ddr_dm),
        .IO_ddr_dq           (ddr_dq),
        .IO_ddr_dqs          (ddr_dqs),
        .IO_ddr_dqs_n        (ddr_dqs_n)
    );

    // ui_clk reset: asserted while the controller is in reset or not yet
    // calibrated, released synchronously.
    logic [1:0] ui_rst_sync /* synthesis syn_srlstyle = "registers" */ = 2'b11;
    wire        ui_rst = ui_rst_sync[1];

    always_ff @(posedge ui_clk or posedge ddr_rst) begin
        if (ddr_rst)
            ui_rst_sync <= 2'b11;
        else
            ui_rst_sync <= {ui_rst_sync[0], !calib_done};
    end

    // ------------------------------------------------------------------
    // AE350 core clock and reset.
    // ------------------------------------------------------------------
    logic core_clk;
    logic ae350_pll_lock;

    ae350_pll cpu_pll (
        .lock    (ae350_pll_lock),
        .cpu_clk (core_clk),
        .bus_clk (),
        .clkin   (clk)
    );

    // Host restart request, written through the debug view in the transport
    // domain and synchronized into the AE350 bus domain.
    logic [15:0] restart_count;
    logic [31:0] restarts;
    wire         restart = restart_count != 0;

    logic [1:0] ae350_lock_ui /* synthesis syn_srlstyle = "registers" */;
    logic [1:0] restart_ui    /* synthesis syn_srlstyle = "registers" */;
    logic [7:0] cpu_reset_count = 8'hff;
    logic       cpu_resetn = 1'b0;

    always_ff @(posedge ui_clk) begin
        ae350_lock_ui <= {ae350_lock_ui[0], ae350_pll_lock};
        restart_ui    <= {restart_ui[0], restart};
        if (ui_rst || !ae350_lock_ui[1] || restart_ui[1]) begin
            cpu_reset_count <= 8'hff;
            cpu_resetn      <= 1'b0;
        end else if (cpu_reset_count != 0) begin
            cpu_reset_count <= cpu_reset_count - 8'd1;
        end else begin
            cpu_resetn <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // AE350 and its fabric ports.
    // ------------------------------------------------------------------
    logic [31:0] rom_haddr, rom_hrdata;
    logic [1:0]  rom_htrans;
    logic        rom_hready;

    logic [31:0] exts_haddr, exts_hwdata, exts_hrdata;
    logic        exts_hsel, exts_hwrite, exts_hready;
    logic [1:0]  exts_htrans;
    logic [2:0]  exts_hsize;

    logic [31:0] ram_haddr;
    logic [1:0]  ram_htrans;
    logic        ram_hwrite, ram_hready, ram_hresp;
    logic [2:0]  ram_hsize, ram_hburst;
    logic [63:0] ram_hwdata, ram_hrdata;

    ae350_soc soc (
        .bus_clk     (ui_clk),
        .core_clk    (core_clk),
        .resetn      (cpu_resetn),
        .rom_haddr   (rom_haddr),
        .rom_htrans  (rom_htrans),
        .rom_hrdata  (rom_hrdata),
        .rom_hready  (rom_hready),
        .exts_haddr  (exts_haddr),
        .exts_hsel   (exts_hsel),
        .exts_htrans (exts_htrans),
        .exts_hwrite (exts_hwrite),
        .exts_hsize  (exts_hsize),
        .exts_hwdata (exts_hwdata),
        .exts_hrdata (exts_hrdata),
        .exts_hready (exts_hready),
        .ram_haddr   (ram_haddr),
        .ram_htrans  (ram_htrans),
        .ram_hwrite  (ram_hwrite),
        .ram_hsize   (ram_hsize),
        .ram_hburst  (ram_hburst),
        .ram_hwdata  (ram_hwdata),
        .ram_hrdata  (ram_hrdata),
        .ram_hready  (ram_hready),
        .ram_hresp   (ram_hresp)
    );

    ae350_boot_rom boot_rom (
        .clk    (ui_clk),
        .rst    (!cpu_resetn),
        .haddr  (rom_haddr),
        .htrans (rom_htrans),
        .hrdata (rom_hrdata),
        .hready (rom_hready)
    );

    logic [31:0] bridge_reads, bridge_writes, bridge_latency_sum;
    logic [31:0] bridge_latency_max, bridge_buffer_hits, bridge_errors;
    logic [31:0] bridge_trace_addr [16];
    logic [15:0] bridge_trace_info [16];
    logic [7:0]  bridge_trace_status;
    logic [31:0] bridge_first_error, bridge_state;

    // The bridge and the register block restart with the CPU, so their
    // counters and the log cover one boot.
    ae350_ram_bridge ram_bridge (
        .clk                (ui_clk),
        .rst                (!cpu_resetn),
        .haddr              (ram_haddr),
        .htrans             (ram_htrans),
        .hwrite             (ram_hwrite),
        .hsize              (ram_hsize),
        .hburst             (ram_hburst),
        .hwdata             (ram_hwdata),
        .hrdata             (ram_hrdata),
        .hready             (ram_hready),
        .hresp              (ram_hresp),
        .ctrl_cmd_ready     (cmd_ready),
        .ctrl_cmd           (cmd),
        .ctrl_cmd_en        (cmd_en),
        .ctrl_addr          (cmd_addr),
        .ctrl_wr_data_rdy   (wr_data_rdy),
        .ctrl_wr_data       (wr_data),
        .ctrl_wr_data_en    (wr_data_en),
        .ctrl_wr_data_end   (wr_data_end),
        .ctrl_wr_data_mask  (wr_data_mask),
        .ctrl_rd_data       (rd_data),
        .ctrl_rd_data_valid (rd_data_valid),
        .reads              (bridge_reads),
        .writes             (bridge_writes),
        .latency_sum        (bridge_latency_sum),
        .latency_max        (bridge_latency_max),
        .buffer_hits        (bridge_buffer_hits),
        .errors             (bridge_errors),
        .trace_addr         (bridge_trace_addr),
        .trace_info         (bridge_trace_info),
        .trace_status       (bridge_trace_status),
        .first_error_addr   (bridge_first_error),
        .state              (bridge_state)
    );

    // ------------------------------------------------------------------
    // Program loading through the Tang-Control stream (tclk ingress).
    // ------------------------------------------------------------------
    logic [31:0] stream_sessions, stream_bytes, stream_ends, stream_cancels;
    logic        stream_overflow;
    logic        entry_valid, entry_pop;
    logic [1:0]  entry_tag;
    logic [31:0] entry_data;

    // por_sync_tclk is the synchronized power-on reset for the loader's
    // stream side (same domain as its sclk).  Declared before the loader
    // instantiation and driven by an assign so Gowin does not drop it as an
    // implicit-declaration redeclaration.
    wire por_sync_tclk;

    ae350_stream_loader loader (
        .sclk        (tclk),
        .srst        (!por_sync_tclk),
        .start       (stream_start),
        .stop        (stream_end),
        .cancel      (stream_cancel),
        .data        (stream_data),
        .valid       (stream_valid),
        .ready       (stream_ready),
        .sessions    (stream_sessions),
        .bytes       (stream_bytes),
        .ends        (stream_ends),
        .cancels     (stream_cancels),
        .overflow    (stream_overflow),
        .cclk        (ui_clk),
        .entry_valid (entry_valid),
        .entry_tag   (entry_tag),
        .entry_data  (entry_data),
        .entry_pop   (entry_pop)
    );

    logic [1:0] stream_overflow_ui /* synthesis syn_srlstyle = "registers" */;
    always_ff @(posedge ui_clk)
        stream_overflow_ui <= {stream_overflow_ui[0], stream_overflow};

    logic [7:0]  regs_dbg_addr;
    logic [31:0] regs_dbg_rdata;

    ae350_exts_regs regs (
        .clk                (ui_clk),
        .rst                (!cpu_resetn),
        .haddr              (exts_haddr),
        .hsel               (exts_hsel),
        .htrans             (exts_htrans),
        .hwrite             (exts_hwrite),
        .hsize              (exts_hsize),
        .hwdata             (exts_hwdata),
        .hrdata             (exts_hrdata),
        .hready             (exts_hready),
        .entry_valid        (entry_valid),
        .entry_tag          (entry_tag),
        .entry_data         (entry_data),
        .entry_pop          (entry_pop),
        .stream_overflow    (stream_overflow_ui[1]),
        .bridge_reads       (bridge_reads),
        .bridge_writes      (bridge_writes),
        .bridge_latency_sum (bridge_latency_sum),
        .bridge_latency_max (bridge_latency_max),
        .bridge_buffer_hits (bridge_buffer_hits),
        .bridge_errors      (bridge_errors),
        .bridge_trace_addr  (bridge_trace_addr),
        .bridge_trace_info  (bridge_trace_info),
        .bridge_trace_status(bridge_trace_status),
        .bridge_first_error (bridge_first_error),
        .bridge_state       (bridge_state),
        .dbg_addr           (regs_dbg_addr),
        .dbg_rdata          (regs_dbg_rdata)
    );

    // ------------------------------------------------------------------
    // Transport-domain status and debug view.
    //
    // The register readback crosses ui_clk -> tclk through debug_read_cdc.
    // The single-bit status flags cross into tclk with two-stage
    // synchronizers; the diagnostic counters stay in the 50 MHz clk domain
    // so their rate is identical in the standalone and merged images, and
    // are synchronized for display only (a read may tear by one count).
    // ------------------------------------------------------------------
    logic [31:0] regs_rdata;

    debug_read_cdc #(
        .ADDR_BITS      (8),
        .TARGET_LATENCY (2)
    ) regs_read (
        .dclk   (tclk),
        .daddr  (debug_address[9:2]),
        .drdata (regs_rdata),
        .tclk   (ui_clk),
        .taddr  (regs_dbg_addr),
        .trdata (regs_dbg_rdata)
    );

    logic [1:0]  ae350_lock_sync /* synthesis syn_srlstyle = "registers" */;
    logic [1:0]  ddr_lock_sync   /* synthesis syn_srlstyle = "registers" */;
    logic [1:0]  calib_sync      /* synthesis syn_srlstyle = "registers" */;
    logic [1:0]  running_sync    /* synthesis syn_srlstyle = "registers" */;
    logic [1:0]  por_sync        /* synthesis syn_srlstyle = "registers" */;
    logic [1:0]  calib_done_clk  /* synthesis syn_srlstyle = "registers" */;
    logic [31:0] calib_time;
    logic [31:0] calib_time_meta;
    logic [31:0] calib_time_sync;
    logic [31:0] uptime;
    logic [31:0] uptime_meta;
    logic [31:0] uptime_sync;

    always_ff @(posedge clk) begin
        calib_done_clk <= {calib_done_clk[0], calib_done};
        uptime         <= uptime + 32'd1;
        if (!calib_done_clk[1])
            calib_time <= calib_time + 32'd1;

        if (!por_n) begin
            uptime     <= '0;
            calib_time <= '0;
        end
    end

    always_ff @(posedge tclk) begin
        ae350_lock_sync <= {ae350_lock_sync[0], ae350_pll_lock};
        ddr_lock_sync   <= {ddr_lock_sync[0], ddr_pll_lock};
        calib_sync      <= {calib_sync[0], calib_done};
        running_sync    <= {running_sync[0], cpu_resetn};
        por_sync        <= {por_sync[0], por_n};
        calib_time_meta <= calib_time;
        calib_time_sync <= calib_time_meta;
        uptime_meta     <= uptime;
        uptime_sync     <= uptime_meta;

        if (restart_count != 0)
            restart_count <= restart_count - 16'd1;
        if (debug_valid && debug_write && debug_address[9:0] == 10'h3f0 && debug_wdata[0]) begin
            restart_count <= '1;
            restarts      <= restarts + 32'd1;
        end

        if (!por_sync[1]) begin
            restart_count <= '0;
            restarts      <= '0;
        end
    end

    // por_sync_tclk is the synchronized power-on reset for the loader's
    // stream side (same domain as its sclk).
    assign por_sync_tclk = por_sync[1];

    wire [31:0] flags = {27'b0, running_sync[1], calib_sync[1], ddr_lock_sync[1],
                         ae350_lock_sync[1], por_sync[1]};

    always_comb begin
        unique case (debug_address[9:2])
            8'hf0:   debug_rdata = stream_sessions;
            8'hf1:   debug_rdata = stream_bytes;
            8'hf2:   debug_rdata = stream_ends;
            8'hf3:   debug_rdata = stream_cancels;
            8'hf4:   debug_rdata = {31'b0, stream_overflow};
            8'hf8:   debug_rdata = flags;
            8'hf9:   debug_rdata = calib_time_sync;
            8'hfa:   debug_rdata = uptime_sync;
            8'hfc:   debug_rdata = restarts;
            default: debug_rdata = regs_rdata;
        endcase
    end

endmodule
