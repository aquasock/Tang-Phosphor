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
    input  [11:0] controller1,
    input  [11:0] controller2,
    input  [15:0] hid1,
    input  [15:0] hid2,
    input   [5:0] controller_status,
    input   [3:0] player_state,
    input         audio_format_valid,
    input         playback_active,
    input  [31:0] audio_sample_rate,
    input  [11:0] pcm_fifo_level,
    input  [31:0] samples_played,
    input  [31:0] audio_underruns,
    input   [7:0] audio_error,
    input  [31:0] hdmi_audio_rate,
    input   [2:0] detected_format,
    input         pause_requested,
    input         ui_visible,
    input         ui_playlist,
    input   [7:0] ui_current_track,
    input   [7:0] ui_track_count,
    input   [7:0] ui_window_start,
    input  [31:0] elapsed_seconds,
    input  [31:0] duration_seconds,
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
        32'h0000_0004: request_rdata = 32'h0001_0006; // register ABI 1.6
        32'h0000_0008: request_rdata = BUILD_DATE;
        32'h0000_000c: request_rdata = 32'h0000_007f;
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
        32'h0000_0048: request_rdata = {20'b0, controller1};
        32'h0000_004c: request_rdata = {20'b0, controller2};
        32'h0000_0050: request_rdata = {16'b0, hid1};
        32'h0000_0054: request_rdata = {16'b0, hid2};
        32'h0000_0058: request_rdata = {26'b0, controller_status};
        32'h0000_005c: request_rdata = {18'b0, audio_error,
            playback_active, audio_format_valid, player_state};
        32'h0000_0060: request_rdata = audio_sample_rate;
        32'h0000_0064: request_rdata = {20'b0, pcm_fifo_level};
        32'h0000_0068: request_rdata = samples_played;
        32'h0000_006c: request_rdata = audio_underruns;
        32'h0000_0070: request_rdata = hdmi_audio_rate;
        32'h0000_0074: request_rdata = {29'b0, detected_format};
        32'h0000_0078: request_rdata = {31'b0, pause_requested};
        32'h0000_007c: request_rdata = {30'b0, ui_playlist, ui_visible};
        32'h0000_0080: request_rdata = {8'b0, ui_window_start,
            ui_track_count, ui_current_track};
        32'h0000_008c: request_rdata = elapsed_seconds;
        32'h0000_0090: request_rdata = duration_seconds;
        default:       request_rdata = 32'hdead_beef;
    endcase
end

endmodule
