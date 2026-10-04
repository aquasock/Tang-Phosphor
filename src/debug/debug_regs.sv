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
    input  [14:0] pcm_fifo_level,
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
    input  [31:0] boundary_count,
    input  [31:0] boundary_gap_samples,
    input  [15:0] audible_stream_id,

    // Mirror block, added by the socket bring-up fold.  Addresses live in the
    // previously unused hi-bank slots from word index 40 (0xa0); nothing above
    // moves, because Tang-Control and the firmware already depend on the rest.
    // Values are raw on purpose: meanings live with the consumer, and a
    // register derived for a consumer's convenience was rejected once already
    // when it cost 10.6 percent of Fmax.
    input  [31:0] src_signature,
    input  [31:0] hdmi_signature,
    input  [31:0] oled_signature,
    input  [31:0] render_frames,
    input  [31:0] oled_frames,
    input  [31:0] hdmi_frames,
    input        source_bank,
    input  [2:0]  render_pattern,
    input  [31:0] enc_count,
    input  [3:0]  enc_raw,
    input         enc_button,
    input         enc_switch,

    // TinyTang keyboard link (src/input/keylink_rx.sv).  These are here so the
    // link can be tested without a display: the counters say whether frames
    // are arriving intact, and the report says what the keyboard sent, both of
    // which are readable over the transport.
    input  [31:0] link_frames,
    input  [31:0] link_bad_checksum,
    input  [31:0] link_truncated,
    input  [7:0]  link_mods,
    input  [7:0]  link_key0,
    input  [7:0]  link_key1,
    output reg [3:0] pmod0_personality,
    output reg [3:0] pmod1_personality,
    output reg       pmod0_flipped,
    output reg       pmod1_flipped,
    output reg       render_hold,
    output reg [31:0] request_rdata
);

localparam [31:0] MAGIC = 32'h5450_4830; // "TPH0"
localparam [31:0] BUILD_DATE = 32'h2026_0927;

