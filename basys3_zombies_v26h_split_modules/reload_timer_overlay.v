// ============================================================================
// V23 RELOAD COUNTDOWN UNDER CROSSHAIR
//
// tenths_remaining:
//   pistol  starts at 12 -> 1.2
//   shotgun starts at 20 -> 2.0
//   rifle   starts at 18 -> 1.8
//
// Draws one whole digit, decimal point, and one tenths digit.
// ============================================================================
module reload_timer_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire       reload_active,
    input  wire [4:0] tenths_remaining,
    output reg        reload_pixel
);
    reg [3:0] whole_digit;
    reg [3:0] decimal_digit;
    reg [6:0] segments;
    reg [3:0] lx;
    reg [3:0] ly;
    reg       inside;
    reg [3:0] digit;

    function [6:0] digit_segments;
        input [3:0] d;
        begin
            case(d)
                0:digit_segments=7'b1111110;
                1:digit_segments=7'b0110000;
                2:digit_segments=7'b1101101;
                3:digit_segments=7'b1111001;
                4:digit_segments=7'b0110011;
                5:digit_segments=7'b1011011;
                6:digit_segments=7'b1011111;
                7:digit_segments=7'b1110000;
                8:digit_segments=7'b1111111;
                9:digit_segments=7'b1111011;
                default:digit_segments=7'b0000000;
            endcase
        end
    endfunction

    always @(*) begin
        if (tenths_remaining >= 5'd20) begin
            whole_digit = 4'd2;
            decimal_digit = tenths_remaining - 5'd20;
        end
        else if (tenths_remaining >= 5'd10) begin
            whole_digit = 4'd1;
            decimal_digit = tenths_remaining - 5'd10;
        end
        else begin
            whole_digit = 4'd0;
            decimal_digit = tenths_remaining[3:0];
        end

        reload_pixel = 1'b0;
        lx = 0; ly = 0; inside = 1'b0; digit = 0;

        if (reload_active &&
            (pixel_y >= 10'd252) && (pixel_y < 10'd268)) begin

            // Whole digit: x=306..313, 8x16
            if ((pixel_x >= 10'd306) && (pixel_x < 10'd314)) begin
                lx = pixel_x - 10'd306;
                ly = pixel_y - 10'd252;
                digit = whole_digit;
                inside = 1'b1;
            end

            // Decimal dot.
            if ((pixel_x >= 10'd317) && (pixel_x <= 10'd319) &&
                (pixel_y >= 10'd264) && (pixel_y <= 10'd266))
                reload_pixel = 1'b1;

            // Tenths digit: x=322..329.
            if ((pixel_x >= 10'd322) && (pixel_x < 10'd330)) begin
                lx = pixel_x - 10'd322;
                ly = pixel_y - 10'd252;
                digit = decimal_digit;
                inside = 1'b1;
            end
        end

        segments = digit_segments(digit);

        // Mini 8x16 seven-segment geometry.
        if (inside) begin
            if (segments[6] && (ly <= 1) && (lx >= 2) && (lx <= 5))
                reload_pixel = 1'b1;
            if (segments[5] && (lx >= 6) && (ly >= 2) && (ly <= 6))
                reload_pixel = 1'b1;
            if (segments[4] && (lx >= 6) && (ly >= 9) && (ly <= 13))
                reload_pixel = 1'b1;
            if (segments[3] && (ly >= 14) && (lx >= 2) && (lx <= 5))
                reload_pixel = 1'b1;
            if (segments[2] && (lx <= 1) && (ly >= 9) && (ly <= 13))
                reload_pixel = 1'b1;
            if (segments[1] && (lx <= 1) && (ly >= 2) && (ly <= 6))
                reload_pixel = 1'b1;
            if (segments[0] && (ly >= 7) && (ly <= 8) &&
                (lx >= 2) && (lx <= 5))
                reload_pixel = 1'b1;
        end
    end
endmodule
