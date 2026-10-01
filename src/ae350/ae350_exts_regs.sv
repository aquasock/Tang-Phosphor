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
//   0x090 W   play stream: four bytes, least significant first
//   0x094 W   play stream control: bit 0 start, bit 1 end, bit 2 cancel
//         R   bit 0: the play stream has room for another entry
//   0x098 W   play stream: one byte (bits 7:0)
//             Writes to 0x090-0x098 wait while the play stream is full.
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
// The AHB port inserts two wait states per write and three per read, so
// every path from the AE350 macro ends at a register: a write captures HWDATA
// and a registered decode of its target, then commits a cycle later, and the
// read multiplexer is split over two cycles after a local copy of the
// address.  The address-phase
// attributes are captured on every cycle that HREADY is high, enabled only by
// the local HREADY register, so the macro's outputs reach their capture
// registers without decode logic; only pending and HREADY depend on HSEL and
// HTRANS, through the accept term.  The merged image's constraints keep that
// handshake, the captured attributes, and the program result words beside the
// AE350 macro, so their names (hready, pending, accept, a_*, user) are part
// of the floorplan.

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

    // Play stream to the player (through an async FIFO): {kind, count, data},
    // kind 0 data (count + 1 bytes), 1 start, 2 end, 3 cancel.
    output logic        play_valid,
    output logic [1:0]  play_kind,
    output logic [1:0]  play_count,
    output logic [31:0] play_data,
    input  logic        play_ready,

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

    // Debug view: word address in, data three cycles later.
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
    logic       decoding;
    logic [7:0] read_addr;

    // Write commit stage: the data word and a one-hot target decoded from
    // the captured address.
    logic        committing;
    logic [31:0] w_data;
    logic        w_state, w_image_bytes, w_image_crc, w_result, w_log_head, w_pop;
    logic        w_play_ctrl, w_play_byte, w_play;
    logic [15:0] w_user;
    logic       a_write;
    logic [7:0] a_addr /* synthesis syn_maxfan = 16 */;
    logic [3:0] a_lanes;

    // Read decode for everything but the log ring, in two stages: the 16
    // program result words, the core registers (0x00-0x0c), and the stream
    // and bridge registers (0x20-0x2d) are selected separately, then
    // combined.
    function automatic logic [31:0] read_core(input logic [7:0] address);
        unique case (address[3:0])
            4'h0:    return address[7:4] == 4'h0 ? MAGIC : 32'h0;
            4'h1:    return address[7:4] == 4'h0 ? ABI : 32'h0;
            4'h2:    return address[7:4] == 4'h0 ? {31'b0, stream_overflow} : 32'h0;
            4'h3:    return address[7:4] == 4'h0 ? now[31:0] : 32'h0;
            4'h4:    return address[7:4] == 4'h0 ? time_high : 32'h0;
            4'h8:    return address[7:4] == 4'h0 ? state : 32'h0;
            4'h9:    return address[7:4] == 4'h0 ? image_bytes : 32'h0;
            4'ha:    return address[7:4] == 4'h0 ? image_crc : 32'h0;
            4'hb:    return address[7:4] == 4'h0 ? result : 32'h0;
            4'hc:    return address[7:4] == 4'h0 ? log_head : 32'h0;
            default: return 32'h0;
        endcase
    endfunction

    function automatic logic [31:0] read_link(input logic [7:0] address);
        unique case (address[3:0])
            4'h0:    return address[7:4] == 4'h2 ? {29'b0, entry_tag, entry_valid} : 32'h0;
            4'h1:    return address[7:4] == 4'h2 ? entry_data : 32'h0;
            4'h8:    return address[7:4] == 4'h2 ? bridge_reads : 32'h0;
            4'h9:    return address[7:4] == 4'h2 ? bridge_writes : 32'h0;
            4'ha:    return address[7:4] == 4'h2 ? bridge_latency_sum : 32'h0;
            4'hb:    return address[7:4] == 4'h2 ? bridge_latency_max : 32'h0;
            4'hc:    return address[7:4] == 4'h2 ? bridge_buffer_hits : 32'h0;
            4'hd:    return address[7:4] == 4'h2 ? bridge_errors : 32'h0;
            4'h5:    return address[7:4] == 4'h2 ? {31'b0, play_ready} : 32'h0;
            default: return 32'h0;
        endcase
    endfunction

    // Kept as a named net so the floorplan can place its LUT with the
    // handshake registers.  Declared, then driven by an assign, as Gowin
    // requires (see tang_phosphor_top.sv).
    wire accept /* synthesis syn_keep = 1 */;
    assign accept = hready && hsel && htrans[1];

    logic [31:0] read_user_word;
    logic [31:0] read_core_word;
    logic [31:0] read_link_word;
    logic [1:0]  read_select;

    always_ff @(posedge clk) begin
        now        <= now + 64'd1;
        entry_pop  <= 1'b0;
        play_valid <= 1'b0;

        // The attributes are only used while pending, and HREADY stays low
        // from acceptance until completion, so capturing them on every
        // HREADY cycle holds exactly the accepted transfer's values.
        if (hready) begin
            a_write <= hwrite;
            a_addr  <= haddr[9:2];
            a_lanes <= hsize == 3'd0 ? 4'b0001 << haddr[1:0] :
                       hsize == 3'd1 ? (haddr[1] ? 4'b1100 : 4'b0011) : 4'b1111;
        end

        if (accept) begin
            pending <= 1'b1;
            hready  <= 1'b0;
        end

        if (pending) begin
            pending <= 1'b0;
            if (a_write) begin
                committing    <= 1'b1;
                w_data        <= hwdata;
                w_state       <= a_addr == 8'h08;
                w_image_bytes <= a_addr == 8'h09;
                w_image_crc   <= a_addr == 8'h0a;
                w_result      <= a_addr == 8'h0b;
                w_log_head    <= a_addr == 8'h0c;
                w_pop         <= a_addr == 8'h22;
                w_play_ctrl   <= a_addr == 8'h25;
                w_play_byte   <= a_addr == 8'h26;
                w_play        <= a_addr == 8'h24 || a_addr == 8'h25 || a_addr == 8'h26;
                for (int i = 0; i < 16; i++)
                    w_user[i] <= a_addr == 8'h10 + 8'(i);
            end else begin
                decoding  <= 1'b1;
                read_addr <= a_addr;
                if (a_addr == 8'h03)
                    time_high <= now[63:32];
            end
        end

        // Ordinary register writes commit at once; their strobes are never
        // set for a play-stream write, so they need no play term.  A
        // play-stream write holds the bus until the FIFO has room; one entry
        // is pushed per write, at most every few cycles, so the registered
        // ready already counts the previous push.
        if (committing) begin
            if (w_state)       state       <= w_data;
            if (w_image_bytes) image_bytes <= w_data;
            if (w_image_crc)   image_crc   <= w_data;
            if (w_result)      result      <= w_data;
            if (w_log_head)    log_head    <= w_data;
            if (w_pop)         entry_pop   <= 1'b1;
            for (int i = 0; i < 16; i++)
                if (w_user[i]) user[i] <= w_data;
            if (!w_play || play_ready) begin
                committing <= 1'b0;
                hready     <= 1'b1;
                if (w_play) begin
                    play_valid <= 1'b1;
                    play_data  <= w_data;
                    play_count <= w_play_byte ? 2'd0 : 2'd3;
                    play_kind  <= w_play_ctrl ? (w_data[2] ? 2'd3 : w_data[1] ? 2'd2 : 2'd1) : 2'd0;
                end
            end
        end

        if (decoding) begin
            decoding       <= 1'b0;
            reading        <= 1'b1;
            read_user_word <= user[read_addr[3:0]];
            read_core_word <= read_core(read_addr);
            read_link_word <= read_link(read_addr);
            read_select    <= read_addr[7:4] == 4'h1 ? 2'd1 :
                              read_addr[7:4] == 4'h2 ? 2'd2 : 2'd0;
        end

        if (reading) begin
            reading <= 1'b0;
            hready  <= 1'b1;
            hrdata  <= read_select == 2'd1 ? read_user_word :
                       read_select == 2'd2 ? read_link_word : read_core_word;
        end

        if (rst) begin
            hready      <= 1'b1;
            pending     <= 1'b0;
            committing  <= 1'b0;
            play_valid  <= 1'b0;
            decoding    <= 1'b0;
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

    // Debug view: a local copy of the address, then two register stages, the
    // first of which is the log ring's read port.
    logic [7:0] dbg_word /* synthesis syn_maxfan = 16 */;
    always_ff @(posedge clk)
        dbg_word <= dbg_addr;

    logic [31:0] dbg_log;
    logic [31:0] dbg_user;
    logic [31:0] dbg_core;
    logic [31:0] dbg_link;
    logic [31:0] dbg_diag;
    logic [1:0]  dbg_select;
    logic        dbg_is_diag;

    always_ff @(posedge clk) begin
        dbg_log    <= {log_lane3[7'(dbg_word - 8'h40)], log_lane2[7'(dbg_word - 8'h40)],
                       log_lane1[7'(dbg_word - 8'h40)], log_lane0[7'(dbg_word - 8'h40)]};
        dbg_user   <= user[dbg_word[3:0]];
        dbg_core   <= read_core(dbg_word);
        dbg_link   <= read_link(dbg_word);
        dbg_is_diag <= dbg_word[7:5] == 3'b110 || dbg_word == 8'h2e ||
                       dbg_word == 8'h2f || dbg_word == 8'h30;
        dbg_diag   <= dbg_word == 8'h2e ? bridge_state :
                      dbg_word == 8'h2f ? {24'b0, bridge_trace_status} :
                      dbg_word == 8'h30 ? bridge_first_error :
                      dbg_word[4] ? {16'b0, bridge_trace_info[dbg_word[3:0]]} :
                                    bridge_trace_addr[dbg_word[3:0]];
        dbg_select <= dbg_word[7:6] == 2'b01 || dbg_word[7:6] == 2'b10 ? 2'd3 :
                      dbg_word[7:4] == 4'h1 ? 2'd1 :
                      dbg_word[7:4] == 4'h2 ? 2'd2 : 2'd0;
        dbg_rdata  <= dbg_is_diag ? dbg_diag :
                      dbg_select == 2'd3 ? dbg_log :
                      dbg_select == 2'd2 ? dbg_link :
                      dbg_select == 2'd1 ? dbg_user : dbg_core;
    end

endmodule
