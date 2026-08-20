// ============================================================================
// V22E PLAYER HP HUD
//
// Draws "HP3" immediately to the right of the four-digit money HUD.
// Money occupies x=12..71, y=14..35.
// HP begins at x=84, y=14.
//
// The H/P glyphs use only simple rectangle comparisons. The HP digit reuses
// seven-segment geometry, keeping this display-only overlay very small.
// ============================================================================
module player_hp_hud_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire [2:0] player_hp,
    output reg        hp_pixel
);
    reg [4:0] local_x;
    reg [4:0] local_y;
    reg [6:0] segments;
    reg       inside_digit;

    function [6:0] digit_segments;
        input [3:0] d;
        begin
            case (d)
                4'd0: digit_segments = 7'b1111110;
                4'd1: digit_segments = 7'b0110000;
                4'd2: digit_segments = 7'b1101101;
                4'd3: digit_segments = 7'b1111001;
                4'd4: digit_segments = 7'b0110011;
                default: digit_segments = 7'b0000000;
            endcase
        end
    endfunction

    always @(*) begin
        hp_pixel = 1'b0;
        local_x = 5'd0;
        local_y = 5'd0;
        inside_digit = 1'b0;
        segments = digit_segments({1'b0,player_hp});

        // H: x=84..94, y=14..35
        if ((pixel_y >= 10'd14) && (pixel_y < 10'd36)) begin
            if ((pixel_x >= 10'd84) && (pixel_x <= 10'd85))
                hp_pixel = 1'b1;
            if ((pixel_x >= 10'd93) && (pixel_x <= 10'd94))
                hp_pixel = 1'b1;
            if ((pixel_x >= 10'd84) && (pixel_x <= 10'd94) &&
                (pixel_y >= 10'd24) && (pixel_y <= 10'd25))
                hp_pixel = 1'b1;

            // P: x=100..110, y=14..35
            if ((pixel_x >= 10'd100) && (pixel_x <= 10'd101))
                hp_pixel = 1'b1;
            if ((pixel_y >= 10'd14) && (pixel_y <= 10'd15) &&
                (pixel_x >= 10'd100) && (pixel_x <= 10'd109))
                hp_pixel = 1'b1;
            if ((pixel_y >= 10'd24) && (pixel_y <= 10'd25) &&
                (pixel_x >= 10'd100) && (pixel_x <= 10'd109))
                hp_pixel = 1'b1;
            if ((pixel_x >= 10'd108) && (pixel_x <= 10'd109) &&
                (pixel_y >= 10'd16) && (pixel_y <= 10'd23))
                hp_pixel = 1'b1;

            // HP digit: x=116..127, same 12x22 geometry as money digits.
            if ((pixel_x >= 10'd116) && (pixel_x < 10'd128)) begin
                local_x = pixel_x - 10'd116;
                local_y = pixel_y - 10'd14;
                inside_digit = 1'b1;
            end
        end

        if (inside_digit) begin
            if (segments[6] && (local_y <= 5'd1) &&
                (local_x >= 5'd2) && (local_x <= 5'd9))
                hp_pixel = 1'b1;
            if (segments[5] && (local_x >= 5'd10) &&
                (local_y >= 5'd2) && (local_y <= 5'd9))
                hp_pixel = 1'b1;
            if (segments[4] && (local_x >= 5'd10) &&
                (local_y >= 5'd12) && (local_y <= 5'd19))
                hp_pixel = 1'b1;
            if (segments[3] && (local_y >= 5'd20) &&
                (local_x >= 5'd2) && (local_x <= 5'd9))
                hp_pixel = 1'b1;
            if (segments[2] && (local_x <= 5'd1) &&
                (local_y >= 5'd12) && (local_y <= 5'd19))
                hp_pixel = 1'b1;
            if (segments[1] && (local_x <= 5'd1) &&
                (local_y >= 5'd2) && (local_y <= 5'd9))
                hp_pixel = 1'b1;
            if (segments[0] && (local_y >= 5'd10) && (local_y <= 5'd11) &&
                (local_x >= 5'd2) && (local_x <= 5'd9))
                hp_pixel = 1'b1;
        end
    end
endmodule
