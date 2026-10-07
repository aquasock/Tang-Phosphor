// SPDX-License-Identifier: GPL-3.0-only
// One audio frame clock owns both I2S output and HDMI sample delivery.
// A toggle request fetches one coherent PCM pair from the pixel-clock FIFO
// for the next frame. The producer holds the pair until its next request;
// an acknowledgement crosses two flip-flops before the audio side reads it.
// The actual emitted pair returns with a frame toggle for HDMI. These low
// frequency, held-bus crossings follow local colibri's handshake practice.
module i2s_playback (
    input logic clk_pixel,
    input logic clk_mclk,
    input logic resetn,
    input logic running,
    input logic ready,
    input logic flush,
    input logic paused,
    input logic pcm_valid,
    input logic [15:0] pcm_left, pcm_right,
    output logic sample_tick,
    output logic clk_audio,
    output logic [15:0] hdmi_left, hdmi_right,
    output logic [7:0] lane_o, lane_oe
);
    logic [1:0] audio_reset_sync = 0 /* synthesis syn_srlstyle = "registers" */;
    wire enable = resetn && running;
    always_ff @(posedge clk_mclk or negedge enable) begin
        if (!enable) audio_reset_sync <= 0;
        else audio_reset_sync <= {audio_reset_sync[0], 1'b1};
    end
    wire audio_resetn = audio_reset_sync[1];

    logic [7:0] epoch;
    wire [7:0] epoch_gray = epoch ^ (epoch >> 1);
    always_ff @(posedge clk_pixel) begin
        if (!resetn) epoch <= 0;
        else if (flush) epoch <= epoch + 8'd1;
    end

    logic request_toggle, ack_toggle, frame_toggle;
    logic [39:0] source_pair, emitted_pair;
    logic request_meta /* synthesis syn_srlstyle = "registers" */;
    logic request_sync /* synthesis syn_srlstyle = "registers" */;
    logic request_seen;
    logic frame_meta /* synthesis syn_srlstyle = "registers" */;
    logic frame_sync /* synthesis syn_srlstyle = "registers" */;
    logic frame_seen;
    wire request_event = request_sync != request_seen;
    // Count underruns on empty requests as the existing PCM sink does, but
    // never pop while muted, paused, or clearing a stream.
    assign sample_tick = enable && ready && request_event && !paused && !flush;

    always_ff @(posedge clk_pixel) begin
        if (!enable) begin
            request_meta <= 0;
            request_sync <= 0;
            request_seen <= 0;
            ack_toggle <= 0;
            source_pair <= 0;
            frame_meta <= 0;
            frame_sync <= 0;
            frame_seen <= 0;
            hdmi_left <= 0;
            hdmi_right <= 0;
            clk_audio <= 0;
        end else begin
            request_meta <= request_toggle;
            request_sync <= request_meta;
            frame_meta <= frame_toggle;
            frame_sync <= frame_meta;
            clk_audio <= 0;
            if (request_event) begin
                request_seen <= request_sync;
                source_pair <= {epoch_gray,
                    ready && pcm_valid && !paused && !flush ? {pcm_right, pcm_left} : 32'd0};
                ack_toggle <= request_sync;
            end
            if (frame_sync != frame_seen) begin
                frame_seen <= frame_sync;
                clk_audio <= 1;
                hdmi_left <= emitted_pair[15:0];
                hdmi_right <= emitted_pair[31:16];
            end
        end
    end

    logic ack_meta /* synthesis syn_srlstyle = "registers" */;
    logic ack_sync /* synthesis syn_srlstyle = "registers" */;
    logic ack_seen;
    logic [8:0] control_meta /* synthesis syn_srlstyle = "registers" */;
    logic [8:0] control_sync /* synthesis syn_srlstyle = "registers" */;
    logic [39:0] pending_pair;
    logic pending_valid;
    wire frame_tick;
    wire [31:0] play_pair = pending_valid && control_sync[8] &&
                            pending_pair[39:32] == control_sync[7:0]
                            ? pending_pair[31:0] : 32'd0;
    wire sclk, lrck, sdata;

    always_ff @(posedge clk_mclk or negedge audio_resetn) begin
        if (!audio_resetn) begin
            request_toggle <= 0;
            ack_meta <= 0;
            ack_sync <= 0;
            ack_seen <= 0;
            control_meta <= 0;
            control_sync <= 0;
            pending_pair <= 0;
            pending_valid <= 0;
            emitted_pair <= 0;
            frame_toggle <= 0;
        end else begin
            ack_meta <= ack_toggle;
            ack_sync <= ack_meta;
            control_meta <= {ready, epoch_gray};
            control_sync <= control_meta;
            if (frame_tick) begin
                request_toggle <= !request_toggle;
                emitted_pair <= {control_sync[7:0], play_pair};
                frame_toggle <= !frame_toggle;
                pending_valid <= 0;
            end
            if (ack_sync != ack_seen) begin
                ack_seen <= ack_sync;
                pending_pair <= source_pair;
                pending_valid <= 1;
            end
        end
    end

    i2s_tx tx (
        .clk_mclk(clk_mclk), .resetn(audio_resetn),
        .sample_left(play_pair[15:0]), .sample_right(play_pair[31:16]),
        .sclk(sclk), .lrck(lrck), .sdata(sdata), .sample_tick(frame_tick)
    );
    assign lane_o = {4'b0, sdata, sclk, lrck, clk_mclk && audio_resetn};
    // Only the DAC row is driven. The socket mux releases undeclared pins.
    assign lane_oe = resetn ? 8'h0f : 8'h00;
endmodule
