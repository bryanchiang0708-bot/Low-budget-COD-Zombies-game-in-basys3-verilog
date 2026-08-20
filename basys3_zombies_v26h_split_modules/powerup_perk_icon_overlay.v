// ============================================================================
// V22E EQUIPPED PISTOL ICON
//
// Simple fixed HUD sprite on the lower-right side.
// This is intentionally only an equipment icon for now, not a first-person
// weapon/hand model.
//
// Approximate screen bounds: x=566..627, y=414..461.
// ============================================================================
// ============================================================================
// V26B SELECTED POWER-UP ICON HUD
//
// Packed immediately to the right of HP:
//   slot 0: x=136..149
//   slot 1: x=154..167
//
// The two active perks are packed in fixed type order so there are never gaps.
// icon_kind:
//   1 shoes / move speed
//   2 down arrow / slow zombies
//   3 heart / +1 HP
//   0 magazine / fast reload
// ============================================================================
module powerup_perk_icon_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,

    input  wire       perk_move_speed,
    input  wire       perk_zombie_slow,
    input  wire       perk_extra_hp,
    input  wire       perk_fast_reload,

    input  wire       menu_open,

    output reg        icon_pixel,
    output reg        menu_fg_pixel,
    output reg        menu_bg_pixel
);
    // kind 0..3 maps directly to menu row / fixed HUD slot:
    //   0 shoes
    //   1 down arrow
    //   2 heart
    //   3 magazine

    reg [1:0] draw_kind;
    reg [2:0] icon_x;
    reg [2:0] icon_y;
    reg [7:0] icon_bits;

    reg [4:0] digit_bits;
    reg [2:0] digit_x;
    reg [2:0] digit_y;
    reg [3:0] digit_value;

    reg       slot_owned;
    reg [1:0] slot_kind;

    wire menu_inside =
        menu_open &&
        (pixel_x[9:7] == 3'b010) &&   // 256..383
        (pixel_y[9:7] == 3'b001);     // 128..255

    wire [6:0] menu_x = pixel_x[6:0];
    wire [6:0] menu_y = pixel_y[6:0];
    wire [1:0] menu_row = menu_y[6:5];
    wire [4:0] row_y = menu_y[4:0];

    // ------------------------------------------------------------------------
    // Tiny 8x8 perk-icon ROM.
    //
    // One ROM serves both the persistent HP HUD and the purchase menu.
    // ------------------------------------------------------------------------
    function [7:0] perk_icon_row;
        input [1:0] kind;
        input [2:0] row;
        begin
            case (kind)
                // Shoe
                2'd0: begin
                    case (row)
                        0: perk_icon_row = 8'b11000000;
                        1: perk_icon_row = 8'b11000000;
                        2: perk_icon_row = 8'b11100000;
                        3: perk_icon_row = 8'b11110000;
                        4: perk_icon_row = 8'b11111000;
                        5: perk_icon_row = 8'b11111110;
                        6: perk_icon_row = 8'b01111111;
                        default: perk_icon_row = 8'b00000000;
                    endcase
                end

                // Down arrow
                2'd1: begin
                    case (row)
                        0: perk_icon_row = 8'b00011000;
                        1: perk_icon_row = 8'b00011000;
                        2: perk_icon_row = 8'b00011000;
                        3: perk_icon_row = 8'b00011000;
                        4: perk_icon_row = 8'b11111111;
                        5: perk_icon_row = 8'b01111110;
                        6: perk_icon_row = 8'b00111100;
                        default: perk_icon_row = 8'b00011000;
                    endcase
                end

                // Heart
                2'd2: begin
                    case (row)
                        0: perk_icon_row = 8'b01100110;
                        1: perk_icon_row = 8'b11111111;
                        2: perk_icon_row = 8'b11111111;
                        3: perk_icon_row = 8'b11111111;
                        4: perk_icon_row = 8'b01111110;
                        5: perk_icon_row = 8'b00111100;
                        6: perk_icon_row = 8'b00011000;
                        default: perk_icon_row = 8'b00000000;
                    endcase
                end

                // Magazine
                default: begin
                    case (row)
                        0: perk_icon_row = 8'b00111100;
                        1: perk_icon_row = 8'b00111100;
                        2: perk_icon_row = 8'b00111100;
                        3: perk_icon_row = 8'b00111100;
                        4: perk_icon_row = 8'b00111100;
                        5: perk_icon_row = 8'b00111100;
                        6: perk_icon_row = 8'b00111000;
                        default: perk_icon_row = 8'b00110000;
                    endcase
                end
            endcase
        end
    endfunction

    // ------------------------------------------------------------------------
    // Tiny 5x7 digit ROM.
    // Only digits 0..4 are needed:
    //   row number 1..4 and price 1000.
    // ------------------------------------------------------------------------
    function [4:0] digit_row;
        input [3:0] digit;
        input [2:0] row;
        begin
            digit_row = 5'b00000;

            case (digit)
                4'd0: case (row)
                    0:digit_row=5'b01110;
                    1:digit_row=5'b10001;
                    2:digit_row=5'b10011;
                    3:digit_row=5'b10101;
                    4:digit_row=5'b11001;
                    5:digit_row=5'b10001;
                    6:digit_row=5'b01110;
                    default:digit_row=0;
                endcase

                4'd1: case (row)
                    0:digit_row=5'b00100;
                    1:digit_row=5'b01100;
                    2:digit_row=5'b00100;
                    3:digit_row=5'b00100;
                    4:digit_row=5'b00100;
                    5:digit_row=5'b00100;
                    6:digit_row=5'b01110;
                    default:digit_row=0;
                endcase

                4'd2: case (row)
                    0:digit_row=5'b01110;
                    1:digit_row=5'b10001;
                    2:digit_row=5'b00001;
                    3:digit_row=5'b00010;
                    4:digit_row=5'b00100;
                    5:digit_row=5'b01000;
                    6:digit_row=5'b11111;
                    default:digit_row=0;
                endcase

                4'd3: case (row)
                    0:digit_row=5'b11110;
                    1:digit_row=5'b00001;
                    2:digit_row=5'b00001;
                    3:digit_row=5'b01110;
                    4:digit_row=5'b00001;
                    5:digit_row=5'b00001;
                    6:digit_row=5'b11110;
                    default:digit_row=0;
                endcase

                default: case (row) // 4
                    0:digit_row=5'b00010;
                    1:digit_row=5'b00110;
                    2:digit_row=5'b01010;
                    3:digit_row=5'b10010;
                    4:digit_row=5'b11111;
                    5:digit_row=5'b00010;
                    6:digit_row=5'b00010;
                    default:digit_row=0;
                endcase
            endcase
        end
    endfunction

    always @(*) begin
        icon_pixel = 1'b0;
        menu_fg_pixel = 1'b0;
        menu_bg_pixel = 1'b0;

        draw_kind = 2'd0;
        icon_x = 3'd0;
        icon_y = 3'd0;
        icon_bits = 8'd0;

        digit_bits = 5'd0;
        digit_x = 3'd0;
        digit_y = 3'd0;
        digit_value = 4'd0;

        slot_owned = 1'b0;
        slot_kind = 2'd0;

        // --------------------------------------------------------------------
        // Persistent purchased-perk icons beside HP.
        //
        // Cheap power-of-two placement:
        //   X 128..191 = four 16-pixel slots
        //   Y 16..23   = one 8-pixel icon row
        // Icons occupy the first 8 pixels of each slot.
        // --------------------------------------------------------------------
        if ((pixel_x[9:6] == 4'b0010) &&   // 128..191
            (pixel_y[9:3] == 7'd2) &&      // 16..23
            !pixel_x[3]) begin             // first 8 px of each 16px slot

            slot_kind = pixel_x[5:4];

            case (pixel_x[5:4])
                2'd0: slot_owned = perk_move_speed;
                2'd1: slot_owned = perk_zombie_slow;
                2'd2: slot_owned = perk_extra_hp;
                default: slot_owned = perk_fast_reload;
            endcase

            if (slot_owned) begin
                icon_x = pixel_x[2:0];
                icon_y = pixel_y[2:0];
                icon_bits = perk_icon_row(slot_kind, icon_y);
                icon_pixel = icon_bits[7-icon_x];
            end
        end

        // --------------------------------------------------------------------
        // LUT-optimized POWER UP buy menu.
        //
        // 128x128 centered panel:
        //   X 256..383
        //   Y 128..255
        //
        // Four equal 32-pixel rows:
        //   1  [shoe]   1000
        //   2  [down]   1000
        //   3  [heart]  1000
        //   4  [mag]    1000
        //
        // Purchased row gets an X on the far right.
        // --------------------------------------------------------------------
        if (menu_inside) begin
            menu_bg_pixel = 1'b1;

            // Outer border + row separators.
            if ((menu_x == 7'd0) ||
                (menu_x == 7'd127) ||
                (row_y == 5'd0) ||
                (menu_y == 7'd127))
                menu_fg_pixel = 1'b1;

            // Which perk belongs to this row?
            case (menu_row)
                2'd0: slot_owned = perk_move_speed;
                2'd1: slot_owned = perk_zombie_slow;
                2'd2: slot_owned = perk_extra_hp;
                default: slot_owned = perk_fast_reload;
            endcase

            // Row number 1..4:
            // local X 8..12, row-local Y 12..18.
            if ((menu_x >= 7'd8) && (menu_x <= 7'd12) &&
                (row_y >= 5'd12) && (row_y <= 5'd18)) begin

                digit_x = menu_x[2:0];
                digit_x = menu_x - 7'd8;
                digit_y = row_y - 5'd12;
                digit_value = {2'b00,menu_row} + 4'd1;
                digit_bits = digit_row(digit_value,digit_y);

                if (digit_x < 3'd5)
                    menu_fg_pixel = digit_bits[4-digit_x];
            end

            // Perk icon:
            // local X 32..39, row-local Y 12..19.
            if ((menu_x[6:3] == 4'd4) &&
                (row_y >= 5'd12) && (row_y <= 5'd19)) begin

                icon_x = menu_x[2:0];
                icon_y = row_y - 5'd12;
                icon_bits = perk_icon_row(menu_row,icon_y);
                menu_fg_pixel = menu_fg_pixel | icon_bits[7-icon_x];
            end

            // Price = 1000.
            //
            // Four 8-pixel character slots beginning at local X=64.
            // Only glyphs "1" and "0" are needed.
            if ((menu_x >= 7'd64) && (menu_x <= 7'd92) &&
                (row_y >= 5'd12) && (row_y <= 5'd18)) begin

                digit_y = row_y - 5'd12;

                if ((menu_x >= 7'd64) && (menu_x <= 7'd68)) begin
                    digit_x = menu_x - 7'd64;
                    digit_bits = digit_row(4'd1,digit_y);
                    menu_fg_pixel = menu_fg_pixel | digit_bits[4-digit_x];
                end
                else if ((menu_x >= 7'd72) && (menu_x <= 7'd76)) begin
                    digit_x = menu_x - 7'd72;
                    digit_bits = digit_row(4'd0,digit_y);
                    menu_fg_pixel = menu_fg_pixel | digit_bits[4-digit_x];
                end
                else if ((menu_x >= 7'd80) && (menu_x <= 7'd84)) begin
                    digit_x = menu_x - 7'd80;
                    digit_bits = digit_row(4'd0,digit_y);
                    menu_fg_pixel = menu_fg_pixel | digit_bits[4-digit_x];
                end
                else if ((menu_x >= 7'd88) && (menu_x <= 7'd92)) begin
                    digit_x = menu_x - 7'd88;
                    digit_bits = digit_row(4'd0,digit_y);
                    menu_fg_pixel = menu_fg_pixel | digit_bits[4-digit_x];
                end
            end

            // Purchased X:
            // local X 112..119, row-local Y 12..19.
            if (slot_owned &&
                (menu_x[6:3] == 4'd14) &&
                (row_y >= 5'd12) && (row_y <= 5'd19)) begin

                if ((menu_x[2:0] == (row_y - 5'd12)) ||
                    (menu_x[2:0] == (3'd7 - (row_y - 5'd12))))
                    menu_fg_pixel = 1'b1;
            end
        end
    end
endmodule
