// Implementation of HDMI audio clock regeneration packet
// By Sameer Puri https://github.com/sameer

// See HDMI 1.4b Section 5.3.3
module audio_clock_regeneration_packet (
    input logic clk_pixel,
    input logic clk_audio,
    input logic audio_rate_48k,
    input logic reset,
    output logic clk_audio_counter_wrap,
    output logic [23:0] header,
    output logic [55:0] sub [3:0]
);

// See Section 7.2.3. These are the values produced by the original table-based
// algorithm for Tang-Phosphor's bounded native rates. One CTS measurement spans
// N / 128 audio samples: 49 at 44.1 kHz and 48 at 48 kHz.
localparam logic [19:0] N_44K1 = 20'd6272;
localparam logic [19:0] N_48K = 20'd6144;
logic [5:0] clk_audio_counter;
logic internal_clk_audio_counter_wrap;
logic active_rate_48k;
wire [5:0] clk_audio_counter_end = active_rate_48k ? 6'd47 : 6'd48;
wire [19:0] n_value = active_rate_48k ? N_48K : N_44K1;

logic clk_audio_old;
// always_ff @(posedge clk_audio)
always_ff @(posedge clk_pixel)
begin
    if (reset) begin
        clk_audio_old <= 1'b0;
        clk_audio_counter <= 6'd0;
        internal_clk_audio_counter_wrap <= 1'b0;
        active_rate_48k <= 1'b1;
    end else if (audio_rate_48k != active_rate_48k) begin
        clk_audio_old <= clk_audio;
        clk_audio_counter <= 6'd0;
        active_rate_48k <= audio_rate_48k;
    end else begin
        clk_audio_old <= clk_audio;
        if (clk_audio & ~clk_audio_old) begin
            if (clk_audio_counter == clk_audio_counter_end)
            begin
                clk_audio_counter <= 6'd0;
                internal_clk_audio_counter_wrap <= !internal_clk_audio_counter_wrap;
            end
            else
                clk_audio_counter <= clk_audio_counter + 1'd1;
        end
    end
end

logic [1:0] clk_audio_counter_wrap_synchronizer_chain;
always_ff @(posedge clk_pixel)
begin
    if (reset)
        clk_audio_counter_wrap_synchronizer_chain <= 2'd0;
    else if (audio_rate_48k != active_rate_48k)
        clk_audio_counter_wrap_synchronizer_chain <=
            {2{internal_clk_audio_counter_wrap}};
    else
        clk_audio_counter_wrap_synchronizer_chain <= {internal_clk_audio_counter_wrap, clk_audio_counter_wrap_synchronizer_chain[1]};
end

logic [19:0] cycle_time_stamp;
logic [19:0] cycle_time_stamp_counter;
always_ff @(posedge clk_pixel)
begin
    if (reset)
    begin
        cycle_time_stamp <= 20'd0;
        cycle_time_stamp_counter <= 20'd0;
        clk_audio_counter_wrap <= 1'b0;
    end
    else if (audio_rate_48k != active_rate_48k) begin
        cycle_time_stamp <= 20'd0;
        cycle_time_stamp_counter <= 20'd0;
    end
    else if (clk_audio_counter_wrap_synchronizer_chain[1] ^ clk_audio_counter_wrap_synchronizer_chain[0])
    begin
        cycle_time_stamp_counter <= 20'd0;
        cycle_time_stamp <= cycle_time_stamp_counter + 20'd1;
        clk_audio_counter_wrap <= !clk_audio_counter_wrap;
    end
    else
        cycle_time_stamp_counter <= cycle_time_stamp_counter + 20'd1;
end

// "An HDMI Sink shall ignore bytes HB1 and HB2 of the Audio Clock Regeneration Packet header."
`ifdef MODEL_TECH
assign header = {8'd0, 8'd0, 8'd1};
`else
assign header = {8'dX, 8'dX, 8'd1};
`endif

// "The four Subpackets each contain the same Audio Clock regeneration Subpacket."
genvar i;
generate
    for (i = 0; i < 4; i++)
    begin: same_packet
        assign sub[i] = {n_value[7:0], n_value[15:8], {4'd0, n_value[19:16]}, cycle_time_stamp[7:0], cycle_time_stamp[15:8], {4'd0, cycle_time_stamp[19:16]}, 8'd0};
    end
endgenerate

endmodule
