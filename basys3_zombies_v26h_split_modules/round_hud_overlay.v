// ============================================================================
// ROUND HUD: orange R + two digits at upper-right.
// ============================================================================
module round_hud_overlay (
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire [6:0] round_value,
    output reg round_pixel
);
    reg [3:0] tens, ones, digit_value;
    reg [4:0] lx,ly;
    reg inside_digit;
    reg [6:0] segments;
    integer rv;
    function [6:0] digit_segments;
        input [3:0] d;
        begin
            case(d)
                0:digit_segments=7'b1111110;1:digit_segments=7'b0110000;2:digit_segments=7'b1101101;3:digit_segments=7'b1111001;4:digit_segments=7'b0110011;
                5:digit_segments=7'b1011011;6:digit_segments=7'b1011111;7:digit_segments=7'b1110000;8:digit_segments=7'b1111111;9:digit_segments=7'b1111011;
                default:digit_segments=0;
            endcase
        end
    endfunction
    always @(*) begin
        rv=round_value; if(rv>99) rv=99; tens=rv/10; ones=rv%10;
        round_pixel=0; inside_digit=0; digit_value=0; lx=0;ly=0;
        if((pixel_y>=14)&&(pixel_y<36)) begin
            ly=pixel_y-14;
            // Simple block R at x=578..589.
            if((pixel_x>=578)&&(pixel_x<590)) begin
                lx=pixel_x-578;
                if((lx<=1) || ((ly<=1)&&(lx<=9)) || ((ly>=10)&&(ly<=11)&&(lx<=9)) ||
                   ((lx>=10)&&(ly>=2)&&(ly<=9)) || ((ly>=12)&&(lx>=6)&&(lx<=9))) round_pixel=1'b1;
            end
            else if((pixel_x>=596)&&(pixel_x<608)) begin digit_value=tens; lx=pixel_x-596; inside_digit=1; end
            else if((pixel_x>=612)&&(pixel_x<624)) begin digit_value=ones; lx=pixel_x-612; inside_digit=1; end
        end
        segments=digit_segments(digit_value);
        if(inside_digit) begin
            if(segments[6]&&(ly<=1)&&(lx>=2)&&(lx<=9)) round_pixel=1;
            if(segments[5]&&(lx>=10)&&(ly>=2)&&(ly<=9)) round_pixel=1;
            if(segments[4]&&(lx>=10)&&(ly>=12)&&(ly<=19)) round_pixel=1;
            if(segments[3]&&(ly>=20)&&(lx>=2)&&(lx<=9)) round_pixel=1;
            if(segments[2]&&(lx<=1)&&(ly>=12)&&(ly<=19)) round_pixel=1;
            if(segments[1]&&(lx<=1)&&(ly>=2)&&(ly<=9)) round_pixel=1;
            if(segments[0]&&(ly>=10)&&(ly<=11)&&(lx>=2)&&(lx<=9)) round_pixel=1;
        end
    end
endmodule
