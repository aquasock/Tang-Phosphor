// Tang-Phosphor's core-owned debug register bank. The BL616 transport only
// moves generic 32-bit transactions; meanings remain part of this project.

module debug_regs (
    input         clk,
    input         resetn,
    input         frame_tick,
    input         request_valid,
    input         request_write,
    input  [31:0] request_address,
    input  [31:0] request_wdata,
    input  [31:0] transport_crc_errors,
    input  [31:0] transport_bad_requests,
    input  [31:0] stream_sessions,
    input  [31:0] stream_bytes,
    input  [31:0] stream_ends,
    input  [31:0] stream_cancels,
    input  [31:0] stream_last_offset,
    input  [31:0] stream_crc32,
    output reg [31:0] request_rdata
);

localparam [31:0] MAGIC = 32'h5450_4830; // "TPH0"
localparam [31:0] BUILD_DATE = 32'h2026_0927;

reg [31:0] uptime_cycles;
reg [31:0] frame_count;
reg [31:0] request_count;
reg [31:0] write_count;
reg [31:0] scratch;

always @(posedge clk) begin
    if (!resetn) begin
        uptime_cycles <= 0;
        frame_count <= 0;
        request_count <= 0;
        write_count <= 0;
        scratch <= 0;
    end else begin
        uptime_cycles <= uptime_cycles + 1'b1;
        if (frame_tick)
            frame_count <= frame_count + 1'b1;
        if (request_valid) begin
            request_count <= request_count + 1'b1;
            if (request_write) begin
                write_count <= write_count + 1'b1;
                if (request_address == 32'h0000_0020)
                    scratch <= request_wdata;
            end
        end
    end
end

always @* begin
    case (request_address)
        32'h0000_0000: request_rdata = MAGIC;
        32'h0000_0004: request_rdata = 32'h0001_0000; // register ABI 1.0
        32'h0000_0008: request_rdata = BUILD_DATE;
        32'h0000_000c: request_rdata = 32'h0000_0001; // bit 0: debug bank
        32'h0000_0010: request_rdata = uptime_cycles;
        32'h0000_0014: request_rdata = frame_count;
        32'h0000_0018: request_rdata = request_count;
        32'h0000_001c: request_rdata = write_count;
        32'h0000_0020: request_rdata = scratch;
        32'h0000_0024: request_rdata = transport_crc_errors;
        32'h0000_0028: request_rdata = transport_bad_requests;
        32'h0000_0030: request_rdata = stream_sessions;
        32'h0000_0034: request_rdata = stream_bytes;
        32'h0000_0038: request_rdata = stream_ends;
        32'h0000_003c: request_rdata = stream_cancels;
        32'h0000_0040: request_rdata = stream_last_offset;
        32'h0000_0044: request_rdata = stream_crc32;
        default:       request_rdata = 32'hdead_beef;
    endcase
end

endmodule
