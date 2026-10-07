// SPDX-License-Identifier: GPL-3.0-only
// Tang-native stereo XY phosphor: 512x512, eight-bit age-derived intensity.
// Nine-bit RAM words hold validity and a 240 Hz timestamp. A retirement
// sweep clears age >=128 before the 256-tick counter can wrap. Scanout caches
// three lines during the left bar. No renderer signal backpressures audio.
module scope_xy #(
    parameter integer AGE_TICK_CYCLES = 309375,
    parameter integer FIFO_ADDRESS_WIDTH = 8
) (
    input logic clk, resetn,
    input logic [3:0] control,
    input logic flush, audio_tick, audio_present,
    input logic signed [15:0] audio_left, audio_right,
    input logic [10:0] cx,
    input logic [9:0] cy,
    output logic enabled,
    output logic [23:0] rgb,
    output logic [31:0] dropped, status, sweeps
);
    logic [3:0] settings;
    // Frame start and flush are registered at the boundary, acting one pixel
    // clock later (cx==1, still in the left bar), so clear_all is not a long
    // path from the HDMI counters or the audio timebase.
    logic frame_start=0, flush_q=0;
    always_ff @(posedge clk) begin frame_start<=cx==0 && cy==0; flush_q<=flush; end
    wire mode_change = frame_start && settings!=control;
    assign enabled = settings[0];
    logic initializing;
    logic [14:0] clear_addr;
    // Registered clear: every request (disable, flush, mode change) arises
    // in the left bar or from a flush, so acting one clock later is unseen.
    // Reset reaches the scope's control only through clear_q, so the top
    // level resetn has no combinational path into the draw, retirement or
    // prefetch logic; every register that needs it at once still resets on
    // !resetn directly. usable is a register loaded with the value
    // enabled && !initializing && !clear_all takes on the next clock: a clear
    // in progress or requested implies !usable, and without one enabled does
    // not change.
    logic clear_q=1, usable=0;
    wire clear_next = !resetn || !enabled || flush_q || mode_change;
    always_ff @(posedge clk) clear_q<=clear_next;
    wire clear_all = clear_q;
    always_ff @(posedge clk)
        usable<=!clear_next && !clear_all && !(initializing && !(&clear_addr));
    logic was_present;
    wire break_trace = audio_tick && !audio_present && was_present;
    wire queue_reset = clear_all || initializing || break_trace;
    wire input_valid = usable && audio_tick && audio_present;
    always_ff @(posedge clk) begin
        if (!resetn) begin settings<=0; was_present<=0; end
        else begin
            if (frame_start) settings<=control;
            if (clear_all) was_present<=0;
            else if (audio_tick) was_present<=audio_present;
        end
    end

    wire point_valid;
    wire signed [15:0] point_l, point_r;
    scope_reconstruct reconstruction (
        .clk(clk), .reset(queue_reset), .sample_valid(input_valid),
        .left_in(audio_left), .right_in(audio_right),
        .point_valid(point_valid), .left_out(point_l), .right_out(point_r)
    );
    wire fifo_ready, fifo_valid;
    wire [32:0] fifo_data;
    wire [FIFO_ADDRESS_WIDTH:0] fifo_level;
    logic gap_pending;
    wire fifo_pop;
    pcm_sample_fifo #(.ADDRESS_WIDTH(FIFO_ADDRESS_WIDTH)) points (
        .clk(clk), .reset(!resetn), .clear(queue_reset),
        .input_data({gap_pending, point_l, point_r}),
        .input_valid(point_valid && usable), .input_ready(fifo_ready),
        .output_data(fifo_data), .output_valid(fifo_valid),
        .output_ready(fifo_pop), .level(fifo_level)
    );
    always_ff @(posedge clk) begin
        if (!resetn) begin dropped<=0; gap_pending<=0; end
        else if (queue_reset) gap_pending<=0;
        else if (point_valid && usable) begin
            if (!fifo_ready) begin dropped<=dropped+1'b1; gap_pending<=1; end
            else gap_pending<=0;
        end
    end

    logic [18:0] tick_count;
    logic [7:0] age_clock;
    always_ff @(posedge clk) begin
        if (!resetn) begin tick_count<=0; age_clock<=0; end
        else if (tick_count==19'(AGE_TICK_CYCLES-1)) begin
            tick_count<=0; age_clock<=age_clock+1'b1;
        end else tick_count<=tick_count+1'b1;
    end
    // Linear age ramp, later squared into brightness. Each setting remains
    // bounded by the 128-tick retirement threshold.
    function automatic [7:0] trail_ramp(input logic live,
                                         input logic [7:0] age,
                                         input logic [1:0] trail);
        begin
            trail_ramp=0;
            if (live) case(trail)
                0: if(age<32) trail_ramp=255-(age<<3);
                1: if(age<64) trail_ramp=255-(age<<2);
                2: if(age<128) trail_ramp=255-(age<<1);
                3: if(age<16) trail_ramp=255-(age<<4);
            endcase
        end
    endfunction
    function automatic [7:0] square_round(input logic [7:0] base);
        logic [15:0] energy;
        begin
            energy=16'(base)*16'(base)+16'd255;
            square_round=energy[15:8];
        end
    endfunction

    // Beam stepping is bounded to one pixel per granted update cycle.
    logic drawing, have_previous;
    logic [8:0] previous_x, previous_y, draw_x, draw_y, end_x, end_y;
    logic [8:0] dx, dy;
    logic step_x, step_y;
    logic signed [10:0] error;
    wire signed [11:0] twice_error = 12'(error) <<< 1;
    wire move_x=twice_error > -$signed({3'b0,dy});
    wire move_y=twice_error <  $signed({3'b0,dx});
    wire [8:0] next_x=fifo_data[31:23]^9'h100;
    wire [8:0] next_y=~(fifo_data[15:7]^9'h100);
    wire fresh_point=!have_previous || fifo_data[32];
    wire [8:0] distance_x=next_x>=previous_x ? next_x-previous_x : previous_x-next_x;
    wire [8:0] distance_y=next_y>=previous_y ? next_y-previous_y : previous_y-next_y;

    logic [3:0] schedule;
    logic [2:0] retire_state;
    logic [14:0] retire_addr;
    logic [7:0] expired;
    wire retire_begin=usable && retire_state==0 && schedule==0;
    wire line_slot=usable && retire_state==0 && !retire_begin;
    assign fifo_pop=line_slot && !drawing && fifo_valid;
    wire draw_fire;
    always_ff @(posedge clk) begin
        if (queue_reset) begin
            drawing<=0; have_previous<=0;
            previous_x<=0; previous_y<=0; draw_x<=0; draw_y<=0;
            end_x<=0; end_y<=0; dx<=0; dy<=0; error<=0; step_x<=0; step_y<=0;
        end else begin
            if (fifo_pop) begin
                draw_x<=fresh_point?next_x:previous_x;
                draw_y<=fresh_point?next_y:previous_y;
                end_x<=next_x; end_y<=next_y;
                dx<=fresh_point?9'd0:distance_x;
                dy<=fresh_point?9'd0:distance_y;
                error<=fresh_point?11'sd0:$signed({2'b0,distance_x})-$signed({2'b0,distance_y});
                step_x<=next_x>=previous_x; step_y<=next_y>=previous_y;
                previous_x<=next_x; previous_y<=next_y;
                have_previous<=1; drawing<=1;
            end
            if (draw_fire) begin
                if (draw_x==end_x && draw_y==end_y) drawing<=0;
                else begin
                    if(move_x) draw_x<=step_x?draw_x+1'b1:draw_x-1'b1;
                    if(move_y) draw_y<=step_y?draw_y+1'b1:draw_y-1'b1;
                    error<=error-(move_x?$signed({2'b0,dy}):11'sd0)
                                +(move_y?$signed({2'b0,dx}):11'sd0);
                end
            end
        end
    end

    // Scan-line prefetch: 3*64 wide groups fit before x=275. Source row
    // phase advances once per output line, implementing floor(y*32/45).
    logic [8:0] source_y;
    logic [5:0] phase_y;
    wire [6:0] next_phase_y={1'b0,phase_y}+7'd32;
    logic loading, cache_ready;
    logic [7:0] load_index;
    logic [14:0] b_addr;
    logic [8:0] fetch_above, fetch_below;
    wire b_read=loading && usable;
    logic b_read_d, b_read_dd, b_read_ddd;
    logic [1:0] cache_row_d, cache_row_dd;
    logic [5:0] cache_group_d, cache_group_dd;
    logic [1:0] cache_row;
    logic [5:0] cache_group;
    logic bright_valid;
    logic [1:0] bright_row;
    logic [5:0] bright_group;
    // The prefetch address is a register, one step ahead of load_index, so
    // the cross-port hazard compares two registers. The neighbouring rows
    // settle at cx==1, before the first prefetch read at cx==2.
    wire [7:0] next_index=load_index+1'b1;
    logic [8:0] next_fetch_y;
    always_comb
        case(next_index[7:6])
            0: next_fetch_y=fetch_above;
            2: next_fetch_y=fetch_below;
            default: next_fetch_y=source_y;
        endcase
    always_ff @(posedge clk) begin
        fetch_above<=source_y==0?9'd0:source_y-1'b1;
        fetch_below<=source_y==511?9'd511:source_y+1'b1;
    end
    always_ff @(posedge clk) begin
        if (!resetn || clear_all) begin
            source_y<=0; phase_y<=0; loading<=0; load_index<=0; b_addr<=0;
            b_read_d<=0; b_read_dd<=0; b_read_ddd<=0; cache_row<=0; cache_group<=0;
            cache_row_d<=0; cache_group_d<=0; cache_row_dd<=0; cache_group_dd<=0;
            cache_ready<=0;
        end else begin
            b_read_d<=b_read; b_read_dd<=b_read_d; b_read_ddd<=b_read_dd;
            if(b_read_d) begin cache_row_d<=cache_row; cache_group_d<=cache_group; end
            if(b_read_dd) begin cache_row_dd<=cache_row_d; cache_group_dd<=cache_group_d; end
            if (cx==0) begin
                cache_ready<=0;
                if (cy==0) begin source_y<=0; phase_y<=0; end
                else if(cy<720) begin
                    if(next_phase_y>=45) begin source_y<=source_y+1'b1; phase_y<=6'(next_phase_y-45); end
                    else phase_y<=next_phase_y[5:0];
                end
            end
            if (cx==1 && cy<720 && usable) begin
                loading<=1; load_index<=0;
                b_addr<={source_y==0?9'd0:source_y-1'b1,6'd0};
            end
            if (b_read) begin
                cache_row<=load_index[7:6]; cache_group<=load_index[5:0];
                if(load_index==191) loading<=0;
                else begin
                    load_index<=next_index;
                    b_addr<={next_fetch_y,next_index[5:0]};
                end
            end
            if(bright_valid && bright_row==2 && bright_group==63) cache_ready<=1;
        end
    end

    wire [8:0] a_q[0:7], b_q[0:7];
    logic [8:0] a_data[0:7];
    logic [14:0] a_addr;
    logic a_read;
    logic [7:0] a_we;
    // Cross-port collisions compare each port-A writer's own address with the
    // prefetch address, not the muxed a_addr, keeping the port-A mux off the
    // draw and retirement paths.
    wire draw_hazard=b_read && {draw_y,draw_x[8:4]}==b_addr[14:1];
    wire retire_hazard=b_read && retire_addr[14:1]==b_addr[14:1];
    assign draw_fire=line_slot && drawing && !draw_hazard;
    always_comb begin
        a_addr=retire_addr; a_read=0; a_we=0;
        for(integer g=0;g<8;g++) a_data[g]=0;
        if(initializing && enabled && !clear_all) begin
            a_addr=clear_addr; a_we=8'hff;
        end else if(usable) begin
            if(retire_begin) a_read=1;
            else if(retire_state==4) begin
                if(!retire_hazard) a_we=expired;
            end else if(line_slot && drawing) begin
                a_addr={draw_y,draw_x[8:3]};
                if(!draw_hazard) a_we[draw_x[2:0]]=1;
                for(integer g=0;g<8;g++) a_data[g]={1'b1,age_clock};
            end
        end
    end
    scope_phosphor_ram plane (
        .clk(clk), .a_addr(a_addr), .b_addr(b_addr), .a_read(a_read), .b_read(b_read),
        .a_we(a_we), .a_data(a_data), .a_q(a_q), .b_q(b_q)
    );
    always_ff @(posedge clk) begin
        if(!resetn) sweeps<=0;
        if(clear_all) begin
            initializing<=1; clear_addr<=0; schedule<=0;
            retire_state<=0; retire_addr<=0; expired<=0;
        end else if(initializing) begin
            if(&clear_addr) initializing<=0;
            else clear_addr<=clear_addr+1'b1;
        end else begin
            schedule<=schedule+1'b1;
            case(retire_state)
                0: if(retire_begin) retire_state<=1;
                1: retire_state<=2;
                2: retire_state<=3;
                3: begin
                    for(integer g=0;g<8;g++)
                        expired[g]<=a_q[g][8] && 8'(age_clock-a_q[g][7:0])>=128;
                    retire_state<=4;
                end
                4: if(!retire_hazard) begin
                    retire_state<=0; retire_addr<=retire_addr+1'b1;
                    if(&retire_addr) sweeps<=sweeps+1'b1;
                end
                default: retire_state<=0;
            endcase
        end
    end

    // Brightness is three registered stages after the plane read: age, trail
    // ramp, then square and round. Age is taken as the plane data arrives.
    // Row/group tags travel with the data; the last write publishes the cache.
    logic age_valid, ramp_valid;
    logic [1:0] age_row, ramp_row;
    logic [5:0] age_group, ramp_group;
    logic [7:0] age_live;
    logic [7:0] age_q[0:7], ramp_q[0:7], bright_q[0:7];
    always_ff @(posedge clk) begin
        if (!resetn || clear_all) begin
            age_valid<=0; ramp_valid<=0; bright_valid<=0;
        end else begin
            age_valid<=b_read_ddd; ramp_valid<=age_valid; bright_valid<=ramp_valid;
        end
        age_row<=cache_row_dd; age_group<=cache_group_dd;
        ramp_row<=age_row; ramp_group<=age_group;
        bright_row<=ramp_row; bright_group<=ramp_group;
        for(integer g=0;g<8;g++) begin
            age_live[g]<=b_q[g][8];
            age_q[g]<=age_clock-b_q[g][7:0];
            ramp_q[g]<=trail_ramp(age_live[g],age_q[g],settings[2:1]);
            bright_q[g]<=square_round(ramp_q[g]);
        end
    end

    // request_pixel is computed one clock ahead from cx 274..993, so no HDMI
    // counter logic sits in front of the cache lane reads; cy cannot change
    // between cx==274 and cx==995. source_x is cleared on every cycle outside
    // the view, so it is already zero at cx==275 and is itself read_x.
    logic [8:0] source_x;
    logic [5:0] phase_x;
    wire [6:0] next_phase_x={1'b0,phase_x}+7'd32;
    logic request_pixel=0;
    always_ff @(posedge clk) request_pixel<=cx>=274 && cx<994 && cy<720;
    wire [8:0] read_x=source_x;
    always_ff @(posedge clk) begin
        if(!resetn || !request_pixel) begin source_x<=0; phase_x<=0; end
        else if(next_phase_x>=45) begin source_x<=read_x+1'b1; phase_x<=6'(next_phase_x-45); end
        else begin source_x<=read_x; phase_x<=next_phase_x[5:0]; end
    end

    // One 64x8 memory per cache row and interleaved lane, each with a fixed
    // writer and an asynchronous read followed by a register, keeping the
    // wide phosphor RAM out of the pixel palette path. No simultaneous
    // write/read occurs in the view: publication finishes during the left bar.
    wire [7:0] lane_q[0:23];
    for (genvar r=0;r<3;r++) begin : cache_row_mem
        for (genvar g=0;g<8;g++) begin : lane
            logic [7:0] mem[0:63];
            always_ff @(posedge clk)
                if(bright_valid && bright_row==2'(r)) mem[bright_group]<=bright_q[g];
            assign lane_q[r*8+g]=mem[read_x[8:3]];
        end
    end
    logic [7:0] above_q, core_q, below_q;
    logic [7:0] core_delay, core_previous, core_center;
    logic [7:0] vertical_q, vertical_previous, vertical_older, halo_q;
    logic [3:0] visible_pipe;
    logic [8:0] green_sum;
    always_comb green_sum={1'b0,core_center}+{1'b0,settings[3]?halo_q>>2:8'd0};
    always_ff @(posedge clk) begin
        visible_pipe<={visible_pipe[2:0],request_pixel && usable && cache_ready};
        above_q<=lane_q[{2'd0,read_x[2:0]}];
        core_q <=lane_q[{2'd1,read_x[2:0]}];
        below_q<=lane_q[{2'd2,read_x[2:0]}];
        if(!request_pixel) begin above_q<=0; core_q<=0; below_q<=0; end
        vertical_q<=8'(({2'b0,above_q}+({2'b0,core_q}<<1)+{2'b0,below_q})>>2);
        vertical_previous<=vertical_q; vertical_older<=vertical_previous;
        halo_q<=8'(({2'b0,vertical_older}+({2'b0,vertical_previous}<<1)+{2'b0,vertical_q})>>2);
        core_delay<=core_q; core_previous<=core_delay; core_center<=core_previous;
        rgb<=visible_pipe[3]?{core_center>>3,green_sum[8]?8'hff:green_sum[7:0],core_center>>4}:24'd0;
        if(!resetn || !usable) begin
            visible_pipe<=0; rgb<=0; above_q<=0; core_q<=0; below_q<=0;
            vertical_q<=0; vertical_previous<=0; vertical_older<=0; halo_q<=0;
            core_delay<=0; core_previous<=0; core_center<=0;
        end
    end
    always_comb begin
        status=0;
        status[0]=enabled; status[1]=!initializing; status[2]=drawing;
        status[3]=loading; status[4]=cache_ready;
        status[16:8]=9'(fifo_level); status[23:20]=settings;
        status[31:24]=age_clock;
    end
endmodule
