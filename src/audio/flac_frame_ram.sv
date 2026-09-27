// One provisional/committed FLAC frame bank. Separate channel memories allow
// both coded channels to be read in one cycle for stereo reconstruction.

module flac_frame_ram #(
    parameter integer MAX_BLOCK_SIZE = 4608,
    parameter integer ADDRESS_WIDTH = 13
) (
    input  logic                      clk,
    input  logic                      write_enable,
    input  logic                      write_channel,
    input  logic [ADDRESS_WIDTH-1:0]  write_address,
    input  logic signed [16:0]        write_data,
    input  logic [ADDRESS_WIDTH-1:0]  read_address,
    output logic signed [16:0]        read_channel0,
    output logic signed [16:0]        read_channel1
);

(* syn_ramstyle = "block_ram" *) logic signed [16:0]
    channel0_memory [0:MAX_BLOCK_SIZE-1];
(* syn_ramstyle = "block_ram" *) logic signed [16:0]
    channel1_memory [0:MAX_BLOCK_SIZE-1];

always_ff @(posedge clk) begin
    if (write_enable) begin
        if (write_channel)
            channel1_memory[write_address] <= write_data;
        else
            channel0_memory[write_address] <= write_data;
    end

    read_channel0 <= channel0_memory[read_address];
    read_channel1 <= channel1_memory[read_address];
end

endmodule
