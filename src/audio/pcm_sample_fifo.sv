// Single-clock FIFO for decoded stereo PCM samples. The extra stored bit marks
// the final sample of a stream so short files can drain without relying on a
// later transport event.

module pcm_sample_fifo #(
    parameter integer ADDRESS_WIDTH = 11
) (
    input  logic                   clk,
    input  logic                   reset,
    input  logic                   clear,
    input  logic [32:0]            input_data,
    input  logic                   input_valid,
    output logic                   input_ready,
    output logic [32:0]            output_data,
    output logic                   output_valid,
    input  logic                   output_ready,
    output logic [ADDRESS_WIDTH:0] level
);

localparam integer DEPTH = 1 << ADDRESS_WIDTH;
localparam logic [ADDRESS_WIDTH:0] DEPTH_COUNT = {1'b1, {ADDRESS_WIDTH{1'b0}}};

logic [32:0] memory [0:DEPTH-1];
logic [ADDRESS_WIDTH-1:0] write_pointer;
logic [ADDRESS_WIDTH-1:0] read_pointer;

wire push = input_valid && input_ready;
wire pop = output_valid && output_ready;

assign input_ready = level != DEPTH_COUNT;
assign output_valid = level != 0;
assign output_data = memory[read_pointer];

always_ff @(posedge clk) begin
    if (reset || clear) begin
        write_pointer <= 0;
        read_pointer <= 0;
        level <= 0;
    end else begin
        if (push) begin
            memory[write_pointer] <= input_data;
            write_pointer <= write_pointer + 1'b1;
        end

        if (pop)
            read_pointer <= read_pointer + 1'b1;

        case ({push, pop})
            2'b10: level <= level + 1'b1;
            2'b01: level <= level - 1'b1;
            default: level <= level;
        endcase
    end
end

endmodule
