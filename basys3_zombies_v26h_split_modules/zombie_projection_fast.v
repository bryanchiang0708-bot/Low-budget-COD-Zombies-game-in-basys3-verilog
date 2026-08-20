// ============================================================================
// FAST DISPLAY-ONLY ZOMBIE PROJECTION
// No variable divider. Perspective uses power-of-two depth buckets.
// ============================================================================
module zombie_projection_fast (
    input wire signed [15:0] camera_x,
    input wire signed [15:0] camera_y,
    input wire signed [15:0] camera_z,
    input wire [7:0] camera_yaw,
    input wire signed [8:0] camera_pitch,
    input wire signed [15:0] target_x,
    input wire signed [15:0] target_y,
    input wire signed [15:0] target_z,
    output reg signed [11:0] screen_x,
    output reg signed [11:0] screen_y,
    output reg [7:0] screen_radius,
    output reg visible
);
    wire signed [8:0] sin_yaw, cos_yaw;
    trig_q17 t(.angle(camera_yaw),.sin_value(sin_yaw),.cos_value(cos_yaw));
    wire signed [16:0] rel_x=$signed(target_x)-$signed(camera_x);
    wire signed [16:0] rel_y=$signed(target_y)-$signed(camera_y);
    wire signed [16:0] rel_z=$signed(target_z)-$signed(camera_z);
    wire signed [31:0] yaw_x_num=$signed(rel_x)*$signed(cos_yaw)-$signed(rel_z)*$signed(sin_yaw);
    wire signed [31:0] yaw_z_num=$signed(rel_x)*$signed(sin_yaw)+$signed(rel_z)*$signed(cos_yaw);
    wire signed [17:0] cam_x=yaw_x_num>>>7;
    wire signed [18:0] depth=yaw_z_num>>>7;

    function signed [11:0] pitch_shift_lut;
        input [5:0] m;
        begin
            case(m)
                0:pitch_shift_lut=0;1:pitch_shift_lut=6;2:pitch_shift_lut=13;3:pitch_shift_lut=19;4:pitch_shift_lut=25;5:pitch_shift_lut=32;6:pitch_shift_lut=38;7:pitch_shift_lut=44;
                8:pitch_shift_lut=51;9:pitch_shift_lut=57;10:pitch_shift_lut=64;11:pitch_shift_lut=71;12:pitch_shift_lut=78;13:pitch_shift_lut=85;14:pitch_shift_lut=92;15:pitch_shift_lut=99;
                16:pitch_shift_lut=106;17:pitch_shift_lut=113;18:pitch_shift_lut=121;19:pitch_shift_lut=129;20:pitch_shift_lut=137;21:pitch_shift_lut=145;22:pitch_shift_lut=153;23:pitch_shift_lut=162;
                24:pitch_shift_lut=171;25:pitch_shift_lut=180;26:pitch_shift_lut=190;27:pitch_shift_lut=200;28:pitch_shift_lut=210;29:pitch_shift_lut=221;30:pitch_shift_lut=232;31:pitch_shift_lut=244;
                32:pitch_shift_lut=256;33:pitch_shift_lut=269;34:pitch_shift_lut=282;35:pitch_shift_lut=297;36:pitch_shift_lut=312;37:pitch_shift_lut=328;38:pitch_shift_lut=345;39:pitch_shift_lut=363;
                40:pitch_shift_lut=383;41:pitch_shift_lut=404;default:pitch_shift_lut=427;
            endcase
        end
    endfunction
    reg [5:0] pmag; reg signed [11:0] horizon;
    reg signed [31:0] pxoff, pyoff; reg [7:0] rr;
    always @(*) begin
        if(camera_pitch<0) begin pmag=((-camera_pitch)>42)?42:-camera_pitch; horizon=12'sd240-pitch_shift_lut(pmag); end
        else begin pmag=(camera_pitch>42)?42:camera_pitch[5:0]; horizon=12'sd240+pitch_shift_lut(pmag); end
        pxoff=0; pyoff=0; rr=4; visible=0; screen_x=320; screen_y=horizon; screen_radius=4;
        if(depth>24) begin
            if(depth<48) begin pxoff=$signed(cam_x)<<<3; pyoff=$signed(rel_y)<<<3; rr=8'd80; end
            else if(depth<96) begin pxoff=$signed(cam_x)<<<2; pyoff=$signed(rel_y)<<<2; rr=8'd80; end
            else if(depth<192) begin pxoff=$signed(cam_x)<<<1; pyoff=$signed(rel_y)<<<1; rr=8'd48; end
            else if(depth<384) begin pxoff=$signed(cam_x); pyoff=$signed(rel_y); rr=8'd24; end
            else if(depth<768) begin pxoff=$signed(cam_x)>>>1; pyoff=$signed(rel_y)>>>1; rr=8'd12; end
            else if(depth<1536) begin pxoff=$signed(cam_x)>>>2; pyoff=$signed(rel_y)>>>2; rr=8'd6; end
            else begin pxoff=$signed(cam_x)>>>3; pyoff=$signed(rel_y)>>>3; rr=8'd4; end
            screen_x = 12'sd320 + pxoff[11:0];
            screen_y = horizon - pyoff[11:0];
            screen_radius = rr;
            if(($signed(screen_x)+$signed({4'd0,rr})>=0) && ($signed(screen_x)-$signed({4'd0,rr})<640) &&
               ($signed(screen_y)+$signed({4'd0,rr})>=0) && ($signed(screen_y)-$signed({4'd0,rr})<480)) visible=1'b1;
        end
    end
endmodule
