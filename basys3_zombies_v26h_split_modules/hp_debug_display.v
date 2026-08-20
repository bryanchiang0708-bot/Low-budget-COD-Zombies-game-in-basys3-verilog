// ============================================================================
// TINY HP DEBUG DISPLAY
//
// leftmost digit  = zombie HP
// rightmost digit = player HP
// middle digits are blank.
// No division/modulo arithmetic.
// ============================================================================
module hp_debug_display (
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire [3:0] zombie_hp,
    input  wire [2:0] player_hp,
    output reg  [6:0] seg,
    output reg  [3:0] an,
    output reg        dp
);

    reg [17:0] refresh_counter;
    wire [1:0] digit_select = refresh_counter[17:16];

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
                4'd9:  encode_digit = 7'b0010000;
                4'd10: encode_digit = 7'b0001000; // A = 10 HP debug
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
        seg = 7'b1111111;
        an  = 4'b1111;
        dp  = 1'b1;

        case (digit_select)
            2'd0: begin
                an  = 4'b1110;
                seg = encode_digit({1'b0, player_hp});
            end

            2'd3: begin
                an  = 4'b0111;
                seg = encode_digit(zombie_hp);
            end

            default: begin
                an  = 4'b1111;
                seg = 7'b1111111;
            end
        endcase
    end

endmodule
