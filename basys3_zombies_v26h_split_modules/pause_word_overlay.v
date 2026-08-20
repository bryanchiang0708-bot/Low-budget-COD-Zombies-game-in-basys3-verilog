// ============================================================================
// CENTER-SCREEN "PAUSE" WORD
// 5x7 block font, scale 6 -> 174 x 42 pixels centered at 640x480.
// Display only.
// ============================================================================
module pause_word_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire       pause_active,
    output reg        pause_pixel
);
    localparam [9:0] START_X = 10'd233;
    localparam [9:0] START_Y = 10'd219;

    reg [2:0] char_index;
    reg [2:0] glyph_row_index;
    reg [2:0] glyph_col_index;
    reg       inside_char;
    reg [4:0] glyph_bits;
    reg [9:0] local_x;
    reg [9:0] local_y;

    // Return one 5-pixel row. bit[4] = left-most column.
    function [4:0] pause_glyph_row;
        input [2:0] ch;
        input [2:0] row;
        begin
            pause_glyph_row = 5'b00000;
            case (ch)
                // P
                3'd0: case (row)
                    0: pause_glyph_row=5'b11110;
                    1: pause_glyph_row=5'b10001;
                    2: pause_glyph_row=5'b10001;
                    3: pause_glyph_row=5'b11110;
                    4: pause_glyph_row=5'b10000;
                    5: pause_glyph_row=5'b10000;
                    6: pause_glyph_row=5'b10000;
                    default: pause_glyph_row=0;
                endcase
                // A
                3'd1: case (row)
                    0: pause_glyph_row=5'b01110;
                    1: pause_glyph_row=5'b10001;
                    2: pause_glyph_row=5'b10001;
                    3: pause_glyph_row=5'b11111;
                    4: pause_glyph_row=5'b10001;
                    5: pause_glyph_row=5'b10001;
                    6: pause_glyph_row=5'b10001;
                    default: pause_glyph_row=0;
                endcase
                // U
                3'd2: case (row)
                    0,1,2,3,4,5: pause_glyph_row=5'b10001;
                    6: pause_glyph_row=5'b01110;
                    default: pause_glyph_row=0;
                endcase
                // S
                3'd3: case (row)
                    0: pause_glyph_row=5'b01111;
                    1: pause_glyph_row=5'b10000;
                    2: pause_glyph_row=5'b10000;
                    3: pause_glyph_row=5'b01110;
                    4: pause_glyph_row=5'b00001;
                    5: pause_glyph_row=5'b00001;
                    6: pause_glyph_row=5'b11110;
                    default: pause_glyph_row=0;
                endcase
                // E
                3'd4: case (row)
                    0: pause_glyph_row=5'b11111;
                    1: pause_glyph_row=5'b10000;
                    2: pause_glyph_row=5'b10000;
                    3: pause_glyph_row=5'b11110;
                    4: pause_glyph_row=5'b10000;
                    5: pause_glyph_row=5'b10000;
                    6: pause_glyph_row=5'b11111;
                    default: pause_glyph_row=0;
                endcase
                default: pause_glyph_row=5'b00000;
            endcase
        end
    endfunction

    always @(*) begin
        pause_pixel = 1'b0;
        char_index = 3'd0;
        glyph_row_index = 3'd0;
        glyph_col_index = 3'd0;
        inside_char = 1'b0;
        glyph_bits = 5'b00000;
        local_x = 10'd0;
        local_y = 10'd0;

        if (pause_active &&
            (pixel_x >= START_X) && (pixel_x < START_X + 10'd174) &&
            (pixel_y >= START_Y) && (pixel_y < START_Y + 10'd42)) begin

            local_x = pixel_x - START_X;
            local_y = pixel_y - START_Y;

            // Character cells are 36 px wide: 30 px glyph + 6 px gap.
            if (local_x < 10'd30) begin
                char_index = 3'd0; inside_char = 1'b1; local_x = local_x;
            end else if ((local_x >= 10'd36) && (local_x < 10'd66)) begin
                char_index = 3'd1; inside_char = 1'b1; local_x = local_x - 10'd36;
            end else if ((local_x >= 10'd72) && (local_x < 10'd102)) begin
                char_index = 3'd2; inside_char = 1'b1; local_x = local_x - 10'd72;
            end else if ((local_x >= 10'd108) && (local_x < 10'd138)) begin
                char_index = 3'd3; inside_char = 1'b1; local_x = local_x - 10'd108;
            end else if ((local_x >= 10'd144) && (local_x < 10'd174)) begin
                char_index = 3'd4; inside_char = 1'b1; local_x = local_x - 10'd144;
            end

            if (local_y < 6) glyph_row_index=0;
            else if (local_y < 12) glyph_row_index=1;
            else if (local_y < 18) glyph_row_index=2;
            else if (local_y < 24) glyph_row_index=3;
            else if (local_y < 30) glyph_row_index=4;
            else if (local_y < 36) glyph_row_index=5;
            else glyph_row_index=6;

            if (local_x < 6) glyph_col_index=0;
            else if (local_x < 12) glyph_col_index=1;
            else if (local_x < 18) glyph_col_index=2;
            else if (local_x < 24) glyph_col_index=3;
            else glyph_col_index=4;

            glyph_bits = pause_glyph_row(char_index, glyph_row_index);

            if (inside_char)
                case (glyph_col_index)
                    0: pause_pixel = glyph_bits[4];
                    1: pause_pixel = glyph_bits[3];
                    2: pause_pixel = glyph_bits[2];
                    3: pause_pixel = glyph_bits[1];
                    default: pause_pixel = glyph_bits[0];
                endcase
        end
    end
endmodule
