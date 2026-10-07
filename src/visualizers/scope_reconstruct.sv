// SPDX-License-Identifier: GPL-3.0-only
// 2x, 15-tap half-band reconstruction of the visual observation only.
// Coefficients match the MiSTer behavioral reference. A captured pair and
// seven-sample history feed a shared multiplier; audio never waits for it.
module scope_reconstruct (
    input logic clk, reset, sample_valid,
    input logic signed [15:0] left_in, right_in,
    output logic point_valid,
    output logic signed [15:0] left_out, right_out
);
    logic signed [15:0] h_l[0:7], h_r[0:7];
    logic [3:0] state;
    logic signed [35:0] acc_l, acc_r;
    logic signed [16:0] pair;
    logic signed [15:0] coefficient;
    logic signed [32:0] product;
    assign product = pair * coefficient;
    always_comb begin
        pair = 0; coefficient = 0;
        case (state)
            1: begin pair = 17'(h_l[0])+17'(h_l[7]); coefficient = -240; end
            2: begin pair = 17'(h_l[1])+17'(h_l[6]); coefficient = 1064; end
            3: begin pair = 17'(h_l[2])+17'(h_l[5]); coefficient = -4500; end
            4: begin pair = 17'(h_l[3])+17'(h_l[4]); coefficient = 20060; end
            5: begin pair = 17'(h_r[0])+17'(h_r[7]); coefficient = -240; end
            6: begin pair = 17'(h_r[1])+17'(h_r[6]); coefficient = 1064; end
            7: begin pair = 17'(h_r[2])+17'(h_r[5]); coefficient = -4500; end
            8: begin pair = 17'(h_r[3])+17'(h_r[4]); coefficient = 20060; end
            default: begin end
        endcase
    end
    function automatic signed [15:0] rounded(input logic signed [35:0] v);
        logic signed [35:0] r;
        begin
            // Round to nearest, ties away from zero, without negative bias.
            r = v + (v < 0 ? 36'sd16383 : 36'sd16384);
            r = r >>> 15;
            if (r > 32767) rounded = 16'sh7fff;
            else if (r < -32768) rounded = 16'sh8000;
            else rounded = 16'(r);
        end
    endfunction
    always_ff @(posedge clk) begin
        point_valid <= 0;
        if (reset) begin
            state <= 0; acc_l <= 0; acc_r <= 0;
            left_out <= 0; right_out <= 0;
            for (integer i=0;i<8;i++) begin h_l[i]<=0; h_r[i]<=0; end
        end else begin
            case (state)
                0: if (sample_valid) begin
                    for (integer i=7;i>0;i--) begin h_l[i]<=h_l[i-1]; h_r[i]<=h_r[i-1]; end
                    h_l[0]<=left_in; h_r[0]<=right_in; state<=1;
                end
                1,2,3,4: begin
                    acc_l <= state==1 ? 36'(product) : acc_l+36'(product);
                    state<=state+1'b1;
                end
                5,6,7,8: begin
                    acc_r <= state==5 ? 36'(product) : acc_r+36'(product);
                    state<=state+1'b1;
                end
                9: begin
                    left_out<=rounded(acc_l); right_out<=rounded(acc_r);
                    point_valid<=1; state<=10;
                end
                10: begin
                    left_out<=h_l[3]; right_out<=h_r[3];
                    point_valid<=1; state<=0;
                end
                default: state<=0;
            endcase
        end
    end
endmodule
