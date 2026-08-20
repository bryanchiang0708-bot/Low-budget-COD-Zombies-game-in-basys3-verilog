module zombie_pill_pixel (
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire signed [11:0] screen_x,
    input wire signed [11:0] screen_y,
    input wire [7:0] radius,
    input wire visible,
    output wire pixel_on
);
    wire signed [12:0] dx=$signed({3'b000,pixel_x})-$signed(screen_x);
    wire signed [12:0] dy=$signed({3'b000,pixel_y})-$signed(screen_y);
    wire [12:0] ax=dx[12]?-dx:dx;
    wire [12:0] ay=dy[12]?-dy:dy;
    wire [12:0] r={5'd0,radius};
    wire [13:0] hh=({6'd0,radius}<<1);
    wire [13:0] capoff={1'b0,ay}-{1'b0,r};
    wire body=visible && (ay<=r) && (ax<=r);
    wire cap=visible && (ay>r) && ({1'b0,ay}<=hh) && (({1'b0,ax}+capoff)<={1'b0,r});
    assign pixel_on=body||cap;
endmodule
