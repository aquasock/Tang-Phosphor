// SPDX-License-Identifier: GPL-3.0-only
//
// Randomized check of ae350_ram_bridge against a byte-level reference memory.
// A pipelined AHB-Lite master issues WRAP4/INCR4/INCR8/undefined-length
// bursts with BUSY and IDLE cycles, narrow single transfers, and addresses
// outside DDR3; a Gowin native-port model stalls cmd_ready and wr_data_rdy at
// random and returns reads in order after a random latency.  Addresses are
// confined to a few lines so reads constantly follow writes to the same line.
`timescale 1ns/1ps

module ae350_ram_bridge_tb;

    localparam int LINES = 8;
    localparam int SLOTS = 60000;
    localparam logic [31:0] BASE = 32'h4123_4000;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = !clk;

    logic [31:0]  haddr;
    logic [1:0]   htrans;
    logic         hwrite;
    logic [2:0]   hsize;
    logic [2:0]   hburst;
    logic [63:0]  hwdata;
    logic [63:0]  hrdata;
    logic         hready;
    logic         hresp;

    logic         cmd_ready;
    logic [2:0]   cmd;
    logic         cmd_en;
    logic [28:0]  addr;
    logic         wr_data_rdy;
    logic [255:0] wr_data;
    logic         wr_data_en;
    logic         wr_data_end;
    logic [31:0]  wr_data_mask;
    logic [255:0] rd_data;
    logic         rd_data_valid;

    logic [31:0] reads, writes, latency_sum, latency_max, buffer_hits, errors;
    logic [31:0] trace_addr [16];
    logic [15:0] trace_info [16];
    logic [7:0]  trace_status;
    logic [31:0] first_error_addr, bridge_state;

    ae350_ram_bridge dut (
        .clk(clk), .rst(rst),
        .haddr(haddr), .htrans(htrans), .hwrite(hwrite), .hsize(hsize),
        .hburst(hburst), .hwdata(hwdata), .hrdata(hrdata), .hready(hready),
        .hresp(hresp),
        .ctrl_cmd_ready(cmd_ready), .ctrl_cmd(cmd), .ctrl_cmd_en(cmd_en),
        .ctrl_addr(addr), .ctrl_wr_data_rdy(wr_data_rdy),
        .ctrl_wr_data(wr_data), .ctrl_wr_data_en(wr_data_en),
        .ctrl_wr_data_end(wr_data_end), .ctrl_wr_data_mask(wr_data_mask),
        .ctrl_rd_data(rd_data), .ctrl_rd_data_valid(rd_data_valid),
        .reads(reads), .writes(writes), .latency_sum(latency_sum),
        .latency_max(latency_max), .buffer_hits(buffer_hits), .errors(errors),
        .trace_addr(trace_addr), .trace_info(trace_info), .trace_status(trace_status),
        .first_error_addr(first_error_addr), .state(bridge_state)
    );

    int failures = 0;

    function automatic logic [7:0] initial_byte(input logic [31:0] a);
        return 8'(a * 32'h9e37_79b9 >> 13);
    endfunction

    // ------------------------------------------------------------------
    // Native-port model: memory indexed by 256-bit word.
    // ------------------------------------------------------------------
    logic [255:0] ddr [logic [24:0]];
    logic [255:0] rq_data [$];
    int           rq_due  [$];
    int           cycle = 0;

    function automatic logic [255:0] ddr_word(input logic [24:0] index);
        logic [255:0] w;
        if (ddr.exists(index))
            return ddr[index];
        for (int b = 0; b < 32; b++)
            w[8 * b +: 8] = initial_byte({2'b01, index, 5'(b)});
        return w;
    endfunction

    always_ff @(posedge clk) begin
        cycle <= cycle + 1;
        cmd_ready   <= ($urandom % 100) < 75;
        wr_data_rdy <= ($urandom % 100) < 80;
        rd_data_valid <= 1'b0;
        if (!rst && cmd_en) begin
            logic [255:0] w;
            if (!cmd_ready || addr[2:0] != 0 || addr[28])
                begin $display("FAIL: command without ready or bad address %h", addr); failures++; end
            w = ddr_word(addr[27:3]);
            if (cmd == 3'b000) begin
                if (!wr_data_rdy || !wr_data_en || !wr_data_end)
                    begin $display("FAIL: write without data handshake"); failures++; end
                for (int b = 0; b < 32; b++)
                    if (!wr_data_mask[b])
                        w[8 * b +: 8] = wr_data[8 * b +: 8];
                ddr[addr[27:3]] = w;
            end else if (cmd == 3'b001) begin
                if (wr_data_en)
                    begin $display("FAIL: wr_data_en on a read"); failures++; end
                rq_data.push_back(w);
                rq_due.push_back(cycle + 4 + int'($urandom % 40));
            end else begin
                $display("FAIL: unknown command %0d", cmd); failures++;
            end
        end else if (!rst && wr_data_en) begin
            $display("FAIL: wr_data_en without cmd_en"); failures++;
        end
        if (rq_due.size() != 0 && rq_due[0] <= cycle) begin
            rd_data_valid <= 1'b1;
            rd_data <= rq_data.pop_front();
            void'(rq_due.pop_front());
        end
    end

    // ------------------------------------------------------------------
    // Reference memory and AHB master.
    // ------------------------------------------------------------------
    logic [7:0] ref_mem [logic [31:0]];

    function automatic logic [7:0] ref_byte(input logic [31:0] a);
        return ref_mem.exists(a) ? ref_mem[a] : initial_byte(a);
    endfunction

    typedef struct {
        logic [1:0]  trans;
        logic [31:0] addr;
        logic        write;
        logic [2:0]  size;
        logic [2:0]  burst;
        logic [63:0] wdata;
    } slot_t;

    slot_t slots [$];

    function automatic logic [31:0] line_address();
        return BASE + 32'(($urandom % LINES) * 32);
    endfunction

    function automatic slot_t make(input logic [1:0] trans, input logic [31:0] a,
                                   input logic write, input logic [2:0] size,
                                   input logic [2:0] burst);
        slot_t s;
        s.trans = trans;
        s.addr  = a;
        s.write = write;
        s.size  = size;
        s.burst = burst;
        s.wdata = {$urandom, $urandom};
        return s;
    endfunction

    task automatic maybe_busy(input slot_t next);
        if (($urandom % 8) == 0) begin
            slot_t b = next;
            b.trans = 2'b01;
            slots.push_back(b);
        end
    endtask

    task automatic gen_burst(input logic write, input logic [2:0] burst, input int beats,
                             input logic [31:0] start, input bit wrap);
        logic [31:0] a;
        for (int i = 0; i < beats; i++) begin
            if (wrap)
                a = {start[31:5], 5'(start[4:0] + 8 * i)};
            else
                a = start + 32'(8 * i);
            if (i != 0)
                maybe_busy(make(2'b11, a, write, 3'd3, burst));
            slots.push_back(make(i == 0 ? 2'b10 : 2'b11, a, write, 3'd3, burst));
        end
    endtask

    task automatic generate_slots();
        while (slots.size() < SLOTS) begin
            int kind = $urandom % 12;
            logic [31:0] line = line_address();
            logic write = 1'($urandom % 2);
            unique case (kind)
                0, 1: gen_burst(1'b0, 3'b010, 4, line + 32'(8 * ($urandom % 4)), 1);  // WRAP4 read (line fill)
                2, 3: gen_burst(1'b1, 3'b011, 4, line, 0);                           // INCR4 write (eviction)
                4:    gen_burst(1'b1, 3'b010, 4, line + 32'(8 * ($urandom % 4)), 1);  // WRAP4 write
                5:    gen_burst(write, 3'b001, 1 + $urandom % 10,
                                line + 32'(8 * ($urandom % 4)), 0);                  // INCR, may cross lines
                6:    gen_burst(write, 3'b101, 8, line, 0);                          // INCR8 over two lines
                7, 8: begin                                                          // narrow single
                    logic [2:0] size = 3'($urandom % 4);
                    logic [31:0] a = line + 32'($urandom % 32);
                    a = a & ~((32'd1 << size) - 1);
                    slots.push_back(make(2'b10, a, write, size, 3'b000));
                end
                9: begin                                                             // outside DDR3
                    logic [31:0] a = ($urandom % 2) ? 32'h0000_1000 : 32'h8000_0040;
                    slots.push_back(make(2'b10, a, write, 3'd2, 3'b000));
                end
                default: repeat (1 + $urandom % 3)
                    slots.push_back(make(2'b00, 32'h0, 1'b0, 3'd0, 3'b000));
            endcase
        end
        repeat (4)
            slots.push_back(make(2'b00, 32'h0, 1'b0, 3'd0, 3'b000));
    endtask

    slot_t a_slot;      // in its address phase
    slot_t d_slot;      // in its data phase
    logic  d_valid = 1'b0;
    int    next_slot = 0;
    int    completed = 0;
    int    error_count = 0;
    logic  done = 1'b0;

    function automatic bit outside(input logic [31:0] a);
        return a[31:30] != 2'b01;
    endfunction

    always_ff @(posedge clk) begin
        if (!rst && !done && hready) begin
            if (d_valid) begin
                if (outside(d_slot.addr)) begin
                    if (!hresp) begin $display("FAIL: no ERROR for %h", d_slot.addr); failures++; end
                    error_count++;
                end else begin
                    if (hresp) begin $display("FAIL: ERROR for %h", d_slot.addr); failures++; end
                    for (int b = 0; b < 8; b++) begin
                        logic [31:0] a;
                        a = {d_slot.addr[31:3], 3'(b)};
                        if (b >= d_slot.addr[2:0] && b < d_slot.addr[2:0] + (1 << d_slot.size)) begin
                            if (d_slot.write)
                                ref_mem[a] = hwdata[8 * b +: 8];
                            else if (hrdata[8 * b +: 8] !== ref_byte(a)) begin
                                if (failures < 20)
                                    $display("FAIL: read %h byte %0d got %h expected %h at cycle %0d",
                                             d_slot.addr, b, hrdata[8 * b +: 8], ref_byte(a), cycle);
                                failures++;
                            end
                        end
                    end
                end
                completed++;
            end
            d_valid <= a_slot.trans[1];
            d_slot  <= a_slot;
            hwdata  <= a_slot.wdata;
            if (next_slot < slots.size()) begin
                a_slot <= slots[next_slot];
                next_slot <= next_slot + 1;
            end else begin
                done <= 1'b1;
            end
        end
    end

    assign haddr  = a_slot.addr;
    assign htrans = done ? 2'b00 : a_slot.trans;
    assign hwrite = a_slot.write;
    assign hsize  = a_slot.size;
    assign hburst = a_slot.burst;

    initial begin
        a_slot = make(2'b00, 32'h0, 1'b0, 3'd0, 3'b000);
        generate_slots();
        repeat (4) @(posedge clk);
        rst <= 1'b0;
        wait (done);
        repeat (8) @(posedge clk);
        $display("ae350_ram_bridge_tb: %0d transfers, %0d errors, %0d native reads, %0d writes, %0d buffer hits, latency max %0d",
                 completed, error_count, reads, writes, buffer_hits, latency_max);
        if (error_count != 0 && (first_error_addr[31:30] == 2'b01 || !trace_status[7])) begin
            $display("FAIL: trace did not record the first error (%h, status %h)",
                     first_error_addr, trace_status);
            failures++;
        end
        if (errors != error_count) begin
            $display("FAIL: bridge counted %0d errors, master saw %0d", errors, error_count);
            failures++;
        end
        if (failures == 0 && completed > SLOTS / 2)
            $display("PASS");
        else
            $fatal(1, "ae350_ram_bridge_tb: %0d failures", failures);
        $finish;
    end

    initial begin
        #50ms;
        $display("hang: hready %b hresp %b d_valid %b rd_pend %b rd_wait %b wbuf_valid %b wbuf_open %b wr_wait %b a_slot %h/%b",
                 hready, hresp, dut.c_valid, dut.rd_pend, dut.rd_wait, dut.wbuf_valid, dut.wbuf_open, dut.wr_wait,
                 a_slot.addr, a_slot.trans);
        $fatal(1, "ae350_ram_bridge_tb: timeout (%0d of %0d slots)", next_slot, slots.size());
    end

endmodule
