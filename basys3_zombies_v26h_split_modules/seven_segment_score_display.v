// ============================================================================
// BASYS 3 FOUR-DIGIT SEVEN-SEGMENT DISPLAY
// Left two digits = left_value, right two digits = right_value.
// seg/an/dp are active-low on Basys 3.
// ============================================================================
module seven_segment_score_display (
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire       enable,
    input  wire [6:0] left_value,
    input  wire [6:0] right_value,
    output reg  [6:0] seg,
    output reg  [3:0] an,
    output reg        dp
);

    reg [17:0] refresh_counter;
    wire [1:0] digit_select = refresh_counter[17:16];

    reg [3:0] digit_value;
    reg [3:0] left_tens, left_ones, right_tens, right_ones;

    function [6:0] encode_digit;
        input [3:0] d;
        begin
            case (d)
                4'd0: encode_digit = 7'b1000000;
                4'd1: encode_digit = 7'b1111001;
                4'd2: encode_digit = 7'b0100100;
                4'd3: encode_digit = 7'b0110000;
                4'd4: encode_digit = 7'b0011001;
                4'd5: encode_digit = 7'b0010010;
                4'd6: encode_digit = 7'b0000010;
                4'd7: encode_digit = 7'b1111000;
                4'd8: encode_digit = 7'b0000000;
                4'd9: encode_digit = 7'b0010000;
                default: encode_digit = 7'b1111111;
            endcase
        end
    endfunction

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset)
            refresh_counter <= 18'd0;
        else
            refresh_counter <= refresh_counter + 18'd1;
    end

    always @(*) begin
        left_tens  = (left_value  > 7'd99) ? 4'd9 : left_value / 10;
        left_ones  = (left_value  > 7'd99) ? 4'd9 : left_value % 10;
        right_tens = (right_value > 7'd99) ? 4'd9 : right_value / 10;
        right_ones = (right_value > 7'd99) ? 4'd9 : right_value % 10;

        seg = 7'b1111111;
        an  = 4'b1111;
        dp  = 1'b1;
        digit_value = 4'd0;

        if (enable) begin
            case (digit_select)
                2'd0: begin
                    an = 4'b1110; // rightmost
                    digit_value = right_ones;
                end
                2'd1: begin
                    an = 4'b1101;
                    digit_value = right_tens;
                end
                2'd2: begin
                    an = 4'b1011;
                    digit_value = left_ones;
                end
                2'd3: begin
                    an = 4'b0111; // leftmost
                    digit_value = left_tens;
                end
            endcase
            seg = encode_digit(digit_value);
        end
    end

endmodule
