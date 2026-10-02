// SPDX-License-Identifier: GPL-3.0-only
//
// Pmod OLEDrgb bring-up core.
//
// A deliberately standalone experiment: it instantiates neither the player nor
// the AE350 nor the transport.  The panel protocol lives in oled_panel; this
// top supplies the pixels from a built-in pattern generator so the panel, its
// colour order and the whole PMOD path can still be judged by eye on their
// own, without the frame store or the socket layer.
//
// The module sits on PMOD0, the socket furthest from the HDMI port.  Every
// OLEDrgb signal is a host-driven input, so a mis-seated module cannot drive
// against these outputs.
//
// Patterns, each held about a second:
//   0 red   1 green   2 blue   3 white   4 black
//   5 eight vertical colour bars
//   6 red/green ramp across the panel

module oled_pmod_top (
    input  logic sys_clk,       // 50 MHz board clock

    output logic oled_cs_n,
    output logic oled_mosi,
    output logic oled_sck,
    output logic oled_dc,
    output logic oled_res_n,
    output logic oled_vccen,
    output logic oled_pmoden
);
    // Frames each pattern is held: 64 panel frames is about a second.
    localparam [7:0] HOLD_FRAMES = 8'd63;

    // ------------------------------------------------------------------
    // Power-on reset.
    // ------------------------------------------------------------------
    logic [15:0] por_cnt = 16'd0;
    logic        rst     = 1'b1;

    always_ff @(posedge sys_clk) begin
        if (por_cnt != 16'hFFFF)
            por_cnt <= por_cnt + 16'd1;
        else
            rst <= 1'b0;
    end

    // ------------------------------------------------------------------
    // Built-in pattern source, RGB565.
    // ------------------------------------------------------------------
    function automatic logic [15:0] pattern_pixel(
        input logic [6:0] px,
        input logic [5:0] py,
        input logic [2:0] p
    );
        case (p)
            3'd0: pattern_pixel = 16'hF800;                 // red
            3'd1: pattern_pixel = 16'h07E0;                 // green
            3'd2: pattern_pixel = 16'h001F;                 // blue
            3'd3: pattern_pixel = 16'hFFFF;                 // white
            3'd4: pattern_pixel = 16'h0000;                 // black
            3'd5: begin                                     // eight 12 px bars
                case (px / 7'd12)
                    7'd0: pattern_pixel = 16'hF800;         // red
                    7'd1: pattern_pixel = 16'h07E0;         // green
                    7'd2: pattern_pixel = 16'h001F;         // blue
                    7'd3: pattern_pixel = 16'h07FF;         // cyan
                    7'd4: pattern_pixel = 16'hF81F;         // magenta
                    7'd5: pattern_pixel = 16'hFFE0;         // yellow
                    7'd6: pattern_pixel = 16'hFFFF;         // white
                    default: pattern_pixel = 16'h0000;      // black
                endcase
            end
            default: pattern_pixel = {px[6:2], py[5:0], py[5:1]};
        endcase
    endfunction

    logic [6:0]  px_x;
    logic [5:0]  px_y;
    logic [15:0] px_data;
    logic [2:0]  pat  = 3'd0;
    logic [7:0]  fcnt = 8'd0;
    logic        frame_start;

    always_comb px_data = pattern_pixel(px_x, px_y, pat);

    always_ff @(posedge sys_clk) begin
        if (rst) begin
            pat  <= 3'd0;
            fcnt <= 8'd0;
        end else if (frame_start) begin
            if (fcnt == HOLD_FRAMES) begin
                fcnt <= 8'd0;
                pat  <= (pat == 3'd6) ? 3'd0 : pat + 3'd1;
            end else begin
                fcnt <= fcnt + 8'd1;
            end
        end
    end

    oled_panel #(.CLK_MHZ(50)) panel (
        .clk         (sys_clk),
        .rst         (rst),
        .px_x        (px_x),
        .px_y        (px_y),
        .px_data     (px_data),
        .cs_n        (oled_cs_n),
        .mosi        (oled_mosi),
        .sck         (oled_sck),
        .dc          (oled_dc),
        .res_n       (oled_res_n),
        .vccen       (oled_vccen),
        .pmoden      (oled_pmoden),
        .frame_start (frame_start)
    );
endmodule
