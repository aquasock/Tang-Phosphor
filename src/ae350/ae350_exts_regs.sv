// SPDX-License-Identifier: GPL-3.0-only
//
// AE350 fabric registers on the CPU-master extended AHB port (EXTS), which
// the A25 sees uncached at 0xe8000000.  Offsets are shared with the
// Tang-Control debug view (dbg_*), which reads every register here.  Only
// word accesses are supported, except that the log ring also takes byte
// and halfword writes; the window aliases every 1 KiB.
//
//   0x000 R   magic "TPA3" (0x54504133)
//   0x004 R   register ABI version
//   0x008 R   flags: bit 0 stream loader overflow (sticky)
//   0x00c R   100 MHz time, low word; a CPU read latches the high word
//   0x010 R   100 MHz time, high word latched by the low-word read
//   0x020 RW  loader state: bits 7:0 state, bits 31:16 completed runs
//   0x024 RW  payload bytes of the last image
//   0x028 RW  CRC-32 of the last image payload
//   0x02c RW  return value of the last program
//   0x030 RW  log head: bytes written to the log ring
//   0x040 RW  16 program result words (0x040-0x07c)
//   0x080 R   stream entry status: bit 0 valid, bits 2:1 tag
//   0x084 R   stream entry word
//   0x088 W   discard the stream entry
//   0x0a0 R   RAM bridge: native reads, writes, read-latency sum and
//             maximum (100 MHz cycles), line-buffer hits, ERROR responses
//             (0x0a0-0x0b4)
//   0x100 W   log ring, 128 words (0x100-0x2fc); read by the debug view only
//
// Debug view only (RAM-bridge diagnostics, see ae350_ram_bridge.sv):
//   0x0b8     bridge state flags
//   0x0bc     trace status {frozen, next entry}
//   0x0c0     address of the first ERROR response
//   0x300     trace addresses, 16 words (0x300-0x33c)
//   0x340     trace transfer attributes, 16 words (0x340-0x37c)
//
// The AHB port inserts one wait state per write and two per read, so every
// path from the AE350 macro ends at a register and the read multiplexer is
// split over two cycles.

