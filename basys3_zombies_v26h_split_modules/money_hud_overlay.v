// ============================================================================
// FOUR-DIGIT SCREEN MONEY HUD
//
// 4 x seven-segment-style glyphs at upper-left, no division/modulo and no
// multiplication. Leading zeroes are intentionally shown (0000..9999).
// ============================================================================
module money_hud_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,

    input  wire [3:0] digit_thousands,
    input  wire [3:0] digit_hundreds,
    input  wire [3:0] digit_tens,
    input  wire [3:0] digit_ones,

    output reg        money_pixel
);

    reg [3:0] digit_value;
    reg [4:0] local_x;
    reg [4:0] local_y;
    reg       inside_digit;
    reg [6:0] segments;

    function [6:0] digit_segments;
        input [3:0] d;
        begin
            // bits: a b c d e f g
            case (d)
                4'd0: digit_segments = 7'b1111110;
                4'd1: digit_segments = 7'b0110000;
                4'd2: digit_segments = 7'b1101101;
                4'd3: digit_segments = 7'b1111001;
                4'd4: digit_segments = 7'b0110011;
                4'd5: digit_segments = 7'b1011011;
                4'd6: digit_segments = 7'b1011111;
                4'd7: digit_segments = 7'b1110000;
                4'd8: digit_segments = 7'b1111111;
                4'd9: digit_segments = 7'b1111011;
                default: digit_segments = 7'b0000000;
            endcase
        end
    endfunction

    always @(*) begin
        inside_digit = 1'b1;
        digit_value  = 4'd0;
        local_x      = 5'd0;
        local_y      = 5'd0;
        money_pixel  = 1'b0;

        // Each digit is 12x22 with 4 pixels of spacing.
        // Overall HUD begins at x=12, y=14.
        if ((pixel_y >= 10'd14) && (pixel_y < 10'd36)) begin
            local_y = pixel_y - 10'd14;

            if ((pixel_x >= 10'd12) && (pixel_x < 10'd24)) begin
                digit_value = digit_thousands;
                local_x = pixel_x - 10'd12;
            end
            else if ((pixel_x >= 10'd28) && (pixel_x < 10'd40)) begin
                digit_value = digit_hundreds;
                local_x = pixel_x - 10'd28;
            end
            else if ((pixel_x >= 10'd44) && (pixel_x < 10'd56)) begin
                digit_value = digit_tens;
                local_x = pixel_x - 10'd44;
            end
            else if ((pixel_x >= 10'd60) && (pixel_x < 10'd72)) begin
                digit_value = digit_ones;
                local_x = pixel_x - 10'd60;
            end
            else begin
                inside_digit = 1'b0;
            end
        end
        else begin
            inside_digit = 1'b0;
        end

        segments = digit_segments(digit_value);

        if (inside_digit) begin
            // 2-pixel-thick seven-segment strokes.
            // a
            if (segments[6] && (local_y <= 5'd1) &&
                (local_x >= 5'd2) && (local_x <= 5'd9))
                money_pixel = 1'b1;
            // b
            if (segments[5] && (local_x >= 5'd10) &&
                (local_y >= 5'd2) && (local_y <= 5'd9))
                money_pixel = 1'b1;
            // c
            if (segments[4] && (local_x >= 5'd10) &&
                (local_y >= 5'd12) && (local_y <= 5'd19))
                money_pixel = 1'b1;
            // d
            if (segments[3] && (local_y >= 5'd20) &&
                (local_x >= 5'd2) && (local_x <= 5'd9))
                money_pixel = 1'b1;
            // e
            if (segments[2] && (local_x <= 5'd1) &&
                (local_y >= 5'd12) && (local_y <= 5'd19))
                money_pixel = 1'b1;
            // f
            if (segments[1] && (local_x <= 5'd1) &&
                (local_y >= 5'd2) && (local_y <= 5'd9))
                money_pixel = 1'b1;
            // g
            if (segments[0] && (local_y >= 5'd10) && (local_y <= 5'd11) &&
                (local_x >= 5'd2) && (local_x <= 5'd9))
                money_pixel = 1'b1;
        end
    end

endmodule
