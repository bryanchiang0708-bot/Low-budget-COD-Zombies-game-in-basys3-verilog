// ============================================================================
// V22G START / DEATH SCREEN TEXT
//
// Start:
//      PRESS Y TO START
//
// Death:
//      YOU DIED
//      PRESS Y TO RESTART
//
// 5x7 font, scale 4. Black background is selected by the top-level VGA mux.
// ============================================================================
module game_flow_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire       show_start,
    input  wire       show_dead,
    output reg        text_pixel,
    output reg        red_pixel
);

    function [4:0] glyph_row;
        input [7:0] ch;
        input [2:0] row;
        begin
            glyph_row = 5'b00000;
            case (ch)
                "A": case(row)
                    0:glyph_row=5'b01110; 1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001; 3:glyph_row=5'b11111;
                    4:glyph_row=5'b10001; 5:glyph_row=5'b10001;
                    6:glyph_row=5'b10001; default:glyph_row=0;
                endcase
                "D": case(row)
                    0:glyph_row=5'b11110; 1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001; 3:glyph_row=5'b10001;
                    4:glyph_row=5'b10001; 5:glyph_row=5'b10001;
                    6:glyph_row=5'b11110; default:glyph_row=0;
                endcase
                "E": case(row)
                    0:glyph_row=5'b11111; 1:glyph_row=5'b10000;
                    2:glyph_row=5'b10000; 3:glyph_row=5'b11110;
                    4:glyph_row=5'b10000; 5:glyph_row=5'b10000;
                    6:glyph_row=5'b11111; default:glyph_row=0;
                endcase
                "I": case(row)
                    0:glyph_row=5'b11111; 1:glyph_row=5'b00100;
                    2:glyph_row=5'b00100; 3:glyph_row=5'b00100;
                    4:glyph_row=5'b00100; 5:glyph_row=5'b00100;
                    6:glyph_row=5'b11111; default:glyph_row=0;
                endcase
                "O": case(row)
                    0:glyph_row=5'b01110; 1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001; 3:glyph_row=5'b10001;
                    4:glyph_row=5'b10001; 5:glyph_row=5'b10001;
                    6:glyph_row=5'b01110; default:glyph_row=0;
                endcase
                "P": case(row)
                    0:glyph_row=5'b11110; 1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001; 3:glyph_row=5'b11110;
                    4:glyph_row=5'b10000; 5:glyph_row=5'b10000;
                    6:glyph_row=5'b10000; default:glyph_row=0;
                endcase
                "R": case(row)
                    0:glyph_row=5'b11110; 1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001; 3:glyph_row=5'b11110;
                    4:glyph_row=5'b10100; 5:glyph_row=5'b10010;
                    6:glyph_row=5'b10001; default:glyph_row=0;
                endcase
                "S": case(row)
                    0:glyph_row=5'b01111; 1:glyph_row=5'b10000;
                    2:glyph_row=5'b10000; 3:glyph_row=5'b01110;
                    4:glyph_row=5'b00001; 5:glyph_row=5'b00001;
                    6:glyph_row=5'b11110; default:glyph_row=0;
                endcase
                "T": case(row)
                    0:glyph_row=5'b11111; 1:glyph_row=5'b00100;
                    2:glyph_row=5'b00100; 3:glyph_row=5'b00100;
                    4:glyph_row=5'b00100; 5:glyph_row=5'b00100;
                    6:glyph_row=5'b00100; default:glyph_row=0;
                endcase
                "U": case(row)
                    0:glyph_row=5'b10001; 1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001; 3:glyph_row=5'b10001;
                    4:glyph_row=5'b10001; 5:glyph_row=5'b10001;
                    6:glyph_row=5'b01110; default:glyph_row=0;
                endcase
                "Y": case(row)
                    0:glyph_row=5'b10001; 1:glyph_row=5'b10001;
                    2:glyph_row=5'b01010; 3:glyph_row=5'b00100;
                    4:glyph_row=5'b00100; 5:glyph_row=5'b00100;
                    6:glyph_row=5'b00100; default:glyph_row=0;
                endcase
                default: glyph_row=5'b00000;
            endcase
        end
    endfunction

    // Separate fixed-string character functions. Spaces intentionally return
    // ASCII 0x20, whose glyph is blank.
    function [7:0] start_string_char;
        input [4:0] idx;
        begin
            case(idx)
                0:start_string_char="P"; 1:start_string_char="R";
                2:start_string_char="E"; 3:start_string_char="S";
                4:start_string_char="S"; 5:start_string_char=" ";
                6:start_string_char="Y"; 7:start_string_char=" ";
                8:start_string_char="T"; 9:start_string_char="O";
                10:start_string_char=" "; 11:start_string_char="S";
                12:start_string_char="T"; 13:start_string_char="A";
                14:start_string_char="R"; 15:start_string_char="T";
                default:start_string_char=" ";
            endcase
        end
    endfunction

    function [7:0] died_string_char;
        input [3:0] idx;
        begin
            case(idx)
                0:died_string_char="Y"; 1:died_string_char="O";
                2:died_string_char="U"; 3:died_string_char=" ";
                4:died_string_char="D"; 5:died_string_char="I";
                6:died_string_char="E"; 7:died_string_char="D";
                default:died_string_char=" ";
            endcase
        end
    endfunction

    function [7:0] restart_string_char;
        input [4:0] idx;
        begin
            case(idx)
                0:restart_string_char="P"; 1:restart_string_char="R";
                2:restart_string_char="E"; 3:restart_string_char="S";
                4:restart_string_char="S"; 5:restart_string_char=" ";
                6:restart_string_char="Y"; 7:restart_string_char=" ";
                8:restart_string_char="T"; 9:restart_string_char="O";
                10:restart_string_char=" "; 11:restart_string_char="R";
                12:restart_string_char="E"; 13:restart_string_char="S";
                14:restart_string_char="T"; 15:restart_string_char="A";
                16:restart_string_char="R"; 17:restart_string_char="T";
                default:restart_string_char=" ";
            endcase
        end
    endfunction

    reg [9:0] lx;
    reg [9:0] ly;
    reg [6:0] cell_x;
    reg [4:0] char_index;
    reg [2:0] glyph_col;
    reg [2:0] glyph_row_index;
    reg [7:0] selected_char;
    reg [4:0] selected_row;
    reg       inside_text;
    reg       selected_red;

    // x logical cell / 6. For the used range (0..107), floor(43*x/256)
    // exactly equals floor(x/6). Constant 43 is shift/add friendly.
    reg [14:0] char_mult;

    always @(*) begin
        text_pixel = 1'b0;
        red_pixel = 1'b0;

        lx = 10'd0;
        ly = 10'd0;
        cell_x = 7'd0;
        char_index = 5'd0;
        glyph_col = 3'd0;
        glyph_row_index = 3'd0;
        selected_char = " ";
        selected_row = 5'b00000;
        inside_text = 1'b0;
        selected_red = 1'b0;
        char_mult = 15'd0;

        // ------------------------------------------------------------
        // START: PRESS Y TO START
        // 16 chars * 24 pixels = 384 px, centered -> X=128.
        // ------------------------------------------------------------
        if (show_start &&
            (pixel_x >= 10'd128) && (pixel_x < 10'd512) &&
            (pixel_y >= 10'd226) && (pixel_y < 10'd254)) begin

            lx = pixel_x - 10'd128;
            ly = pixel_y - 10'd226;
            cell_x = lx[9:2];

            char_mult = (cell_x << 5) + (cell_x << 3) +
                        (cell_x << 1) + cell_x;
            char_index = char_mult[14:8];
            glyph_col = cell_x - ((char_index << 2) + (char_index << 1));
            glyph_row_index = ly[4:2];

            if ((char_index < 5'd16) && (glyph_col < 3'd5) &&
                (glyph_row_index < 3'd7)) begin
                selected_char = start_string_char(char_index);
                inside_text = 1'b1;
                selected_red = 1'b0;
            end
        end

        // ------------------------------------------------------------
        // DEAD title: YOU DIED
        // 8 chars * 24 = 192 px, centered -> X=224.
        // ------------------------------------------------------------
        else if (show_dead &&
            (pixel_x >= 10'd224) && (pixel_x < 10'd416) &&
            (pixel_y >= 10'd190) && (pixel_y < 10'd218)) begin

            lx = pixel_x - 10'd224;
            ly = pixel_y - 10'd190;
            cell_x = lx[9:2];

            char_mult = (cell_x << 5) + (cell_x << 3) +
                        (cell_x << 1) + cell_x;
            char_index = char_mult[14:8];
            glyph_col = cell_x - ((char_index << 2) + (char_index << 1));
            glyph_row_index = ly[4:2];

            if ((char_index < 5'd8) && (glyph_col < 3'd5) &&
                (glyph_row_index < 3'd7)) begin
                selected_char = died_string_char(char_index[3:0]);
                inside_text = 1'b1;
                selected_red = 1'b1;
            end
        end

        // ------------------------------------------------------------
        // DEAD prompt: PRESS Y TO RESTART
        // 18 chars * 24 = 432 px, centered -> X=104.
        // ------------------------------------------------------------
        else if (show_dead &&
            (pixel_x >= 10'd104) && (pixel_x < 10'd536) &&
            (pixel_y >= 10'd250) && (pixel_y < 10'd278)) begin

            lx = pixel_x - 10'd104;
            ly = pixel_y - 10'd250;
            cell_x = lx[9:2];

            char_mult = (cell_x << 5) + (cell_x << 3) +
                        (cell_x << 1) + cell_x;
            char_index = char_mult[14:8];
            glyph_col = cell_x - ((char_index << 2) + (char_index << 1));
            glyph_row_index = ly[4:2];

            if ((char_index < 5'd18) && (glyph_col < 3'd5) &&
                (glyph_row_index < 3'd7)) begin
                selected_char = restart_string_char(char_index);
                inside_text = 1'b1;
                selected_red = 1'b0;
            end
        end

        selected_row = glyph_row(selected_char, glyph_row_index);

        if (inside_text) begin
            case(glyph_col)
                0:text_pixel = selected_row[4];
                1:text_pixel = selected_row[3];
                2:text_pixel = selected_row[2];
                3:text_pixel = selected_row[1];
                default:text_pixel = selected_row[0];
            endcase

            if (text_pixel)
                red_pixel = selected_red;
        end
    end
endmodule
