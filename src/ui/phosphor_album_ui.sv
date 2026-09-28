// Native 720p Phosphor library screen. Tang-Control supplies bounded ASCII
// metadata; playback position and timing remain FPGA-owned.

module phosphor_album_ui (
    input  logic        clk,
    input  logic        resetn,
    input  logic [10:0] x,
    input  logic  [9:0] y,
    input  logic [23:0] rgb_in,
    input  logic        visible,
    input  logic        playlist,
    input  logic        paused,
    input  logic  [3:0] player_state,
    input  logic  [7:0] current_track,
    input  logic  [7:0] track_count,
    input  logic  [7:0] window_start,
    input  logic [31:0] lengths_0_3,
    input  logic [31:0] lengths_4_7,
    input  logic  [7:0] length_8,
    output logic  [8:0] text_address,
    input  logic  [7:0] text_data,
    input  logic        artwork_valid,
    output logic [13:0] artwork_address,
    input  logic  [7:0] artwork_data,
    input  logic [31:0] samples_played,
    input  logic [35:0] total_samples,
    input  logic [31:0] elapsed_seconds,
    input  logic [31:0] duration_seconds,
    output logic [23:0] rgb_out
);

localparam logic [3:0] PLAYER_IDLE = 4'd0;
localparam logic [3:0] PLAYER_RECEIVING = 4'd1;
localparam logic [3:0] PLAYER_PREFILL = 4'd2;
localparam logic [3:0] PLAYER_PLAYING = 4'd3;
localparam logic [3:0] PLAYER_COMPLETE = 4'd4;
localparam logic [3:0] PLAYER_ERROR = 4'd5;

localparam integer CELL_WIDTH = 16;
localparam integer CELL_HEIGHT = 20;

logic [7:0] title_scroll;
logic [7:0] album_scroll;
logic [7:0] artist_scroll;
logic [7:0] scroll_divider;
logic [6:0] scroll_hold;
logic [7:0] tracked_track;
wire frame_tick = x == 0 && y == 0;

function automatic [7:0] slot_length(input logic [3:0] slot);
begin
    case (slot)
        0: slot_length = lengths_0_3[31:24];
        1: slot_length = lengths_0_3[23:16];
        2: slot_length = lengths_0_3[15:8];
        3: slot_length = lengths_0_3[7:0];
        4: slot_length = lengths_4_7[31:24];
        5: slot_length = lengths_4_7[23:16];
        6: slot_length = lengths_4_7[15:8];
        7: slot_length = lengths_4_7[7:0];
        default: slot_length = length_8;
    endcase
end
endfunction

