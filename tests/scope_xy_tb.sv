`timescale 1ns/1ps
module scope_xy_tb;
    logic clk=0; always #1 clk=~clk;
    logic resetn=0;
    logic [3:0] control=0;
    logic flush=0, audio_tick=0, present=0;
    logic signed [15:0] l=0,r=0;
    logic [10:0] cx=0;
    logic [9:0] cy=0;
    always @(negedge clk) begin
        if(!resetn) begin cx=0; cy=0; end
        else if(cx==1649) begin cx=0; cy=cy==749?10'd0:cy+1'b1; end
        else cx=cx+1'b1;
    end
    wire enabled;
    wire [23:0] rgb;
    wire [31:0] drops,status,sweeps;
    scope_xy dut (
        .clk(clk),.resetn(resetn),.control(control),.flush(flush),
        .audio_tick(audio_tick),.audio_present(present),.audio_left(l),.audio_right(r),
        .cx(cx),.cy(cy),.enabled(enabled),.rgb(rgb),
        .dropped(drops),.status(status),.sweeps(sweeps)
    );
    // Monitor the vendor's physical address-region rule independently of
    // the renderer's own write-hazard decision, on every RAM transaction.
    always @(posedge clk) if(resetn) begin
        if(dut.b_read && |dut.a_we && dut.a_addr[14:1]==dut.b_addr[14:1])
            $fatal(1,"Gowin cross-port read/write collision");
        if(dut.a_read && |dut.a_we) $fatal(1,"read-before-write requested");
    end
    task automatic sample(input integer il,ir);
        @(posedge clk); #0.2; audio_tick=1; present=1; l=16'(il); r=16'(ir);
        @(posedge clk); #0.2; audio_tick=0;
        repeat(1544) @(posedge clk);
    endtask
    logic seed=0,check_raster=0;
    logic gap_pop_d=0, watch_wrap=0;
    logic [7:0] previous_age=0;
    integer overflow_breaks=0, age_wraps=0;
    always @(posedge clk) begin
        gap_pop_d<=dut.fifo_pop && dut.fifo_data[32];
        if(watch_wrap && dut.age_clock<previous_age) age_wraps++;
        previous_age<=dut.age_clock;
    end
    always @(negedge clk) if(gap_pop_d) begin
        if(dut.draw_x!=dut.end_x || dut.draw_y!=dut.end_y)
            $fatal(1,"visual loss produced a catch-up line");
        overflow_breaks++;
    end
    integer seeded=0;
    function automatic bit ink(input integer x,y);
        return x==y || x+y==511 || y==80 || x==400 || (x<64 && y<64 && ((x/8+y/8)%2)==0);
    endfunction
    for(genvar g=0;g<8;g++) begin : seed_bank
        initial begin
            wait(seed);
            for(integer a=0;a<32768;a++) dut.plane.bank[g].mem[a]={ink((a%64)*8+g,a/64),8'd0};
            seeded++;
        end
    end
    function automatic integer core(input integer px,py);
        if(px<0 || px>=720) return 0;
        return ink(px*32/45,py*32/45)?255:0;
    endfunction
    function automatic integer vertical(input integer px,py);
        integer x,y,above,below;
        if(px<0 || px>=720) return 0;
        x=px*32/45; y=py*32/45;
        above=ink(x,y==0?0:y-1)?255:0;
        below=ink(x,y==511?511:y+1)?255:0;
        return (above+2*core(px,py)+below)/4;
    endfunction
    integer pixels=0;
    integer drops_before_withdrawal;
    integer ppm;
    logic [23:0] expected_rgb;
    always @(posedge clk) if(check_raster && cx<1280 && cy<720) begin
        integer c,h,gr;
        expected_rgb=0;
        if(cx>=280 && cx<1000) begin
            c=core(integer'(cx)-280,integer'(cy));
            h=(vertical(integer'(cx)-281,integer'(cy))+2*vertical(integer'(cx)-280,integer'(cy))+vertical(integer'(cx)-279,integer'(cy)))/4;
            gr=c+h/4; if(gr>255) gr=255;
            expected_rgb={8'(c>>3),8'(gr),8'(c>>4)};
        end
        if(rgb!==expected_rgb) $fatal(1,"raster mismatch (%0d,%0d): got %h expected %h",cx,cy,rgb,expected_rgb);
        pixels++;
        $fwrite(ppm,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
    end
    initial begin
        repeat(3) @(posedge clk); #0.2; resetn=1; control=4'hb;
        wait(enabled && !dut.initializing);
        // Repeated coherent constants settle the FIR to a single point. All
        // reconstructed points still traverse FIFO and line machinery.
        for(integer i=0;i<24;i++) sample(16384,-16384);
        wait(!dut.drawing && dut.fifo_level==0);
        if(drops!=0) $fatal(1,"ordinary points dropped");
        if(dut.previous_x!=384 || dut.previous_y!=383) $fatal(1,"channel/sign mapping");
        // Full-scale jumps stress beam stepping and retirement arbitration.
        for(integer i=0;i<512;i++) sample(i[0]?32767:-32768,i[0]?-32768:32767);
        wait(!dut.drawing && dut.fifo_level==0);
        if(drops!=0 || sweeps==0) $fatal(1,"worst-case scheduling did not keep up");
        // Force a producer faster than the maximum line workload, checking
        // explicit loss accounting and a discontinuity on the retained tail.
        for(integer i=0;i<600;i++) begin
            @(posedge clk); #0.2; audio_tick=1; present=1;
            l=i[0]?32767:-32768; r=i[0]?-32768:32767;
            @(posedge clk); #0.2; audio_tick=0;
            repeat(14) @(posedge clk);
        end
        if(drops==0) $fatal(1,"overload did not account for visual loss");
        drops_before_withdrawal=integer'(drops);
        wait(!dut.drawing && dut.fifo_level==0);
        if(overflow_breaks==0) $fatal(1,"overflow discontinuity untested");
        // Synthetic silence breaks the visual stream but leaves the canvas
        // aging. No queued points or connecting line may survive it.
        @(posedge clk); #0.2; audio_tick=1; present=0;
        @(posedge clk); #0.2; audio_tick=0;
        repeat(30) @(posedge clk);
        if(dut.have_previous || dut.fifo_level!=0) $fatal(1,"pause did not break continuity");
        // Seed a fixed known plane and freeze its age for a complete, exact
        // raster comparison. This isolates video scaling/filter alignment
        // from audio geometry and the already exercised retirement scheduler.
        force dut.age_clock=0;
        seed=1; wait(seeded==8);
        wait(cx==1649 && cy==749);
        @(negedge clk);
        ppm=$fopen("build/oscope-session/scope-raster.ppm","wb");
        $fwrite(ppm,"P6\n1280 720\n255\n");
        check_raster=1;
        wait(cx==1649 && cy==719);
        @(negedge clk); check_raster=0; $fclose(ppm);
        if(pixels!=921600) $fatal(1,"full raster coverage: %0d",pixels);
        release dut.age_clock;
        @(posedge clk); #0.2; previous_age=dut.age_clock; watch_wrap=1;
        // Old pixels must disappear and stay gone across the timestamp wrap.
        repeat(81) begin
            wait(cx==0 && cy==0); wait(cx==1649 && cy==749); @(posedge clk);
        end
        if(age_wraps==0) $fatal(1,"timestamp wrap not exercised");
        if(dut.plane.bank[0].mem[0][8]) $fatal(1,"expired timestamp resurrected");
        control=0;
        wait(!enabled);
        repeat(8) @(posedge clk);
        if(rgb!=0 || integer'(drops)!=drops_before_withdrawal) $fatal(1,"withdrawal or drop count");
        $display("PASS scope XY: stereo mapping, worst-case queue, retirement, RAM hazards, pause, complete glow raster and timestamp wrap");
        $finish;
    end
    initial begin #300000000; $fatal(1,"scope timeout"); end
endmodule
