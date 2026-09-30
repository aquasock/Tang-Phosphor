// SPDX-License-Identifier: GPL-3.0-only
//
// AE350 boot ROM on the ROM AHB port (reset vector 0x80000000), in block
// RAM initialized from INIT_FILE: one 32-bit little-endian word per line in
// hex, as written by software/ae350/Makefile.  The address is registered
// and the port inserts one wait state per access, so no path runs from the
// AE350 macro into the RAM.  Addresses alias every WORDS words.

module ae350_boot_rom #(
    parameter int    WORDS     = 2048,
    parameter string INIT_FILE = "ae350_boot.hex"
) (
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] haddr,
    input  logic [1:0]  htrans,
    output logic [31:0] hrdata,
    output logic        hready
);

    localparam int ADDR_BITS = $clog2(WORDS);

    (* syn_ramstyle = "block_ram" *) logic [31:0] rom [0:WORDS-1];
    initial $readmemh(INIT_FILE, rom);

    logic [ADDR_BITS-1:0] address;
    logic                 pending;

    always_ff @(posedge clk)
        hrdata <= rom[address];

    always_ff @(posedge clk) begin
        if (hready && htrans[1]) begin
            address <= haddr[ADDR_BITS+1:2];
            pending <= 1'b1;
            hready  <= 1'b0;
        end
        if (pending) begin
            pending <= 1'b0;
            hready  <= 1'b1;
        end
        if (rst) begin
            pending <= 1'b0;
            hready  <= 1'b1;
        end
    end

endmodule