always_ff @(posedge clk) begin
    if (!resetn || !visible) begin
        title_scroll <= 0;
        album_scroll <= 0;
        artist_scroll <= 0;
        scroll_divider <= 0;
        scroll_hold <= 7'd60;
        tracked_track <= 0;
    end else if (frame_tick) begin
        if (tracked_track != current_track) begin
            tracked_track <= current_track;
            title_scroll <= 0;
            album_scroll <= 0;
            artist_scroll <= 0;
            scroll_divider <= 0;
            scroll_hold <= 7'd60;
        end else if (scroll_hold != 0) begin
            scroll_hold <= scroll_hold - 1'b1;
        end else if (scroll_divider == 8'd7) begin
            scroll_divider <= 0;
            if (slot_length(1) > 18)
                artist_scroll <= artist_scroll >= slot_length(1) - 18 ?
                    8'd0 : 8'(artist_scroll + 1'b1);
            else
                artist_scroll <= 0;
            if (slot_length(2) > 18)
                title_scroll <= title_scroll >= slot_length(2) - 18 ?
                    8'd0 : 8'(title_scroll + 1'b1);
            else
                title_scroll <= 0;
            if (slot_length(0) > 18)
                album_scroll <= album_scroll >= slot_length(0) - 18 ?
                    8'd0 : 8'(album_scroll + 1'b1);
            else
                album_scroll <= 0;
            if ((slot_length(1) > 18 && artist_scroll >= slot_length(1) - 18) ||
                    (slot_length(2) > 18 && title_scroll >= slot_length(2) - 18) ||
                    (slot_length(0) > 18 && album_scroll >= slot_length(0) - 18))
                scroll_hold <= 7'd60;
        end else begin
            scroll_divider <= scroll_divider + 1'b1;
        end
    end
end

function automatic [7:0] static_glyph(
    input logic [3:0] line,
    input logic [5:0] index
);
begin
    case ({line, index})
        10'h000: static_glyph = 8'h50;
        10'h001: static_glyph = 8'h48;
        10'h002: static_glyph = 8'h4f;
        10'h003: static_glyph = 8'h53;
        10'h004: static_glyph = 8'h50;
        10'h005: static_glyph = 8'h48;
        10'h006: static_glyph = 8'h4f;
        10'h007: static_glyph = 8'h52;
        10'h040: static_glyph = 8'h41;
        10'h041: static_glyph = 8'h4c;
        10'h042: static_glyph = 8'h42;
        10'h043: static_glyph = 8'h55;
        10'h044: static_glyph = 8'h4d;
        10'h045: static_glyph = 8'h20;
        10'h046: static_glyph = 8'h2f;
        10'h047: static_glyph = 8'h20;
        10'h048: static_glyph = 8'h50;
        10'h049: static_glyph = 8'h4c;
        10'h04a: static_glyph = 8'h41;
        10'h04b: static_glyph = 8'h59;
        10'h04c: static_glyph = 8'h4c;
        10'h04d: static_glyph = 8'h49;
        10'h04e: static_glyph = 8'h53;
        10'h04f: static_glyph = 8'h54;
        10'h080: static_glyph = 8'h4e;
        10'h081: static_glyph = 8'h4f;
        10'h082: static_glyph = 8'h57;
        10'h083: static_glyph = 8'h20;
        10'h084: static_glyph = 8'h50;
        10'h085: static_glyph = 8'h4c;
        10'h086: static_glyph = 8'h41;
        10'h087: static_glyph = 8'h59;
        10'h088: static_glyph = 8'h49;
        10'h089: static_glyph = 8'h4e;
        10'h08a: static_glyph = 8'h47;
        10'h0c0: static_glyph = 8'h43;
        10'h0c1: static_glyph = 8'h55;
        10'h0c2: static_glyph = 8'h52;
        10'h0c3: static_glyph = 8'h52;
        10'h0c4: static_glyph = 8'h45;
        10'h0c5: static_glyph = 8'h4e;
        10'h0c6: static_glyph = 8'h54;
        10'h0c7: static_glyph = 8'h20;
        10'h0c8: static_glyph = 8'h50;
        10'h0c9: static_glyph = 8'h4c;
        10'h0ca: static_glyph = 8'h41;
        10'h0cb: static_glyph = 8'h59;
        10'h0cc: static_glyph = 8'h4c;
        10'h0cd: static_glyph = 8'h49;
        10'h0ce: static_glyph = 8'h53;
        10'h0cf: static_glyph = 8'h54;
        10'h100: static_glyph = 8'h50;
        10'h101: static_glyph = 8'h4c;
        10'h102: static_glyph = 8'h41;
        10'h103: static_glyph = 8'h59;
        10'h104: static_glyph = 8'h49;
        10'h105: static_glyph = 8'h4e;
        10'h106: static_glyph = 8'h47;
        10'h140: static_glyph = 8'h50;
        10'h141: static_glyph = 8'h41;
        10'h142: static_glyph = 8'h55;
        10'h143: static_glyph = 8'h53;
        10'h144: static_glyph = 8'h45;
        10'h145: static_glyph = 8'h44;
        10'h180: static_glyph = 8'h4c;
        10'h181: static_glyph = 8'h4f;
        10'h182: static_glyph = 8'h41;
        10'h183: static_glyph = 8'h44;
        10'h184: static_glyph = 8'h49;
        10'h185: static_glyph = 8'h4e;
        10'h186: static_glyph = 8'h47;
        10'h1c0: static_glyph = 8'h43;
        10'h1c1: static_glyph = 8'h4f;
        10'h1c2: static_glyph = 8'h4d;
        10'h1c3: static_glyph = 8'h50;
        10'h1c4: static_glyph = 8'h4c;
        10'h1c5: static_glyph = 8'h45;
        10'h1c6: static_glyph = 8'h54;
        10'h1c7: static_glyph = 8'h45;
        10'h200: static_glyph = 8'h45;
        10'h201: static_glyph = 8'h52;
        10'h202: static_glyph = 8'h52;
        10'h203: static_glyph = 8'h4f;
        10'h204: static_glyph = 8'h52;
        10'h240: static_glyph = 8'h53;
        10'h241: static_glyph = 8'h54;
        10'h242: static_glyph = 8'h41;
        10'h243: static_glyph = 8'h52;
        10'h244: static_glyph = 8'h54;
        10'h245: static_glyph = 8'h3a;
        10'h246: static_glyph = 8'h20;
        10'h247: static_glyph = 8'h50;
        10'h248: static_glyph = 8'h41;
        10'h249: static_glyph = 8'h55;
        10'h24a: static_glyph = 8'h53;
        10'h24b: static_glyph = 8'h45;
        10'h24c: static_glyph = 8'h20;
        10'h24d: static_glyph = 8'h20;
        10'h24e: static_glyph = 8'h20;
        10'h24f: static_glyph = 8'h4c;
        10'h250: static_glyph = 8'h45;
        10'h251: static_glyph = 8'h46;
        10'h252: static_glyph = 8'h54;
        10'h253: static_glyph = 8'h2f;
        10'h254: static_glyph = 8'h52;
        10'h255: static_glyph = 8'h49;
        10'h256: static_glyph = 8'h47;
        10'h257: static_glyph = 8'h48;
        10'h258: static_glyph = 8'h54;
        10'h259: static_glyph = 8'h3a;
        10'h25a: static_glyph = 8'h20;
        10'h25b: static_glyph = 8'h54;
        10'h25c: static_glyph = 8'h52;
        10'h25d: static_glyph = 8'h41;
        10'h25e: static_glyph = 8'h43;
        10'h25f: static_glyph = 8'h4b;
        10'h260: static_glyph = 8'h20;
        10'h261: static_glyph = 8'h20;
        10'h262: static_glyph = 8'h20;
        10'h263: static_glyph = 8'h58;
        10'h264: static_glyph = 8'h3a;
        10'h265: static_glyph = 8'h20;
        10'h266: static_glyph = 8'h49;
        10'h267: static_glyph = 8'h4e;
        10'h268: static_glyph = 8'h46;
        10'h269: static_glyph = 8'h4f;
        default: static_glyph = 8'h20;
    endcase
end
endfunction

function automatic [7:0] time_glyph(
    input logic [23:0] digits,
    input logic [3:0] index
);
begin
    case (index)
        0: time_glyph = {4'h3, digits[23:20]};
        1: time_glyph = {4'h3, digits[19:16]};
        2, 5: time_glyph = ":";
        3: time_glyph = {4'h3, digits[15:12]};
        4: time_glyph = {4'h3, digits[11:8]};
        6: time_glyph = {4'h3, digits[7:4]};
        default: time_glyph = {4'h3, digits[3:0]};
    endcase
end
endfunction

logic [23:0] elapsed_digits;
logic [23:0] duration_digits;
logic [5:0] progress_filled;
logic [5:0] progress_step;
logic [41:0] progress_scaled_samples;
logic [41:0] progress_threshold;
logic [35:0] progress_total;
logic progress_busy;

localparam logic [4:0] TEXT_NONE = 0;
localparam logic [4:0] TEXT_PHOSPHOR = 1;
localparam logic [4:0] TEXT_PLAYLIST_LABEL = 4;
localparam logic [4:0] TEXT_ALBUM = 7;
localparam logic [4:0] TEXT_ARTIST = 8;
localparam logic [4:0] TEXT_ROW_0 = 9;
localparam logic [4:0] TEXT_ROW_1 = 10;
localparam logic [4:0] TEXT_ROW_2 = 11;
localparam logic [4:0] TEXT_ROW_3 = 12;
localparam logic [4:0] TEXT_ROW_4 = 13;
localparam logic [4:0] TEXT_ROW_5 = 14;
localparam logic [4:0] TEXT_ELAPSED = 15;
localparam logic [4:0] TEXT_DURATION = 16;
localparam logic [4:0] TEXT_TRACK = 17;

logic [4:0] text_zone;
logic [4:0] text_zone_q;
logic [10:0] text_local_x;
logic [9:0] text_local_y;
logic [7:0] text_length;
logic [5:0] text_scroll;
logic text_row_selected;
logic [10:0] text_local_x_q;
logic [9:0] text_local_y_q;
logic [7:0] text_length_q;
logic [5:0] text_scroll_q;
logic text_row_selected_q;

// Playlist rows compare against one registered offset instead of adding the
// window start to every raster row: current == start + row <=> row ==
// current - start, modulo 256.
logic [7:0] selected_row_q;
always_ff @(posedge clk) begin
    if (!resetn)
        selected_row_q <= 0;
    else
        selected_row_q <= current_track - window_start;
end

// First register classifies the sparse text rectangles and resolves each
// zone's local coordinates, slot length, scroll, and row selection.  The
// following stage then only indexes characters, keeping the pixel counter
// and the slot-length multiplexer off the font-address critical path.
always_comb begin
    text_zone = TEXT_NONE;
    if (visible && track_count != 0) begin
        if (x >= 100 && x < 388) begin
            if (y >= 466 && y < 486) text_zone = TEXT_ALBUM;
            else if (y >= 518 && y < 538) text_zone = TEXT_ARTIST;
            else if (y >= 570 && y < 590) text_zone = TEXT_TRACK;
            else if (x < 228 && y >= 670 && y < 690)
                text_zone = TEXT_ELAPSED;
            else if (!artwork_valid && x >= 186 && x < 314 &&
                     y >= 190 && y < 210)
                text_zone = TEXT_PHOSPHOR;
        end else if (x >= 482 && x < 994 && playlist) begin
            if (y >= 166 && y < 186) text_zone = TEXT_ROW_0;
            else if (y >= 234 && y < 254) text_zone = TEXT_ROW_1;
            else if (y >= 302 && y < 322) text_zone = TEXT_ROW_2;
            else if (y >= 370 && y < 390) text_zone = TEXT_ROW_3;
            else if (y >= 438 && y < 458) text_zone = TEXT_ROW_4;
            else if (y >= 506 && y < 526) text_zone = TEXT_ROW_5;
            else if (x >= 690 && x < 946 && y >= 105 && y < 125)
                text_zone = TEXT_PLAYLIST_LABEL;
        end else if (x >= 1052 && x < 1180 && y >= 670 && y < 690) begin
            text_zone = TEXT_DURATION;
        end
    end
end

always_comb begin
    text_local_x = 0;
    text_local_y = 0;
    text_length = 0;
    text_scroll = 0;
    text_row_selected = 1'b0;
    case (text_zone)
        TEXT_PHOSPHOR: begin
            text_local_x = x - 186; text_local_y = y - 190;
        end
        TEXT_PLAYLIST_LABEL: begin
            text_local_x = x - 690; text_local_y = y - 105;
        end
        TEXT_ALBUM: begin
            text_local_x = x - 100; text_local_y = y - 466;
            text_length = slot_length(0); text_scroll = album_scroll[5:0];
        end
        TEXT_ARTIST: begin
            text_local_x = x - 100; text_local_y = y - 518;
            text_length = slot_length(1); text_scroll = artist_scroll[5:0];
        end
        TEXT_TRACK: begin
            text_local_x = x - 100; text_local_y = y - 570;
            text_length = slot_length(2); text_scroll = title_scroll[5:0];
        end
        TEXT_ROW_0: begin
            text_local_x = x - 482; text_local_y = y - 166;
            text_length = slot_length(3); text_row_selected = selected_row_q == 0;
        end
        TEXT_ROW_1: begin
            text_local_x = x - 482; text_local_y = y - 234;
            text_length = slot_length(4); text_row_selected = selected_row_q == 1;
        end
        TEXT_ROW_2: begin
            text_local_x = x - 482; text_local_y = y - 302;
            text_length = slot_length(5); text_row_selected = selected_row_q == 2;
        end
        TEXT_ROW_3: begin
            text_local_x = x - 482; text_local_y = y - 370;
            text_length = slot_length(6); text_row_selected = selected_row_q == 3;
        end
        TEXT_ROW_4: begin
            text_local_x = x - 482; text_local_y = y - 438;
            text_length = slot_length(7); text_row_selected = selected_row_q == 4;
        end
        TEXT_ROW_5: begin
            text_local_x = x - 482; text_local_y = y - 506;
            text_length = slot_length(8); text_row_selected = selected_row_q == 5;
        end
        TEXT_ELAPSED: begin
            text_local_x = x - 100; text_local_y = y - 670;
        end
        TEXT_DURATION: begin
            text_local_x = x - 1052; text_local_y = y - 670;
        end
        default: ;
    endcase
end

always_ff @(posedge clk) begin
    if (!resetn) begin
        text_zone_q <= TEXT_NONE;
        text_local_x_q <= 0;
        text_local_y_q <= 0;
        text_length_q <= 0;
        text_scroll_q <= 0;
        text_row_selected_q <= 1'b0;
    end else begin
        text_zone_q <= text_zone;
        text_local_x_q <= text_local_x;
        text_local_y_q <= text_local_y;
        text_length_q <= text_length;
        text_scroll_q <= text_scroll;
        text_row_selected_q <= text_row_selected;
    end
end

phosphor_time_digits elapsed_time (
    .clk(clk), .resetn(resetn), .seconds_value(elapsed_seconds),
    .digits(elapsed_digits)
);

phosphor_time_digits duration_time (
    .clk(clk), .resetn(resetn), .seconds_value(duration_seconds),
    .digits(duration_digits)
);

// Progress changes only once per video frame.  Work out the 32-block fill
// count over 32 cheap add/compare cycles instead of putting a wide multiply
// and divide in the raster path.
always_ff @(posedge clk) begin
    if (!resetn) begin
        progress_filled <= 0;
        progress_step <= 0;
        progress_scaled_samples <= 0;
        progress_threshold <= 0;
        progress_total <= 0;
        progress_busy <= 1'b0;
    end else if (frame_tick) begin
        progress_filled <= 0;
        progress_step <= 0;
        progress_scaled_samples <= {5'b0, samples_played, 5'b0};
        progress_threshold <= {6'b0, total_samples};
        progress_total <= total_samples;
        progress_busy <= total_samples != 0;
    end else if (progress_busy) begin
        if (progress_scaled_samples >= progress_threshold)
            progress_filled <= progress_step + 1'b1;
        if (progress_step == 6'd31) begin
            progress_busy <= 1'b0;
        end else begin
            progress_step <= progress_step + 1'b1;
            progress_threshold <= progress_threshold + {6'b0, progress_total};
        end
    end
end

// Base layout, stage 1: classify every panel, placeholder, progress, and
// playlist-row rectangle from the pixel counter.  Stage 2 only prioritizes the
// registered flags, so no comparison chain reaches the colour multiplexer.
logic [23:0] rgb_in_q;
logic region_visible;
logic art_panel, art_panel_border;
logic meta_panel, meta_panel_border;
logic list_panel, list_panel_border;
logic placeholder, placeholder_grid, placeholder_cross, placeholder_frame;
logic progress_area, progress_border;
logic [10:0] progress_x;
logic [5:0] progress_block;
logic row_band_selected;
logic region_visible_q;
logic art_panel_q, art_panel_border_q;
logic meta_panel_q, meta_panel_border_q;
logic list_panel_q, list_panel_border_q;
logic placeholder_q, placeholder_grid_q, placeholder_cross_q, placeholder_frame_q;
logic progress_area_q, progress_border_q;
logic [5:0] progress_block_q;
logic row_band_selected_q;

always_comb begin
    region_visible = visible && track_count != 0;

    // Three panels from the MiSTer album presentation: artwork, metadata,
    // and a six-row library viewport.
    art_panel = x >= 80 && x < 420 && y >= 80 && y < 420;
    art_panel_border = x < 84 || x >= 416 || y < 84 || y >= 416;
    meta_panel = x >= 80 && x < 420 && y >= 438 && y < 610;
    meta_panel_border = x < 84 || x >= 416 || y < 442 || y >= 606;
    list_panel = playlist && x >= 446 && x < 1200 && y >= 80 && y < 610;
    list_panel_border = x < 450 || x >= 1196 || y < 84 || y >= 606;

    // Keep the Phosphor placeholder until a complete artwork bank commits.
    placeholder = !artwork_valid && x >= 118 && x < 382 && y >= 118 && y < 382;
    placeholder_grid = x[5:0] == 0 || y[5:0] == 0;
    placeholder_cross = (x >= 244 && x < 256) || (y >= 244 && y < 256);
    placeholder_frame = (x >= 160 && x < 340 && (y == 160 || y == 340)) ||
                        (y >= 160 && y < 340 && (x == 160 || x == 340));

    // Quantized progress bar avoids a raster-rate divider.
    progress_area = x >= 100 && x < 1124 && y >= 644 && y < 660;
    progress_border = y == 644 || y == 659 || x == 100 || x == 1123;
    progress_x = x - 100;
    progress_block = progress_x[10:5];

    // Six playlist rows, with the active row highlighted as a complete band.
    row_band_selected = 1'b0;
    if (playlist && x >= 466 && x < 1180) begin
        if (y >= 150 && y < 202) row_band_selected = selected_row_q == 0;
        else if (y >= 218 && y < 270) row_band_selected = selected_row_q == 1;
        else if (y >= 286 && y < 338) row_band_selected = selected_row_q == 2;
        else if (y >= 354 && y < 406) row_band_selected = selected_row_q == 3;
        else if (y >= 422 && y < 474) row_band_selected = selected_row_q == 4;
        else if (y >= 490 && y < 542) row_band_selected = selected_row_q == 5;
    end
end

always_ff @(posedge clk) begin
    if (!resetn) begin
        rgb_in_q <= 0;
        region_visible_q <= 1'b0;
        art_panel_q <= 1'b0;
        art_panel_border_q <= 1'b0;
        meta_panel_q <= 1'b0;
        meta_panel_border_q <= 1'b0;
        list_panel_q <= 1'b0;
        list_panel_border_q <= 1'b0;
        placeholder_q <= 1'b0;
        placeholder_grid_q <= 1'b0;
        placeholder_cross_q <= 1'b0;
        placeholder_frame_q <= 1'b0;
        progress_area_q <= 1'b0;
        progress_border_q <= 1'b0;
        progress_block_q <= 0;
        row_band_selected_q <= 1'b0;
    end else begin
        rgb_in_q <= rgb_in;
        region_visible_q <= region_visible;
        art_panel_q <= art_panel;
        art_panel_border_q <= art_panel_border;
        meta_panel_q <= meta_panel;
        meta_panel_border_q <= meta_panel_border;
        list_panel_q <= list_panel;
        list_panel_border_q <= list_panel_border;
        placeholder_q <= placeholder;
        placeholder_grid_q <= placeholder_grid;
        placeholder_cross_q <= placeholder_cross;
        placeholder_frame_q <= placeholder_frame;
        progress_area_q <= progress_area;
        progress_border_q <= progress_border;
        progress_block_q <= progress_block;
        row_band_selected_q <= row_band_selected;
    end
end

logic [23:0] base_rgb;

always_comb begin
    base_rgb = rgb_in_q;
    if (region_visible_q) begin
        base_rgb = 24'h07100c;
        if (art_panel_q)
            base_rgb = art_panel_border_q ? 24'h668078 : 24'h0b1812;
        if (meta_panel_q)
            base_rgb = meta_panel_border_q ? 24'h668078 : 24'h0b1812;
        if (list_panel_q)
            base_rgb = list_panel_border_q ? 24'h668078 : 24'h0b1812;
        if (placeholder_q) begin
            if (placeholder_grid_q)
                base_rgb = 24'h183c2a;
            if (placeholder_cross_q)
                base_rgb = 24'h56f08c;
            if (placeholder_frame_q)
                base_rgb = 24'h2a8050;
        end
        if (progress_area_q) begin
            if (progress_border_q)
                base_rgb = 24'h668078;
            else if (progress_block_q < progress_filled)
                base_rgb = 24'h38d878;
            else
                base_rgb = 24'h14251d;
        end
        if (row_band_selected_q)
            base_rgb = 24'h183c2a;
    end
end

// Artwork addressing is registered twice before the block RAM: once for the
// panel-local coordinates and once for the 92-byte row multiply.  The
// artwork colour replaces the base layout two stages later in its delay line,
// so the total raster latency is unchanged.
logic artwork_pixel;
logic artwork_pixel_q;
logic artwork_pixel_qq;
logic artwork_pixel_qqq;
logic [6:0] artwork_x_q;
logic [6:0] artwork_y_q;

always_comb
    artwork_pixel = visible && track_count != 0 && artwork_valid &&
        x >= 158 && x < 342 && y >= 158 && y < 342;

always_ff @(posedge clk) begin
    if (!resetn) begin
        artwork_pixel_q <= 1'b0;
        artwork_pixel_qq <= 1'b0;
        artwork_pixel_qqq <= 1'b0;
        artwork_x_q <= 0;
        artwork_y_q <= 0;
        artwork_address <= 0;
    end else begin
        artwork_pixel_q <= artwork_pixel;
        artwork_pixel_qq <= artwork_pixel_q;
        artwork_pixel_qqq <= artwork_pixel_qq;
        artwork_x_q <= 7'((x - 11'd158) >> 1);
        artwork_y_q <= 7'((y - 10'd158) >> 1);
        artwork_address <= artwork_pixel_q ?
            {1'b0, artwork_y_q, 6'b0} + {3'b0, artwork_y_q, 4'b0} +
            {4'b0, artwork_y_q, 3'b0} + {5'b0, artwork_y_q, 2'b0} +
            {7'b0, artwork_x_q} : 14'd0;
    end
end

logic glyph_valid;
logic [7:0] glyph_character;
logic [2:0] glyph_x;
logic [3:0] glyph_y;
logic [23:0] glyph_color;
logic dynamic_text;
logic [1:0] char_mode;
logic [3:0] dynamic_slot;
logic [5:0] dynamic_index;
logic [3:0] static_line;
logic [5:0] static_index;
logic [7:0] row;

always_comb begin
    glyph_valid = 1'b0;
    glyph_character = " ";
    glyph_x = 0;
    glyph_y = 0;
    glyph_color = 24'he8f0ec;
    dynamic_text = 1'b0;
    char_mode = 0;
    dynamic_slot = 0;
    dynamic_index = 0;
    static_line = 0;
    static_index = 0;
    row = 0;

    if (visible && track_count != 0) begin
        // Text-zone coordinates, lengths, and scroll were resolved one cycle
        // earlier.  This stage contains only small adds, compares, and selects.
        case (text_zone_q)
            TEXT_PHOSPHOR: begin
                static_line = 0; static_index = text_local_x_q[9:4];
                glyph_valid = static_index < 8;
            end
            TEXT_PLAYLIST_LABEL: begin
                static_line = 3; static_index = text_local_x_q[9:4];
                glyph_valid = static_index < 16;
            end
            TEXT_ALBUM, TEXT_ARTIST, TEXT_TRACK: begin
                dynamic_slot = text_zone_q == TEXT_ALBUM ? 4'd0 :
                               text_zone_q == TEXT_ARTIST ? 4'd1 : 4'd2;
                dynamic_index = text_local_x_q[9:4] + text_scroll_q;
                glyph_valid = text_local_x_q[9:4] < 18 &&
                              {2'b0, dynamic_index} < text_length_q;
                dynamic_text = glyph_valid;
            end
            TEXT_ROW_0, TEXT_ROW_1, TEXT_ROW_2, TEXT_ROW_3,
            TEXT_ROW_4, TEXT_ROW_5: begin
                row = {3'b0, text_zone_q} - {3'b0, TEXT_ROW_0};
                dynamic_slot = {1'b0, row[2:0]} + 4'd3;
                dynamic_index = text_local_x_q[9:4];
                glyph_valid = {2'b0, dynamic_index} < text_length_q;
                dynamic_text = glyph_valid;
                glyph_color = text_row_selected_q ? 24'hf2fff8 : 24'h789488;
            end
            TEXT_ELAPSED: begin
                static_index = text_local_x_q[9:4]; glyph_valid = static_index < 8;
                glyph_character = time_glyph(elapsed_digits, static_index[3:0]);
                char_mode = 1;
            end
            TEXT_DURATION: begin
                static_index = text_local_x_q[9:4]; glyph_valid = static_index < 8;
                glyph_character = time_glyph(duration_digits, static_index[3:0]);
                char_mode = 1;
            end
            default: ;
        endcase

        if (dynamic_text) begin
            char_mode = 2;
        end else if (glyph_valid && char_mode == 0) begin
            char_mode = 3;
        end

        if (glyph_valid) begin
            glyph_x = text_local_x_q[3:1];
            glyph_y = text_local_y_q[4:1];
            if (glyph_y > 7)
                glyph_valid = 1'b0;
        end
    end
end

logic [23:0] base_rgb_q;
logic [23:0] base_rgb_qq;
logic [23:0] glyph_color_q;
logic [23:0] glyph_color_qq;
logic [2:0] glyph_x_q;
logic [2:0] glyph_x_qq;
logic [3:0] glyph_y_q;
logic [3:0] glyph_y_qq;
logic [3:0] glyph_y_qqq;
logic [7:0] glyph_character_q;
logic glyph_valid_q;
logic glyph_valid_qq;
logic [1:0] char_mode_q;
logic [1:0] char_mode_qq;
logic [1:0] char_mode_qqq;
logic [3:0] static_line_q;
logic [3:0] static_line_qq;
logic [3:0] static_line_qqq;
logic [5:0] static_index_q;
logic [5:0] static_index_qq;
logic [5:0] static_index_qqq;
logic [7:0] direct_character_q;
logic [7:0] direct_character_qq;
logic [7:0] direct_character_qqq;
logic [3:0] dynamic_slot_q;
logic [5:0] dynamic_index_q;
logic [23:0] base_rgb_qqq;
logic [23:0] base_rgb_qqqq;
logic [23:0] base_rgb_qqqqq;
logic [23:0] glyph_color_qqq;
logic [23:0] glyph_color_qqqq;
logic [23:0] glyph_color_qqqqq;
logic [2:0] glyph_x_qqq;
logic [2:0] glyph_x_qqqq;
logic [2:0] glyph_x_qqqqq;
logic glyph_valid_qqq;
logic glyph_valid_qqqq;
logic glyph_valid_qqqqq;

wire [10:0] font_address = {1'b1, glyph_character_q[6:0], glyph_y_qqq[2:0]};
wire [7:0] font_bits;

`ifdef SIM
// Keep most simulated glyphs solid for simple color tests, but make P
// asymmetric so the regression can verify the production ROM bit order.
assign font_bits = glyph_character_q == " " ? 8'h00 :
                   glyph_character_q == "P" ? 8'h01 : 8'hff;
`else
wire [7:0] unused_font_a;
gowin_dpb_menu ui_font_rom (
    .clka(clk), .reseta(1'b0), .ocea(1'b0), .cea(1'b0),
    .ada(11'b0), .wrea(1'b0), .dina(8'b0), .douta(unused_font_a),
    .clkb(clk), .resetb(1'b0), .oceb(1'b1), .ceb(1'b1),
    .adb(font_address), .wreb(1'b0), .dinb(8'b0), .doutb(font_bits)
);
`endif

always_ff @(posedge clk) begin
    if (!resetn) begin
        base_rgb_q <= 0;
        base_rgb_qq <= 0;
        glyph_color_q <= 0;
        glyph_color_qq <= 0;
        glyph_x_q <= 0;
        glyph_x_qq <= 0;
        glyph_x_qqq <= 0;
        glyph_x_qqqq <= 0;
        glyph_x_qqqqq <= 0;
        glyph_y_q <= 0;
        glyph_y_qq <= 0;
        glyph_y_qqq <= 0;
        glyph_character_q <= " ";
        glyph_valid_q <= 0;
        glyph_valid_qq <= 0;
        glyph_valid_qqq <= 0;
        glyph_valid_qqqq <= 0;
        glyph_valid_qqqqq <= 0;
        char_mode_q <= 0;
        char_mode_qq <= 0;
        char_mode_qqq <= 0;
        static_line_q <= 0;
        static_line_qq <= 0;
        static_line_qqq <= 0;
        static_index_q <= 0;
        static_index_qq <= 0;
        static_index_qqq <= 0;
        direct_character_q <= " ";
        direct_character_qq <= " ";
        direct_character_qqq <= " ";
        dynamic_slot_q <= 0;
        dynamic_index_q <= 0;
        text_address <= 0;
        base_rgb_qqq <= 0;
        base_rgb_qqqq <= 0;
        base_rgb_qqqqq <= 0;
        glyph_color_qqq <= 0;
        glyph_color_qqqq <= 0;
        glyph_color_qqqqq <= 0;
        rgb_out <= 0;
    end else begin
        base_rgb_q <= base_rgb;
        base_rgb_qq <= base_rgb_q;
        base_rgb_qqq <= artwork_pixel_qqq ?
            {{artwork_data[7:5], artwork_data[7:5], artwork_data[7:6]},
             {artwork_data[4:2], artwork_data[4:2], artwork_data[4:3]},
             {artwork_data[1:0], artwork_data[1:0], artwork_data[1:0],
              artwork_data[1:0]}} : base_rgb_qq;
        base_rgb_qqqq <= base_rgb_qqq;
        base_rgb_qqqqq <= base_rgb_qqqq;
        glyph_color_q <= glyph_color;
        glyph_color_qq <= glyph_color_q;
        glyph_color_qqq <= glyph_color_qq;
        glyph_color_qqqq <= glyph_color_qqq;
        glyph_color_qqqqq <= glyph_color_qqqq;
        glyph_x_q <= glyph_x;
        glyph_x_qq <= glyph_x_q;
        glyph_x_qqq <= glyph_x_qq;
        glyph_x_qqqq <= glyph_x_qqq;
        glyph_x_qqqqq <= glyph_x_qqqq;
        glyph_y_q <= glyph_y;
        glyph_y_qq <= glyph_y_q;
        glyph_y_qqq <= glyph_y_qq;
        case (char_mode_qqq)
            1: glyph_character_q <= direct_character_qqq;
            2: glyph_character_q <= text_data;
            3: glyph_character_q <= static_glyph(static_line_qqq, static_index_qqq);
            default: glyph_character_q <= " ";
        endcase
        glyph_valid_q <= glyph_valid;
        glyph_valid_qq <= glyph_valid_q;
        glyph_valid_qqq <= glyph_valid_qq;
        glyph_valid_qqqq <= glyph_valid_qqq;
        glyph_valid_qqqqq <= glyph_valid_qqqq;
        char_mode_q <= char_mode;
        char_mode_qq <= char_mode_q;
        char_mode_qqq <= char_mode_qq;
        static_line_q <= static_line;
        static_line_qq <= static_line_q;
        static_line_qqq <= static_line_qq;
        static_index_q <= static_index;
        static_index_qq <= static_index_q;
        static_index_qqq <= static_index_qq;
        direct_character_q <= glyph_character;
        direct_character_qq <= direct_character_q;
        direct_character_qqq <= direct_character_qq;
        dynamic_slot_q <= dynamic_slot;
        dynamic_index_q <= dynamic_index;
        text_address <= {dynamic_slot_q, 5'b0} + {3'b0, dynamic_index_q};
        // The shared TangCore font ROM stores the leftmost pixel in bit 0.
        rgb_out <= glyph_valid_qqqqq && font_bits[glyph_x_qqqqq] ?
            glyph_color_qqqqq : base_rgb_qqqqq;
    end
end

endmodule
