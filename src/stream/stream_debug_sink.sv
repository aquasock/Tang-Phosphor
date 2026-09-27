// Observation-only monitor for the generic BL616 stream channel. The active
// consumer owns ready; this block counts and checksums only accepted bytes.

module stream_debug_sink (
    input         clk,
    input         resetn,
    input         stream_start,
    input         stream_end,
    input         stream_cancel,
    input  [15:0] stream_id,
    input  [31:0] stream_offset,
    input   [7:0] stream_data,
    input         stream_valid,
    input         stream_ready,
    output reg [31:0] session_count,
    output reg [31:0] byte_count,
    output reg [31:0] end_count,
    output reg [31:0] cancel_count,
    output reg [31:0] last_offset,
    output reg [31:0] stream_crc32
);

function [31:0] crc32_byte;
    input [31:0] crc_in;
    input [7:0] data;
    integer bit_index;
    reg [31:0] crc;
    begin
        crc = crc_in ^ data;
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
            crc = crc[0] ? (crc >> 1) ^ 32'hedb8_8320 : crc >> 1;
        crc32_byte = crc;
    end
endfunction

always @(posedge clk) begin
    if (!resetn) begin
        session_count <= 0;
        byte_count <= 0;
        end_count <= 0;
        cancel_count <= 0;
        last_offset <= 0;
        stream_crc32 <= 32'hffff_ffff;
    end else begin
        if (stream_start) begin
            session_count <= session_count + 1'b1;
            byte_count <= 0;
            last_offset <= 0;
            stream_crc32 <= 32'hffff_ffff;
        end
        if (stream_valid && stream_ready) begin
            byte_count <= byte_count + 1'b1;
            last_offset <= stream_offset;
            stream_crc32 <= crc32_byte(stream_crc32, stream_data);
        end
        if (stream_end) begin
            end_count <= end_count + 1'b1;
            stream_crc32 <= ~stream_crc32;
        end
        if (stream_cancel)
            cancel_count <= cancel_count + 1'b1;
    end
end

endmodule
