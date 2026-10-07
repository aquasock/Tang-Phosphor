`timescale 1ns/1ps
module scope_reconstruct_tb;
    logic clk=0; always #5 clk=~clk;
    logic reset=1, valid=0;
    logic signed [15:0] l,r;
    wire ov; wire signed [15:0] ol,orr;
    scope_reconstruct dut(clk,reset,valid,l,r,ov,ol,orr);
    longint signed history_l[0:7],history_r[0:7];
    integer signed expected_l[$],expected_r[$];
    integer checked=0;
    function automatic integer sat(input longint signed v);
        longint signed rounded;
        rounded=(v+(v<0?16383:16384))>>>15;
        if(rounded>32767) return 32767;
        if(rounded< -32768) return -32768;
        return integer'(rounded);
    endfunction
    // Model the symmetric convolution mathematically, outside the RTL's
    // time-multiplexed datapath and state machine.
    always @(posedge clk) begin
        if(reset) begin
            expected_l.delete(); expected_r.delete();
            for(integer i=0;i<8;i++) begin history_l[i]=0; history_r[i]=0; end
        end else if(valid) begin
            for(integer i=7;i>0;i--) begin history_l[i]=history_l[i-1]; history_r[i]=history_r[i-1]; end
            history_l[0]=l; history_r[0]=r;
            expected_l.push_back(sat(-240*(history_l[0]+history_l[7])+1064*(history_l[1]+history_l[6])-4500*(history_l[2]+history_l[5])+20060*(history_l[3]+history_l[4])));
            expected_r.push_back(sat(-240*(history_r[0]+history_r[7])+1064*(history_r[1]+history_r[6])-4500*(history_r[2]+history_r[5])+20060*(history_r[3]+history_r[4])));
            expected_l.push_back(integer'(history_l[3])); expected_r.push_back(integer'(history_r[3]));
        end
    end
    always @(negedge clk) if(ov) begin
        integer el,er;
        if(expected_l.size()==0) $fatal(1,"unexpected reconstructed point");
        el=expected_l.pop_front(); er=expected_r.pop_front();
        if(integer'(ol)!=el || integer'(orr)!=er) $fatal(1,"reconstruction mismatch %0d %0d versus %0d %0d",ol,orr,el,er);
        checked++;
    end
    initial begin
        repeat(3) @(negedge clk); reset=0;
        for(integer i=0;i<260;i++) begin
            @(negedge clk); valid=1;
            case(i%5)
                0: begin l=32767; r=-32768; end
                1: begin l=-32768; r=32767; end
                2: begin l=0; r=0; end
                3: begin l=16384; r=-16384; end
                4: begin l=16'($random); r=16'($random); end
            endcase
            @(negedge clk); valid=0;
            repeat(16) @(negedge clk);
        end
        if(checked!=520 || expected_l.size()!=0) $fatal(1,"point count");
        reset=1; repeat(3) @(negedge clk);
        if(ov) $fatal(1,"reset leaked point");
        $display("PASS scope reconstruction: full-scale, signs, zeros, random stereo, rounding, saturation and reset");
        $finish;
    end
endmodule
