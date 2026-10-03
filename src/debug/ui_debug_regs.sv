// SPDX-License-Identifier: GPL-3.0-only
//
// The mirror core's debug register bank.
//
// The BL616 transport only moves generic 32-bit transactions; the meanings stay
// here, in the project.  This is the mirror core's counterpart to the player's
// src/debug/debug_regs.sv and is deliberately separate: sharing one bank would
// couple two very different register sets.
//
// Two registers are writable and one of them is the point of the exercise:
//
//   0x10  control   bit 0     hold the renderer on the frame it has just drawn
//                   bits 4-7  PMOD0 personality
//                   bits 8-11 PMOD1 personality
//                   bit 12    PMOD0 seated upside down
//                   bit 13    PMOD1 seated upside down
//
//   0x14  scratch   read back what was written, for link testing
//
// Writing the control register is what turns /tang.ini from a document into a
// mechanism: the socket personalities and the seating orientation stop being
// build-time parameters and become declarations the host sends after reading
// the file.  Nothing here validates them; validation is the host's job, since
// the host is the only party that knows what the user wrote.

module ui_debug_regs (
    input  logic        clk,
    input  logic        resetn,

    input  logic        request_valid,
    input  logic        request_write,
    input  logic [31:0] request_address,
    input  logic [31:0] request_wdata,
    output logic [31:0] request_rdata,

    // Observed state.
    input  logic [31:0] uptime_cycles,
    input  logic [31:0] render_frames,
    input  logic [2:0]  pattern,
    input  logic        source_bank,
    input  logic [31:0] source_crc,
    input  logic [31:0] oled_frames,
    input  logic [31:0] oled_crc,
    input  logic [31:0] hdmi_frames,
    input  logic [31:0] hdmi_crc,
    input  logic [31:0] vga_frames,
    input  logic [31:0] vga_crc,

    // Declared configuration, out to the socket layer.
    output logic [3:0]  pmod0_personality,
    output logic [3:0]  pmod1_personality,
    output logic        pmod0_flipped,
    output logic        pmod1_flipped,
    output logic        hold
);
    localparam [31:0] MAGIC      = 32'h5450_4830;   // "TPH0"
    localparam [31:0] BUILD_DATE = 32'h2026_1002;

    // Power-on defaults: nothing selected anywhere, which is the safe state
    // when a module may be seated that has not been declared yet.
    localparam [3:0]  PERS_POR  = 4'd1;     // oledrgb on PMOD0, as before
    localparam [3:0]  PERS_POR1 = 4'd0;     // nothing on PMOD1

    logic [31:0] scratch;
    logic [31:0] rdata_q;

    always_ff @(posedge clk) begin
        if (!resetn) begin
            pmod0_personality <= PERS_POR;
            pmod1_personality <= PERS_POR1;
            pmod0_flipped     <= 1'b0;
            pmod1_flipped     <= 1'b0;
            hold              <= 1'b0;
            scratch           <= 32'd0;
        end else if (request_valid && request_write) begin
            case (request_address[7:2])
                6'h04: begin                       // 0x10 control
                    hold              <= request_wdata[0];
                    pmod0_personality <= request_wdata[7:4];
                    pmod1_personality <= request_wdata[11:8];
                    pmod0_flipped     <= request_wdata[12];
                    pmod1_flipped     <= request_wdata[13];
                end
                6'h05: scratch <= request_wdata;   // 0x14 scratch
                default: ;
            endcase
        end
    end

    // Registered read multiplexer: the transport samples this several byte
    // times after it sets the address, so a registered response is required
    // rather than merely convenient.
    always_ff @(posedge clk) begin
        if (!resetn)
            rdata_q <= 32'd0;
        else begin
            case (request_address[7:2])
                6'h00: rdata_q <= MAGIC;
                6'h01: rdata_q <= BUILD_DATE;
                6'h02: rdata_q <= uptime_cycles;
                6'h03: rdata_q <= render_frames;
                // Reads back in the same layout it is written in, so a host
                // that echoes the register sees what it sent: hold at bit 0,
                // personalities at 7:4 and 11:8, flips at 12 and 13.  The
                // pattern sits above them at 18:16.  An earlier version packed
                // hold at bit 3, which is how the mirror check managed to read
                // a pattern bit as "held" on its first run.
                6'h04: rdata_q <= {13'b0, pattern, 2'b0,
                                   pmod1_flipped, pmod0_flipped,
                                   pmod1_personality, pmod0_personality,
                                   3'b0, hold};
                6'h05: rdata_q <= scratch;
                6'h06: rdata_q <= {31'b0, source_bank};
                6'h07: rdata_q <= source_crc;
                6'h08: rdata_q <= oled_frames;
                6'h09: rdata_q <= oled_crc;
                6'h0a: rdata_q <= hdmi_frames;
                6'h0b: rdata_q <= hdmi_crc;
                6'h0c: rdata_q <= vga_frames;
                6'h0d: rdata_q <= vga_crc;
                default: rdata_q <= 32'd0;
            endcase
        end
    end

    assign request_rdata = rdata_q;
endmodule
