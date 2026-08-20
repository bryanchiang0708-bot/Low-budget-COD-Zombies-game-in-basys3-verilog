module weapon_ammo_hud_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire [5:0] ammo_count,

    input  wire       reserve_unlimited,
    input  wire [3:0] reserve_hundreds,
    input  wire [3:0] reserve_tens,
    input  wire [3:0] reserve_ones,

    output reg        ammo_pixel
);
    reg [3:0] mag_tens;
    reg [3:0] mag_ones;

    reg [6:0] segments;
    reg [4:0] lx;
    reg [4:0] ly;
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
        // Magazine is at most 39.
        if (ammo_count >= 6'd30) begin
            mag_tens = 4'd3;
            mag_ones = ammo_count - 6'd30;
        end
        else if (ammo_count >= 6'd20) begin
            mag_tens = 4'd2;
            mag_ones = ammo_count - 6'd20;
        end
        else if (ammo_count >= 6'd10) begin
            mag_tens = 4'd1;
            mag_ones = ammo_count - 6'd10;
        end
        else begin
            mag_tens = 4'd0;
            mag_ones = ammo_count[3:0];
        end

        ammo_pixel = 1'b0;
        lx = 0;
        ly = 0;
        inside = 1'b0;
        digit = 0;

        // V26B layout: MM / RRR
        // x=520..608, y=382..403.
        if ((pixel_y >= 10'd382) && (pixel_y < 10'd404)) begin
            // Magazine tens
            if ((pixel_x >= 10'd520) && (pixel_x < 10'd532)) begin
                lx = pixel_x - 10'd520;
                ly = pixel_y - 10'd382;
                digit = mag_tens;
                inside = 1'b1;
            end
            // Magazine ones
            else if ((pixel_x >= 10'd536) && (pixel_x < 10'd548)) begin
                lx = pixel_x - 10'd536;
                ly = pixel_y - 10'd382;
                digit = mag_ones;
                inside = 1'b1;
            end

            // Slash separator.
            else if ((pixel_x >= 10'd553) && (pixel_x <= 10'd558)) begin
                // Descending diagonal from upper-right to lower-left.
                if ((pixel_y >= 10'd384) && (pixel_y <= 10'd401)) begin
                    if (((pixel_x == 10'd558) &&
                         (pixel_y >= 10'd384) && (pixel_y <= 10'd386)) ||
                        ((pixel_x == 10'd557) &&
                         (pixel_y >= 10'd387) && (pixel_y <= 10'd389)) ||
                        ((pixel_x == 10'd556) &&
                         (pixel_y >= 10'd390) && (pixel_y <= 10'd392)) ||
                        ((pixel_x == 10'd555) &&
                         (pixel_y >= 10'd393) && (pixel_y <= 10'd395)) ||
                        ((pixel_x == 10'd554) &&
                         (pixel_y >= 10'd396) && (pixel_y <= 10'd398)) ||
                        ((pixel_x == 10'd553) &&
                         (pixel_y >= 10'd399) && (pixel_y <= 10'd401)))
                        ammo_pixel = 1'b1;
                end
            end

            else if (reserve_unlimited) begin
                // Compact infinity symbol occupying the reserve field.
                // Two linked outline loops.
                if ((pixel_y >= 10'd388) && (pixel_y <= 10'd398)) begin
                    if (((pixel_x >= 10'd569) && (pixel_x <= 10'd578) &&
                         ((pixel_y == 10'd388) || (pixel_y == 10'd398) ||
                          (pixel_x == 10'd569) || (pixel_x == 10'd578))) ||
                        ((pixel_x >= 10'd580) && (pixel_x <= 10'd589) &&
                         ((pixel_y == 10'd388) || (pixel_y == 10'd398) ||
                          (pixel_x == 10'd580) || (pixel_x == 10'd589))) ||
                        ((pixel_x >= 10'd577) && (pixel_x <= 10'd581) &&
                         (pixel_y >= 10'd392) && (pixel_y <= 10'd394)))
                        ammo_pixel = 1'b1;
                end
            end
            else begin
                // Reserve hundreds
                if ((pixel_x >= 10'd564) && (pixel_x < 10'd576)) begin
                    lx = pixel_x - 10'd564;
                    ly = pixel_y - 10'd382;
                    digit = reserve_hundreds;
                    inside = 1'b1;
                end
                // Reserve tens
                else if ((pixel_x >= 10'd580) && (pixel_x < 10'd592)) begin
                    lx = pixel_x - 10'd580;
                    ly = pixel_y - 10'd382;
                    digit = reserve_tens;
                    inside = 1'b1;
                end
                // Reserve ones
                else if ((pixel_x >= 10'd596) && (pixel_x < 10'd608)) begin
                    lx = pixel_x - 10'd596;
                    ly = pixel_y - 10'd382;
                    digit = reserve_ones;
                    inside = 1'b1;
                end
            end
        end

        segments = digit_segments(digit);

        if (inside) begin
            if (segments[6] && (ly <= 1) && (lx >= 2) && (lx <= 9))
                ammo_pixel = 1'b1;
            if (segments[5] && (lx >= 10) && (ly >= 2) && (ly <= 9))
                ammo_pixel = 1'b1;
            if (segments[4] && (lx >= 10) && (ly >= 12) && (ly <= 19))
                ammo_pixel = 1'b1;
            if (segments[3] && (ly >= 20) && (lx >= 2) && (lx <= 9))
                ammo_pixel = 1'b1;
            if (segments[2] && (lx <= 1) && (ly >= 12) && (ly <= 19))
                ammo_pixel = 1'b1;
            if (segments[1] && (lx <= 1) && (ly >= 2) && (ly <= 9))
                ammo_pixel = 1'b1;
            if (segments[0] && (ly >= 10) && (ly <= 11) &&
                (lx >= 2) && (lx <= 9))
                ammo_pixel = 1'b1;
        end
    end
endmodule