module ae350_exts_regs (
    input  logic        clk,
    input  logic        rst,

    input  logic [31:0] haddr,
    input  logic        hsel,
    input  logic [1:0]  htrans,
    input  logic        hwrite,
    input  logic [2:0]  hsize,
    input  logic [31:0] hwdata,
    output logic [31:0] hrdata,
    output logic        hready,

    input  logic        entry_valid,
    input  logic [1:0]  entry_tag,
    input  logic [31:0] entry_data,
    output logic        entry_pop,
    input  logic        stream_overflow,

    input  logic [31:0] bridge_reads,
    input  logic [31:0] bridge_writes,
    input  logic [31:0] bridge_latency_sum,
    input  logic [31:0] bridge_latency_max,
    input  logic [31:0] bridge_buffer_hits,
    input  logic [31:0] bridge_errors,
    input  logic [31:0] bridge_trace_addr [16],
    input  logic [15:0] bridge_trace_info [16],
    input  logic [7:0]  bridge_trace_status,
    input  logic [31:0] bridge_first_error,
    input  logic [31:0] bridge_state,

    // Debug view: word address in, data two cycles later.
    input  logic [7:0]  dbg_addr,
    output logic [31:0] dbg_rdata
);

    localparam logic [31:0] MAGIC = 32'h5450_4133;
    localparam logic [31:0] ABI   = 32'h0001_0000;

    logic [31:0] state, image_bytes, image_crc, result, log_head;
    (* syn_ramstyle = "registers" *) logic [31:0] user [16];
    logic [63:0] now;
    logic [31:0] time_high;

    // One RAM per byte lane, so the log takes byte writes.
    (* syn_ramstyle = "block_ram" *) logic [7:0] log_lane0 [0:127];
    (* syn_ramstyle = "block_ram" *) logic [7:0] log_lane1 [0:127];
    (* syn_ramstyle = "block_ram" *) logic [7:0] log_lane2 [0:127];
    (* syn_ramstyle = "block_ram" *) logic [7:0] log_lane3 [0:127];

    logic       pending;
    logic       reading;
    logic       a_write;
    logic [7:0] a_addr /* synthesis syn_maxfan = 16 */;
    logic [3:0] a_lanes;

    // Read decode for everything but the log ring, in two stages: the 16
    // program result words and the other registers are selected
    // separately, then combined.
    function automatic logic [31:0] read_misc(input logic [7:0] address);
        unique case (address)
            8'h00:   return MAGIC;
            8'h01:   return ABI;
            8'h02:   return {31'b0, stream_overflow};
            8'h03:   return now[31:0];
            8'h04:   return time_high;
            8'h08:   return state;
            8'h09:   return image_bytes;
            8'h0a:   return image_crc;
            8'h0b:   return result;
            8'h0c:   return log_head;
            8'h20:   return {29'b0, entry_tag, entry_valid};
            8'h21:   return entry_data;
            8'h28:   return bridge_reads;
            8'h29:   return bridge_writes;
            8'h2a:   return bridge_latency_sum;
            8'h2b:   return bridge_latency_max;
            8'h2c:   return bridge_buffer_hits;
            8'h2d:   return bridge_errors;
            default: return 32'h0;
        endcase
    endfunction

    logic [31:0] read_user_word;
    logic [31:0] read_misc_word;
    logic        read_is_user;

    always_ff @(posedge clk) begin
        now       <= now + 64'd1;
        entry_pop <= 1'b0;

        if (hready && hsel && htrans[1]) begin
            pending <= 1'b1;
            hready  <= 1'b0;
            a_write <= hwrite;
            a_addr  <= haddr[9:2];
            a_lanes <= hsize == 3'd0 ? 4'b0001 << haddr[1:0] :
                       hsize == 3'd1 ? (haddr[1] ? 4'b1100 : 4'b0011) : 4'b1111;
        end

        if (pending) begin
            pending <= 1'b0;
            if (a_write) begin
                hready <= 1'b1;
                unique casez (a_addr)
                    8'h08: state       <= hwdata;
                    8'h09: image_bytes <= hwdata;
                    8'h0a: image_crc   <= hwdata;
                    8'h0b: result      <= hwdata;
                    8'h0c: log_head    <= hwdata;
                    8'b0001????: user[a_addr[3:0]] <= hwdata;
                    8'h22: entry_pop   <= 1'b1;
                    default: ;
                endcase
            end else begin
                reading        <= 1'b1;
                read_user_word <= user[a_addr[3:0]];
                read_misc_word <= read_misc(a_addr);
                read_is_user   <= a_addr[7:4] == 4'h1;
                if (a_addr == 8'h03)
                    time_high <= now[63:32];
            end
        end

        if (reading) begin
            reading <= 1'b0;
            hready  <= 1'b1;
            hrdata  <= read_is_user ? read_user_word : read_misc_word;
        end

        if (rst) begin
            hready      <= 1'b1;
            pending     <= 1'b0;
            reading     <= 1'b0;
            entry_pop   <= 1'b0;
            now         <= '0;
            time_high   <= '0;
            state       <= '0;
            image_bytes <= '0;
            image_crc   <= '0;
            result      <= '0;
            log_head    <= '0;
            for (int i = 0; i < 16; i++)
                user[i] <= '0;
        end
    end

    wire log_write = pending && a_write && (a_addr[7:6] == 2'b01 || a_addr[7:6] == 2'b10);

    wire [6:0] log_index = 7'(a_addr - 8'h40);

    always_ff @(posedge clk) begin
        if (log_write && a_lanes[0]) log_lane0[log_index] <= hwdata[7:0];
        if (log_write && a_lanes[1]) log_lane1[log_index] <= hwdata[15:8];
        if (log_write && a_lanes[2]) log_lane2[log_index] <= hwdata[23:16];
        if (log_write && a_lanes[3]) log_lane3[log_index] <= hwdata[31:24];
    end

    // Debug view: two register stages, the first of which is the log
    // ring's read port.
    logic [31:0] dbg_log;
    logic [31:0] dbg_user;
    logic [31:0] dbg_misc;
    logic [31:0] dbg_diag;
    logic [1:0]  dbg_select;
    logic        dbg_is_diag;

    always_ff @(posedge clk) begin
        dbg_log    <= {log_lane3[7'(dbg_addr - 8'h40)], log_lane2[7'(dbg_addr - 8'h40)],
                       log_lane1[7'(dbg_addr - 8'h40)], log_lane0[7'(dbg_addr - 8'h40)]};
        dbg_user   <= user[dbg_addr[3:0]];
        dbg_misc   <= read_misc(dbg_addr);
        dbg_is_diag <= dbg_addr[7:5] == 3'b110 || dbg_addr == 8'h2e ||
                       dbg_addr == 8'h2f || dbg_addr == 8'h30;
        dbg_diag   <= dbg_addr == 8'h2e ? bridge_state :
                      dbg_addr == 8'h2f ? {24'b0, bridge_trace_status} :
                      dbg_addr == 8'h30 ? bridge_first_error :
                      dbg_addr[4] ? {16'b0, bridge_trace_info[dbg_addr[3:0]]} :
                                    bridge_trace_addr[dbg_addr[3:0]];
        dbg_select <= dbg_addr[7:6] == 2'b01 || dbg_addr[7:6] == 2'b10 ? 2'd2 :
                      dbg_addr[7:4] == 4'h1 ? 2'd1 : 2'd0;
        dbg_rdata  <= dbg_is_diag ? dbg_diag :
                      dbg_select == 2'd2 ? dbg_log :
                      dbg_select == 2'd1 ? dbg_user : dbg_misc;
    end

endmodule