// The mirror block's control registers are the ports above.  Power-on declares
// nothing on either socket, which leaves both released: that is the safe state,
// and the same one a missing /tang.ini produces, since an undeclared module
// must never be driven.

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
        // Safe state: nothing declared, so every socket stays released until a
        // host says otherwise.
        pmod0_personality <= 4'd0;
        pmod1_personality <= 4'd0;
        pmod0_flipped     <= 1'b0;
        pmod1_flipped     <= 1'b0;
        render_hold       <= 1'b0;
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
                else if (request_address == 32'h0000_00c0) begin
                    render_hold       <= request_wdata[0];
                    pmod0_personality <= request_wdata[7:4];
                    pmod1_personality <= request_wdata[11:8];
                    pmod0_flipped     <= request_wdata[12];
                    pmod1_flipped     <= request_wdata[13];
                end
            end
        end
    end
end

// The transport latches the address six UART bytes before sampling read data,
// so a registered read multiplexer keeps this wide case off its response path.
// The read decode starts from its own copy of the address: iosys_bl616
// samples request_rdata six UART bytes after it sets the address, so the
// extra cycle is invisible, and the transport's address register no longer
// feeds the decode across the die.  Writes keep request_address, which block
// replay changes every cycle.
reg [31:0] read_address /* synthesis syn_maxfan = 16 */ = 32'd0;
always @(posedge clk)
    read_address <= request_address;

// Three stages from read_address: a word index and range check, two
// registered 32-way halves, then the final select.  Every readable register
// is word-aligned below 0x100; anything else reads 0xdeadbeef.
reg [5:0]  read_index = 6'd0;
reg        read_known = 1'b0;
reg        read_select_hi = 1'b0;
reg        read_known_q = 1'b0;
reg [31:0] read_lo = 32'd0;
reg [31:0] read_hi = 32'd0;

always @(posedge clk) begin
    read_index <= read_address[7:2];
    read_known <= read_address[31:8] == 24'd0 && read_address[1:0] == 2'd0;

    read_select_hi <= read_index[5];
    read_known_q <= read_known;
    case (read_index[4:0])
        5'd0: read_lo <= MAGIC;
        5'd1: read_lo <= 32'h0001_0007; // register ABI 1.7
        5'd2: read_lo <= BUILD_DATE;
        5'd3: read_lo <= 32'h0000_00ff;
        5'd4: read_lo <= uptime_cycles;
        5'd5: read_lo <= frame_count;
        5'd6: read_lo <= request_count;
        5'd7: read_lo <= write_count;
        5'd8: read_lo <= scratch;
        5'd9: read_lo <= transport_crc_errors;
        5'd10: read_lo <= transport_bad_requests;
        5'd12: read_lo <= stream_sessions;
        5'd13: read_lo <= stream_bytes;
        5'd14: read_lo <= stream_ends;
        5'd15: read_lo <= stream_cancels;
        5'd16: read_lo <= stream_last_offset;
        5'd17: read_lo <= stream_crc32;
        5'd18: read_lo <= {20'b0, controller1};
        5'd19: read_lo <= {20'b0, controller2};
        5'd20: read_lo <= {16'b0, hid1};
        5'd21: read_lo <= {16'b0, hid2};
        5'd22: read_lo <= {26'b0, controller_status};
        5'd23: read_lo <= {18'b0, audio_error, playback_active, audio_format_valid, player_state};
        5'd24: read_lo <= audio_sample_rate;
        5'd25: read_lo <= {17'b0, pcm_fifo_level};
        5'd26: read_lo <= samples_played;
        5'd27: read_lo <= audio_underruns;
        5'd28: read_lo <= hdmi_audio_rate;
        5'd29: read_lo <= {29'b0, detected_format};
        5'd30: read_lo <= {31'b0, pause_requested};
        5'd31: read_lo <= {30'b0, ui_playlist, ui_visible};
        default: read_lo <= 32'hdead_beef;
    endcase
    case (read_index[4:0])
        5'd0: read_hi <= {8'b0, ui_window_start, ui_track_count, ui_current_track};
        5'd3: read_hi <= elapsed_seconds;
        5'd4: read_hi <= duration_seconds;
        5'd7: read_hi <= boundary_count;
        5'd8: read_hi <= boundary_gap_samples;
        5'd9: read_hi <= {16'b0, audible_stream_id};
        // Mirror block, word indices 48-57 (0xc0-0xe4).  Layouts match the
        // socket bring-up core bit for bit, so the checker's decoding carries
        // over: control packs the renderer's frame selector above the declaration, and the
        // encoder state keeps raw at 7:4, switch at 3, button at 2.
        5'd16: read_hi <= {13'b0, render_pattern, 2'b0,
                           pmod1_flipped, pmod0_flipped,
                           pmod1_personality, pmod0_personality,
                           3'b0, render_hold};
        5'd17: read_hi <= {31'b0, source_bank};
        5'd18: read_hi <= src_signature;
        5'd19: read_hi <= hdmi_signature;
        5'd20: read_hi <= oled_signature;
        5'd21: read_hi <= render_frames;
        5'd22: read_hi <= oled_frames;
        5'd23: read_hi <= hdmi_frames;
        5'd24: read_hi <= enc_count;
        5'd25: read_hi <= {24'b0, enc_raw, 2'b0, enc_switch, enc_button};
        // Keyboard link.  Word 26 onwards is new, so nothing already reading
        // this map has to move.
        5'd26: read_hi <= link_frames;
        5'd27: read_hi <= link_bad_checksum;
        5'd28: read_hi <= link_truncated;
        // Last accepted report: modifiers, then the first two keycodes.
        5'd29: read_hi <= {8'b0, link_mods, link_key0, link_key1};
        default: read_hi <= 32'hdead_beef;
    endcase

    request_rdata <= !read_known_q ? 32'hdead_beef :
                     read_select_hi ? read_hi : read_lo;
end

endmodule
