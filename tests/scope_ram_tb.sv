`timescale 1ns/1ps
module scope_ram_tb;
    logic clk=0; always #5 clk=~clk;
`ifndef SCOPE_RAM_BEHAVIORAL
    GSR GSR(1'b1);
`endif
    logic [14:0] aa=0,ba=0;
    logic ar=0,br=0;
    logic [7:0] we=0;
    logic [8:0] data[0:7];
    wire [8:0] aq[0:7],bq[0:7];
    scope_phosphor_ram dut(clk,aa,ba,ar,br,we,data,aq,bq);
    function automatic [8:0] value(input integer addr, lane);
        // The block index term keeps blocks distinct: addr*37 alone aliases
        // every 2048-word block to the same 9-bit pattern.
        return 9'((addr*37)^(lane*73)^((addr>>11)*29)^9'h101);
    endfunction
    initial begin
        repeat(5) @(negedge clk);
        // Exercise all blocks, first/last word, parity bit and lane identity.
        for(integer blockn=0;blockn<16;blockn++) begin
            for(integer offset=0;offset<4;offset++) begin
                aa=15'(blockn*2048+(offset==3?2047:offset));we=8'hff;
                for(integer lane=0;lane<8;lane++) data[lane]=value(integer'(aa),lane);
                @(negedge clk);we=0;
            end
        end
        for(integer blockn=0;blockn<16;blockn++) begin
            aa=15'(blockn*2048+2047);ba=15'(((blockn+7)%16)*2048+1);
            ar=1;br=1;
            @(negedge clk);ar=0;br=0;
            @(negedge clk);
            // Data must not be visible before the third edge.
            for(integer lane=0;lane<8;lane++)
                if(aq[lane]===value(integer'(aa),lane) && bq[lane]===value(integer'(ba),lane) && blockn>0)
                    $fatal(1,"RAM latency too short block %0d lane %0d",blockn,lane);
            @(negedge clk);
            for(integer lane=0;lane<8;lane++) begin
                if(aq[lane]!==value(integer'(aa),lane) || bq[lane]!==value(integer'(ba),lane))
                    $fatal(1,"RAM mapping/latency mismatch block %0d lane %0d: %h %h",blockn,lane,aq[lane],bq[lane]);
            end
        end
        $display("PASS scope RAM: all 128 blocks, 9-bit lane data, both ports and three-cycle latency");
        $finish;
    end
endmodule
