// ============================================================================
// V23B WALL-BUY LABEL OVERLAY
//
// Tracks the visible screen-space bounding box of each pink buy-wall surface
// during one frame, then uses that box on the next frame to center a compact
// 5x7 label. The final pixel is still clipped by the CURRENT buy-wall surface,
// so white letters appear only on the pink wall:
//
//      SHOTGUN 500
//      RIFLE 1000
//
// Scale automatically uses 2x when the visible surface is wide enough;
// otherwise it falls back to 1x. At extreme distance the label may be tiny,
// which is appropriate because the physical sign is far away.
// ============================================================================

// ============================================================================
// V24 VISUAL-ONLY STATIC STATION LABELS
//
// POWER 1000
// ULTIMATE 1500
// POWER UP
// LUCKY BOX 1000
//
// Tracks the projected pink rectangle during one frame, then centers a 5x7
// label inside its previous-frame bounding box. These stations are visual-only.
// ============================================================================







// ============================================================================
// V24B SHARED LUT-OPTIMIZED PINK-STATION LABEL RENDERER
//
// One renderer serves all six projected pink surfaces:
//
//   SHOTGUN 500
//   RIFLE 1000
//   POWER 1000
//   ULTIMATE 1500
//   POWER UP
//   LUCKY BOX 1000
//
// The V24 build had TWO complete label renderers, duplicating the 5x7 font,
// character selection, division-by-6 approximation, and placement logic.
// V24B shares all of that logic.
//
// Text is intentionally fixed at 1x 5x7 size. Removing the optional 2x scaling
// branch recovers additional LUT headroom on the XC7A35T.
// ============================================================================
module shared_station_label_overlay (
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire       frame_tick,
    input  wire       pixel_tick,
    input  wire       active_video,
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire signed [8:0] camera_pitch,
    input  wire       power_on,

    input  wire       shotgun_column,
    input  wire       rifle_column,
    input  wire       power_column,
    input  wire       ultimate_column,
    input  wire       powerup_column,
    input  wire       luckybox_column,

    input  wire       shotgun_surface_pixel,
    input  wire       rifle_surface_pixel,
    input  wire       power_surface_pixel,
    input  wire       ultimate_surface_pixel,
    input  wire       powerup_surface_pixel,
    input  wire       luckybox_surface_pixel,

    output reg        label_pixel
);

    localparam [2:0]
        K_NONE     = 3'd0,
        K_SHOTGUN  = 3'd1,
        K_RIFLE    = 3'd2,
        K_POWER    = 3'd3,
        K_ULTIMATE = 3'd4,
        K_POWERUP  = 3'd5,
        K_LUCKYBOX = 3'd6;

    // X-only projected bounds. Wall subtype is a per-column property, so
    // scanning once on active row 0 is enough.
    reg [9:0] shot_minx, shot_maxx, rifle_minx, rifle_maxx;
    reg [9:0] power_minx, power_maxx, ultimate_minx, ultimate_maxx;
    reg [9:0] powerup_minx, powerup_maxx, lucky_minx, lucky_maxx;

    reg [9:0] shot_bminx, shot_bmaxx, rifle_bminx, rifle_bmaxx;
    reg [9:0] power_bminx, power_bmaxx, ultimate_bminx, ultimate_bmaxx;
    reg [9:0] powerup_bminx, powerup_bmaxx, lucky_bminx, lucky_bmaxx;

    reg shot_valid, rifle_valid, power_valid;
    reg ultimate_valid, powerup_valid, lucky_valid;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            shot_minx<=639; shot_maxx<=0;
            rifle_minx<=639; rifle_maxx<=0;
            power_minx<=639; power_maxx<=0;
            ultimate_minx<=639; ultimate_maxx<=0;
            powerup_minx<=639; powerup_maxx<=0;
            lucky_minx<=639; lucky_maxx<=0;

            shot_bminx<=0; shot_bmaxx<=0;
            rifle_bminx<=0; rifle_bmaxx<=0;
            power_bminx<=0; power_bmaxx<=0;
            ultimate_bminx<=0; ultimate_bmaxx<=0;
            powerup_bminx<=0; powerup_bmaxx<=0;
            lucky_bminx<=0; lucky_bmaxx<=0;

            shot_valid<=0; rifle_valid<=0; power_valid<=0;
            ultimate_valid<=0; powerup_valid<=0; lucky_valid<=0;
        end
        else if (frame_tick) begin
            shot_valid <= (shot_minx <= shot_maxx);
            shot_bminx <= shot_minx; shot_bmaxx <= shot_maxx;

            rifle_valid <= (rifle_minx <= rifle_maxx);
            rifle_bminx <= rifle_minx; rifle_bmaxx <= rifle_maxx;

            power_valid <= (power_minx <= power_maxx);
            power_bminx <= power_minx; power_bmaxx <= power_maxx;

            ultimate_valid <= (ultimate_minx <= ultimate_maxx);
            ultimate_bminx <= ultimate_minx; ultimate_bmaxx <= ultimate_maxx;

            powerup_valid <= (powerup_minx <= powerup_maxx);
            powerup_bminx <= powerup_minx; powerup_bmaxx <= powerup_maxx;

            lucky_valid <= (lucky_minx <= lucky_maxx);
            lucky_bminx <= lucky_minx; lucky_bmaxx <= lucky_maxx;

            shot_minx<=639; shot_maxx<=0;
            rifle_minx<=639; rifle_maxx<=0;
            power_minx<=639; power_maxx<=0;
            ultimate_minx<=639; ultimate_maxx<=0;
            powerup_minx<=639; powerup_maxx<=0;
            lucky_minx<=639; lucky_maxx<=0;
        end
        else if (pixel_tick && active_video && (pixel_y == 10'd0)) begin
            if (shotgun_column) begin
                if(pixel_x<shot_minx) shot_minx<=pixel_x;
                if(pixel_x>shot_maxx) shot_maxx<=pixel_x;
            end
            if (rifle_column) begin
                if(pixel_x<rifle_minx) rifle_minx<=pixel_x;
                if(pixel_x>rifle_maxx) rifle_maxx<=pixel_x;
            end
            if (power_column) begin
                if(pixel_x<power_minx) power_minx<=pixel_x;
                if(pixel_x>power_maxx) power_maxx<=pixel_x;
            end
            if (ultimate_column) begin
                if(pixel_x<ultimate_minx) ultimate_minx<=pixel_x;
                if(pixel_x>ultimate_maxx) ultimate_maxx<=pixel_x;
            end
            if (powerup_column) begin
                if(pixel_x<powerup_minx) powerup_minx<=pixel_x;
                if(pixel_x>powerup_maxx) powerup_maxx<=pixel_x;
            end
            if (luckybox_column) begin
                if(pixel_x<lucky_minx) lucky_minx<=pixel_x;
                if(pixel_x>lucky_maxx) lucky_maxx<=pixel_x;
            end
        end
    end

    function [4:0] glyph_row;
        input [7:0] ch;
        input [2:0] row;
        begin
            glyph_row=0;
            case(ch)
                "A":case(row)0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b11111;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "B":case(row)0:glyph_row=5'b11110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b11110;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                "C":case(row)0:glyph_row=5'b01111;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b10000;4:glyph_row=5'b10000;5:glyph_row=5'b10000;6:glyph_row=5'b01111;default:glyph_row=0;endcase
                "E":case(row)0:glyph_row=5'b11111;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b11110;4:glyph_row=5'b10000;5:glyph_row=5'b10000;6:glyph_row=5'b11111;default:glyph_row=0;endcase
                "F":case(row)0:glyph_row=5'b11111;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b11110;4:glyph_row=5'b10000;5:glyph_row=5'b10000;6:glyph_row=5'b10000;default:glyph_row=0;endcase
                "G":case(row)0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b10000;3:glyph_row=5'b10111;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "H":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b11111;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "I":case(row)0:glyph_row=5'b11111;1:glyph_row=5'b00100;2:glyph_row=5'b00100;3:glyph_row=5'b00100;4:glyph_row=5'b00100;5:glyph_row=5'b00100;6:glyph_row=5'b11111;default:glyph_row=0;endcase
                "K":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b10010;2:glyph_row=5'b10100;3:glyph_row=5'b11000;4:glyph_row=5'b10100;5:glyph_row=5'b10010;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "L":case(row)0:glyph_row=5'b10000;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b10000;4:glyph_row=5'b10000;5:glyph_row=5'b10000;6:glyph_row=5'b11111;default:glyph_row=0;endcase
                "M":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b11011;2:glyph_row=5'b10101;3:glyph_row=5'b10101;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "N":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b11001;2:glyph_row=5'b11001;3:glyph_row=5'b10101;4:glyph_row=5'b10011;5:glyph_row=5'b10011;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "O":case(row)0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b10001;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "P":case(row)0:glyph_row=5'b11110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b11110;4:glyph_row=5'b10000;5:glyph_row=5'b10000;6:glyph_row=5'b10000;default:glyph_row=0;endcase
                "R":case(row)0:glyph_row=5'b11110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b11110;4:glyph_row=5'b10100;5:glyph_row=5'b10010;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "S":case(row)0:glyph_row=5'b01111;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b01110;4:glyph_row=5'b00001;5:glyph_row=5'b00001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                "T":case(row)0:glyph_row=5'b11111;1:glyph_row=5'b00100;2:glyph_row=5'b00100;3:glyph_row=5'b00100;4:glyph_row=5'b00100;5:glyph_row=5'b00100;6:glyph_row=5'b00100;default:glyph_row=0;endcase
                "U":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b10001;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "W":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b10101;4:glyph_row=5'b10101;5:glyph_row=5'b11011;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "X":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b01010;3:glyph_row=5'b00100;4:glyph_row=5'b01010;5:glyph_row=5'b10001;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "Y":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b01010;3:glyph_row=5'b00100;4:glyph_row=5'b00100;5:glyph_row=5'b00100;6:glyph_row=5'b00100;default:glyph_row=0;endcase
                "0":case(row)0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b10011;3:glyph_row=5'b10101;4:glyph_row=5'b11001;5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "1":case(row)0:glyph_row=5'b00100;1:glyph_row=5'b01100;2:glyph_row=5'b00100;3:glyph_row=5'b00100;4:glyph_row=5'b00100;5:glyph_row=5'b00100;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "5":case(row)0:glyph_row=5'b11111;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b11110;4:glyph_row=5'b00001;5:glyph_row=5'b00001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                default:glyph_row=0;
            endcase
        end
    endfunction

    function [4:0] label_length;
        input [2:0] kind;
        input       pwr;
        begin
            case(kind)
                K_SHOTGUN:label_length=11;
                K_RIFLE:label_length=10;

                // Append " ON" or " OFF".
                K_POWER:label_length = pwr ? 13 : 14;
                K_ULTIMATE:label_length = pwr ? 16 : 17;
                K_POWERUP:label_length = pwr ? 11 : 12;

                K_LUCKYBOX:label_length=14;
                default:label_length=0;
            endcase
        end
    endfunction

    function [7:0] label_char;
        input [2:0] kind;
        input [4:0] idx;
        begin
            label_char=" ";
            case(kind)
                K_SHOTGUN:case(idx)
                    0:label_char="S";1:label_char="H";2:label_char="O";3:label_char="T";
                    4:label_char="G";5:label_char="U";6:label_char="N";7:label_char=" ";
                    8:label_char="5";9:label_char="0";10:label_char="0";default:label_char=" ";
                endcase
                K_RIFLE:case(idx)
                    0:label_char="R";1:label_char="I";2:label_char="F";3:label_char="L";
                    4:label_char="E";5:label_char=" ";6:label_char="1";7:label_char="0";
                    8:label_char="0";9:label_char="0";default:label_char=" ";
                endcase
                K_POWER:case(idx)
                    0:label_char="P";1:label_char="O";2:label_char="W";3:label_char="E";
                    4:label_char="R";5:label_char=" ";6:label_char="1";7:label_char="0";
                    8:label_char="0";9:label_char="0";10:label_char=" ";
                    11:label_char="O";
                    12:label_char=power_on ? "N" : "F";
                    13:label_char=power_on ? " " : "F";
                    default:label_char=" ";
                endcase

                K_ULTIMATE:case(idx)
                    0:label_char="U";1:label_char="L";2:label_char="T";3:label_char="I";
                    4:label_char="M";5:label_char="A";6:label_char="T";7:label_char="E";
                    8:label_char=" ";9:label_char="1";10:label_char="5";11:label_char="0";
                    12:label_char="0";13:label_char=" ";14:label_char="O";
                    15:label_char=power_on ? "N" : "F";
                    16:label_char=power_on ? " " : "F";
                    default:label_char=" ";
                endcase

                K_POWERUP:case(idx)
                    0:label_char="P";1:label_char="O";2:label_char="W";3:label_char="E";
                    4:label_char="R";5:label_char=" ";6:label_char="U";7:label_char="P";
                    8:label_char=" ";9:label_char="O";
                    10:label_char=power_on ? "N" : "F";
                    11:label_char=power_on ? " " : "F";
                    default:label_char=" ";
                endcase
                K_LUCKYBOX:case(idx)
                    0:label_char="L";1:label_char="U";2:label_char="C";3:label_char="K";
                    4:label_char="Y";5:label_char=" ";6:label_char="B";7:label_char="O";
                    8:label_char="X";9:label_char=" ";10:label_char="1";11:label_char="0";
                    12:label_char="0";13:label_char="0";default:label_char=" ";
                endcase
                default:label_char=" ";
            endcase
        end
    endfunction

    reg [2:0] kind;
    reg selected_surface;
    reg [9:0] bminx,bmaxx,bw,text_w,x0,dx;
    reg [6:0] logical_x;
    reg [14:0] char_mult;
    reg [4:0] char_idx,chars;
    reg [2:0] char_col;
    reg [7:0] ch;
    reg [4:0] row_bits;

    reg signed [11:0] approx_horizon_y;
    reg signed [11:0] text_y0;
    reg signed [12:0] row_delta;

    always @(*) begin
        label_pixel=0; kind=K_NONE; selected_surface=0;
        bminx=0;bmaxx=0;bw=0;text_w=0;x0=0;dx=0;
        logical_x=0;char_mult=0;char_idx=0;chars=0;char_col=0;
        ch=" ";row_bits=0;

        approx_horizon_y=12'sd240+($signed(camera_pitch)<<<3);
        text_y0=approx_horizon_y-12'sd3;
        row_delta=$signed({3'b000,pixel_y})-$signed(text_y0);

        if(shotgun_column&&shot_valid)begin
            kind=K_SHOTGUN;selected_surface=shotgun_surface_pixel;
            bminx=shot_bminx;bmaxx=shot_bmaxx;
        end else if(rifle_column&&rifle_valid)begin
            kind=K_RIFLE;selected_surface=rifle_surface_pixel;
            bminx=rifle_bminx;bmaxx=rifle_bmaxx;
        end else if(power_column&&power_valid)begin
            kind=K_POWER;selected_surface=power_surface_pixel;
            bminx=power_bminx;bmaxx=power_bmaxx;
        end else if(ultimate_column&&ultimate_valid)begin
            kind=K_ULTIMATE;selected_surface=ultimate_surface_pixel;
            bminx=ultimate_bminx;bmaxx=ultimate_bmaxx;
        end else if(powerup_column&&powerup_valid)begin
            kind=K_POWERUP;selected_surface=powerup_surface_pixel;
            bminx=powerup_bminx;bmaxx=powerup_bmaxx;
        end else if(luckybox_column&&lucky_valid)begin
            kind=K_LUCKYBOX;selected_surface=luckybox_surface_pixel;
            bminx=lucky_bminx;bmaxx=lucky_bmaxx;
        end

        if((kind!=K_NONE)&&selected_surface)begin
            bw=bmaxx-bminx+1;
            chars=label_length(kind,power_on);
            text_w=(chars<<2)+(chars<<1);

            if((bw>=text_w)&&(row_delta>=0)&&(row_delta<=6))begin
                x0=bminx+((bw-text_w)>>1);
                if((pixel_x>=x0)&&(pixel_x<(x0+text_w)))begin
                    dx=pixel_x-x0;
                    logical_x=dx[6:0];
                    char_mult=({8'd0,logical_x}<<5)+
                              ({8'd0,logical_x}<<3)+
                              ({8'd0,logical_x}<<1)+
                               {8'd0,logical_x};
                    char_idx=char_mult[14:8];
                    char_col=logical_x-((char_idx<<2)+(char_idx<<1));
                    ch=label_char(kind,char_idx);
                    row_bits=glyph_row(ch,row_delta[2:0]);
                    if(char_col<5)begin
                        case(char_col)
                            0:label_pixel=row_bits[4];
                            1:label_pixel=row_bits[3];
                            2:label_pixel=row_bits[2];
                            3:label_pixel=row_bits[1];
                            default:label_pixel=row_bits[0];
                        endcase
                    end
                end
            end
        end
    end
endmodule
