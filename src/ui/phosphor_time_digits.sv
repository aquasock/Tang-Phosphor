// Convert bounded seconds to HH:MM:SS without a combinational divider. A new
// value completes in at most 160 clocks, far below one 720p frame interval.

module phosphor_time_digits (
    input  logic        clk,
    input  logic        resetn,
    input  logic [31:0] seconds_value,
    output logic [23:0] digits
);

localparam logic [1:0] IDLE = 0, HOURS = 1, MINUTES = 2;
logic [1:0] state;
logic [31:0] captured;
logic [18:0] remainder;
logic [6:0] hours;
logic [5:0] minutes;

function automatic [3:0] decimal_tens(input logic [6:0] value);
begin
    if (value >= 90) decimal_tens = 9;
    else if (value >= 80) decimal_tens = 8;
    else if (value >= 70) decimal_tens = 7;
    else if (value >= 60) decimal_tens = 6;
    else if (value >= 50) decimal_tens = 5;
    else if (value >= 40) decimal_tens = 4;
    else if (value >= 30) decimal_tens = 3;
    else if (value >= 20) decimal_tens = 2;
    else if (value >= 10) decimal_tens = 1;
    else decimal_tens = 0;
end
endfunction

function automatic [3:0] decimal_ones(input logic [6:0] value);
    logic [3:0] tens;
    logic [6:0] tens_wide;
    logic [6:0] remainder_digit;
begin
    tens = decimal_tens(value);
    tens_wide = {3'b0, tens};
    remainder_digit = value - (tens_wide << 3) - (tens_wide << 1);
    decimal_ones = remainder_digit[3:0];
end
endfunction

always_ff @(posedge clk) begin
    if (!resetn) begin
        state <= IDLE;
        captured <= 0;
        remainder <= 0;
        hours <= 0;
        minutes <= 0;
        digits <= 0;
    end else case (state)
        IDLE: if (captured != seconds_value) begin
            captured <= seconds_value;
            remainder <= seconds_value > 32'd359999 ? 19'd359999 : seconds_value[18:0];
            hours <= 0;
            minutes <= 0;
            state <= HOURS;
        end
        HOURS: begin
            if (remainder >= 3600) begin
                remainder <= remainder - 3600;
                hours <= hours + 1'b1;
            end else begin
                state <= MINUTES;
            end
        end
        MINUTES: begin
            if (remainder >= 60) begin
                remainder <= remainder - 60;
                minutes <= minutes + 1'b1;
            end else begin
                digits <= {
                    decimal_tens(hours), decimal_ones(hours),
                    decimal_tens({1'b0, minutes}), decimal_ones({1'b0, minutes}),
                    decimal_tens(remainder[6:0]), decimal_ones(remainder[6:0])
                };
                state <= IDLE;
            end
        end
        default: state <= IDLE;
    endcase
end

endmodule
