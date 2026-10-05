`timescale 1ns/1ps

// Pixel-exact check of the TinyTang desktop layer against a model of the
// 80x45 cell grid: every visible pixel of two whole frames, with the raster
// wrapping at line and frame ends the way hdmi.sv produces it, then the
// overlay and layer enables, which must hand the picture back untouched.
module ui_desk_layer_tb;

`include "font.vh"

localparam integer FRAME_W = 1650;
localparam integer FRAME_H = 750;

reg clk = 0;
always #5 clk = ~clk;

reg [10:0] cx = 0;
reg [9:0]  cy = 0;
reg        run = 0;
reg        we = 0;
reg [6:0]  wx = 0;
reg [5:0]  wy = 0;
reg [6:0]  wch = 0;
reg [14:0] wfg = 0;
reg [14:0] wbg = 0;
reg        overlay = 0;
reg        layer_on = 0;
wire [23:0] picture_rgb = {cx[7:0], cy[7:0], 8'h5a};
wire [23:0] rgb;

ui_desk_layer dut (
    .clk(clk), .cx(cx), .cy(cy),
    .frame_width(11'(FRAME_W)), .frame_height(10'(FRAME_H)),
    .we(we), .wx(wx), .wy(wy), .wch(wch), .wfg(wfg), .wbg(wbg),
    .overlay(overlay), .layer_on(layer_on),
    .picture_rgb(picture_rgb), .rgb(rgb)
);

always @(posedge clk)
    if (run) begin
        if (cx == FRAME_W - 1) begin
            cx <= 0;
            cy <= cy == FRAME_H - 1 ? 0 : cy + 1;
        end else
            cx <= cx + 1;
    end

function automatic [6:0] cell_ch(input integer x, input integer y);
    cell_ch = 7'((x * 7 + y * 13 + 1) % 128);
endfunction
function automatic [14:0] cell_fg(input integer x, input integer y);
    cell_fg = 15'((x * 911 + y * 37 + 5) | 15'h4210);
endfunction
function automatic [14:0] cell_bg(input integer x, input integer y);
    cell_bg = 15'((x * 53 + y * 1291) & 15'h3def);
endfunction

function automatic [23:0] expand(input [14:0] c);
    expand = {c[4:0], 3'b000, c[9:5], 3'b000, c[14:10], 3'b000};
endfunction

function automatic [23:0] model(input integer px, input integer py);
    integer x, y;
    reg [7:0] glyph_row;
    begin
        x = px / 16;
        y = py / 16;
        glyph_row = FONT[cell_ch(x, y)][(py >> 1) & 7];
        model = expand(glyph_row[(px >> 1) & 7] ? cell_fg(x, y) : cell_bg(x, y));
    end
endfunction

integer x, y, frames, checked, errors;

// rgb is combinational on the raster: the colour beside (cx, cy) must be the
// pixel for (cx, cy), sampled between edges.
always @(negedge clk)
    if (run && overlay && layer_on && cx < 1280 && cy < 720) begin
        checked = checked + 1;
        if (rgb !== model(cx, cy)) begin
            errors = errors + 1;
            if (errors <= 8)
                $display("FAIL pixel (%0d,%0d) got %06x expected %06x",
                         cx, cy, rgb, model(cx, cy));
        end
    end

always @(negedge clk)
    if (run && !(overlay && layer_on) && rgb !== picture_rgb) begin
        errors = errors + 1;
        if (errors <= 8)
            $display("FAIL picture not passed through at (%0d,%0d)", cx, cy);
    end

initial begin
    checked = 0;
    errors = 0;
    for (y = 0; y < 45; y = y + 1)
        for (x = 0; x < 80; x = x + 1) begin
            @(negedge clk);
            we = 1; wx = x; wy = y;
            wch = cell_ch(x, y); wfg = cell_fg(x, y); wbg = cell_bg(x, y);
        end
    @(negedge clk);
    we = 0;

    overlay = 1;
    layer_on = 1;
    run = 1;
    for (frames = 0; frames < 2; frames = frames + 1)
        repeat (FRAME_W * FRAME_H) @(posedge clk);
    if (checked !== 2 * 1280 * 720)
        $fatal(1, "FAIL checked %0d pixels", checked);

    // Either enable alone hands the picture back, mid-frame included.
    repeat (FRAME_W * 100 + 333) @(posedge clk);
    @(negedge clk) overlay = 0;
    repeat (FRAME_W * 3) @(posedge clk);
    @(negedge clk) begin overlay = 1; layer_on = 0; end
    repeat (FRAME_W * 3) @(posedge clk);
    @(negedge clk) layer_on = 1;
    repeat (FRAME_W * 3) @(posedge clk);

    if (errors != 0)
        $fatal(1, "FAIL %0d mismatches", errors);
    $display("PASS ui_desk_layer: %0d pixels match the cell model, enables pass the picture through", checked);
    $finish;
end

endmodule
