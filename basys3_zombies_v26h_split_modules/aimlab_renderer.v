// ============================================================================
// VGA FIVE-ROOM ZOMBIES MAP RENDERER
// Repeating 64x64 world-unit grid panels.
// Wall geometry comes from the cached 20-segment map raycaster.
// Blue ceiling, red walls, green/gray floor retained for easy geometry testing.
// ============================================================================
module aimlab_renderer (
    input  wire [9:0]         pixel_x,
    input  wire [9:0]         pixel_y,

    input  wire signed [15:0] camera_x,
    input  wire signed [15:0] camera_y,
    input  wire signed [15:0] camera_z,
    input  wire [7:0]         camera_yaw,
    input  wire signed [8:0]  camera_pitch,

    input  wire [15:0]        map_wall_depth,
    input  wire               map_wall_valid,

    input  wire               host_alive,
    output reg [11:0]         raw_rgb
);

    // Wall shape is supplied by zombies_map_wall_raycaster.
    // The floor/ceiling still use the existing 64x64 world-unit panel grid,
    // which now directly matches one map grid block.

    localparam signed [15:0] CEILING_Y   =  16'sd256;
    localparam [15:0] BASE_EYE_Y = 16'd80;

    localparam integer FOCAL_LENGTH = 256;
    localparam integer RAY_SCALE    = 32768;  // 128 trig scale * 256 focal
    localparam integer NEAR_DEPTH   = 8;

    // ------------------------------------------------------------------------
    // Camera yaw trig
    // ------------------------------------------------------------------------
    wire signed [8:0] sin_yaw;
    wire signed [8:0] cos_yaw;

    trig_q17 room_yaw_trig (
        .angle(camera_yaw),
        .sin_value(sin_yaw),
        .cos_value(cos_yaw)
    );

    // Current horizontal pixel offset from screen center.
    reg signed [11:0] screen_offset_x;

    // ------------------------------------------------------------------------
    // Dedicated wall ray angle.
    //
    // Approximate ~102 degree horizontal FOV:
    // screen edge (+/-320 px) -> about +/-36 phase steps (~+/-50.6 deg).
    //
    // Using a normalized angular ray here avoids the unstable per-pixel
    // variable-divider chain that was previously used for wall intersections.
    // ------------------------------------------------------------------------
    wire signed [31:0] wall_angle_mul =
        $signed(screen_offset_x) * 32'sd29;

    wire signed [12:0] wall_angle_offset =
        $signed(wall_angle_mul) >>> 8;

    wire [7:0] wall_ray_angle =
        camera_yaw + wall_angle_offset[7:0];

    wire [7:0] wall_offset_angle =
        wall_angle_offset[7:0];

    wire signed [8:0] wall_ray_sin;
    wire signed [8:0] wall_ray_cos;
    wire signed [8:0] wall_offset_sin_unused;
    wire signed [8:0] wall_offset_cos;

    trig_q17 wall_ray_trig (
        .angle(wall_ray_angle),
        .sin_value(wall_ray_sin),
        .cos_value(wall_ray_cos)
    );

    trig_q17 wall_offset_trig (
        .angle(wall_offset_angle),
        .sin_value(wall_offset_sin_unused),
        .cos_value(wall_offset_cos)
    );

    // ------------------------------------------------------------------------
    // Current screen-column ray in world X/Z
    //
    // center ray:
    //   forward = (sin(yaw), cos(yaw))
    //
    // off-center pixels add the camera-right vector.
    // ------------------------------------------------------------------------
    reg signed [31:0] ray_x_q7;
    reg signed [31:0] ray_z_q7;

    // ------------------------------------------------------------------------
    // Ray / wall intersection
    // ------------------------------------------------------------------------
    reg signed [16:0] x_plane_delta;
    reg signed [16:0] z_plane_delta;

    reg signed [47:0] x_depth_num;
    reg signed [47:0] z_depth_num;

    reg signed [31:0] x_wall_depth;
    reg signed [31:0] z_wall_depth;

    reg signed [31:0] x_wall_hit_z;
    reg signed [31:0] z_wall_hit_x;

    reg x_wall_valid;
    reg z_wall_valid;

    reg signed [31:0] wall_depth;
    reg signed [31:0] wall_u_world;
    reg [1:0] wall_side;

    reg signed [31:0] wall_ray_distance;
    reg signed [47:0] wall_forward_mul;

    reg [7:0]  abs_wall_sin;
    reg [7:0]  abs_wall_cos;
    reg [15:0] inv_wall_sin_q8;
    reg [15:0] inv_wall_cos_q8;

    reg [8:0]  wall_depth_index;
    reg [15:0] wall_proj_scale;

    // 0 = +X wall
    // 1 = -X wall
    // 2 = +Z wall
    // 3 = -Z wall

    // ------------------------------------------------------------------------
    // Vertical room projection
    // ------------------------------------------------------------------------
    reg signed [11:0] horizon_y;
    reg signed [31:0] wall_top;
    reg signed [31:0] wall_bottom;
    reg signed [31:0] wall_y_world;

    // ------------------------------------------------------------------------
    // Floor / ceiling world-space grid projection
    // ------------------------------------------------------------------------
    reg signed [12:0] horizon_delta;
    reg [8:0] plane_dy;

    reg [15:0] floor_depth_base;
    reg [15:0] floor_depth;
    reg [16:0] ceiling_depth;
    (* use_dsp = "no" *) reg [31:0] floor_depth_product;
    (* use_dsp = "no" *) reg [31:0] ceiling_depth_product;
    reg [15:0] camera_y_unsigned;
    reg [15:0] ceiling_height_from_camera;

    reg signed [47:0] floor_x_mul;
    reg signed [47:0] floor_z_mul;
    reg signed [47:0] ceil_x_mul;
    reg signed [47:0] ceil_z_mul;

    reg signed [31:0] plane_world_x;
    reg signed [31:0] plane_world_z;


    // ------------------------------------------------------------------------
    // Tile helpers
    // ------------------------------------------------------------------------
    reg plane_grid_line;
    reg plane_checker;

    reg [5:0] wall_u_mod;
    reg [5:0] wall_y_mod;
    reg [5:0] plane_x_mod;
    reg [5:0] plane_z_mod;

    // ------------------------------------------------------------------------
    // Fabric-only 16x9 unsigned multiplier.
    //
    // V14 originally used:
    //     floor_depth_base * camera_y
    //     floor_depth_base * ceiling_height
    //
    // Those two variable multipliers were inferred into two extra DSP48E1s,
    // pushing the Basys 3 over its 90-DSP limit. This shift/add version keeps
    // the same integer result but is built from LUT/carry fabric instead.
    // ------------------------------------------------------------------------
    function [31:0] mul_u16_u9_fabric;
        input [15:0] a;
        input [8:0]  b;
        integer i;
        reg [31:0] acc;
        begin
            acc = 32'd0;
            for (i = 0; i < 9; i = i + 1) begin
                if (b[i])
                    acc = acc + ({16'd0, a} << i);
            end
            mul_u16_u9_fabric = acc;
        end
    endfunction

    // ------------------------------------------------------------------------
    // Fixed center crosshair
    // ------------------------------------------------------------------------
    // Minimal 2x2 center reticle.
    wire crosshair =
        (pixel_x >= 10'd319) && (pixel_x <= 10'd320) &&
        (pixel_y >= 10'd239) && (pixel_y <= 10'd240);

    wire host_warning =
        (!host_alive) &&
        (pixel_x >= 10'd8) && (pixel_x <= 10'd18) &&
        (pixel_y >= 10'd8) && (pixel_y <= 10'd18);

    // ------------------------------------------------------------------------
    // Floor-distance reciprocal-style lookup.
    //
    // Returns base forward depth for an 80-unit standing eye height.
    // V14 scales this lookup by the live camera_y for jumping, and separately
    // by (CEILING_Y - camera_y) for the ceiling.
    // ------------------------------------------------------------------------

    // ------------------------------------------------------------------------
    // Reciprocal of |sin/cos| for wall intersections.
    // Output Q8 represents (128 / magnitude).
    // ------------------------------------------------------------------------
    function [15:0] recip_trig_q8;
        input [7:0] magnitude;
        begin
            case (magnitude)
                8'd0: recip_trig_q8 = 16'd65535;
                8'd1: recip_trig_q8 = 16'd32768;
                8'd2: recip_trig_q8 = 16'd16384;
                8'd3: recip_trig_q8 = 16'd10923;
                8'd4: recip_trig_q8 = 16'd8192;
                8'd5: recip_trig_q8 = 16'd6554;
                8'd6: recip_trig_q8 = 16'd5461;
                8'd7: recip_trig_q8 = 16'd4681;
                8'd8: recip_trig_q8 = 16'd4096;
                8'd9: recip_trig_q8 = 16'd3641;
                8'd10: recip_trig_q8 = 16'd3277;
                8'd11: recip_trig_q8 = 16'd2979;
                8'd12: recip_trig_q8 = 16'd2731;
                8'd13: recip_trig_q8 = 16'd2521;
                8'd14: recip_trig_q8 = 16'd2341;
                8'd15: recip_trig_q8 = 16'd2185;
                8'd16: recip_trig_q8 = 16'd2048;
                8'd17: recip_trig_q8 = 16'd1928;
                8'd18: recip_trig_q8 = 16'd1820;
                8'd19: recip_trig_q8 = 16'd1725;
                8'd20: recip_trig_q8 = 16'd1638;
                8'd21: recip_trig_q8 = 16'd1560;
                8'd22: recip_trig_q8 = 16'd1489;
                8'd23: recip_trig_q8 = 16'd1425;
                8'd24: recip_trig_q8 = 16'd1365;
                8'd25: recip_trig_q8 = 16'd1311;
                8'd26: recip_trig_q8 = 16'd1260;
                8'd27: recip_trig_q8 = 16'd1214;
                8'd28: recip_trig_q8 = 16'd1170;
                8'd29: recip_trig_q8 = 16'd1130;
                8'd30: recip_trig_q8 = 16'd1092;
                8'd31: recip_trig_q8 = 16'd1057;
                8'd32: recip_trig_q8 = 16'd1024;
                8'd33: recip_trig_q8 = 16'd993;
                8'd34: recip_trig_q8 = 16'd964;
                8'd35: recip_trig_q8 = 16'd936;
                8'd36: recip_trig_q8 = 16'd910;
                8'd37: recip_trig_q8 = 16'd886;
                8'd38: recip_trig_q8 = 16'd862;
                8'd39: recip_trig_q8 = 16'd840;
                8'd40: recip_trig_q8 = 16'd819;
                8'd41: recip_trig_q8 = 16'd799;
                8'd42: recip_trig_q8 = 16'd780;
                8'd43: recip_trig_q8 = 16'd762;
                8'd44: recip_trig_q8 = 16'd745;
                8'd45: recip_trig_q8 = 16'd728;
                8'd46: recip_trig_q8 = 16'd712;
                8'd47: recip_trig_q8 = 16'd697;
                8'd48: recip_trig_q8 = 16'd683;
                8'd49: recip_trig_q8 = 16'd669;
                8'd50: recip_trig_q8 = 16'd655;
                8'd51: recip_trig_q8 = 16'd643;
                8'd52: recip_trig_q8 = 16'd630;
                8'd53: recip_trig_q8 = 16'd618;
                8'd54: recip_trig_q8 = 16'd607;
                8'd55: recip_trig_q8 = 16'd596;
                8'd56: recip_trig_q8 = 16'd585;
                8'd57: recip_trig_q8 = 16'd575;
                8'd58: recip_trig_q8 = 16'd565;
                8'd59: recip_trig_q8 = 16'd555;
                8'd60: recip_trig_q8 = 16'd546;
                8'd61: recip_trig_q8 = 16'd537;
                8'd62: recip_trig_q8 = 16'd529;
                8'd63: recip_trig_q8 = 16'd520;
                8'd64: recip_trig_q8 = 16'd512;
                8'd65: recip_trig_q8 = 16'd504;
                8'd66: recip_trig_q8 = 16'd496;
                8'd67: recip_trig_q8 = 16'd489;
                8'd68: recip_trig_q8 = 16'd482;
                8'd69: recip_trig_q8 = 16'd475;
                8'd70: recip_trig_q8 = 16'd468;
                8'd71: recip_trig_q8 = 16'd462;
                8'd72: recip_trig_q8 = 16'd455;
                8'd73: recip_trig_q8 = 16'd449;
                8'd74: recip_trig_q8 = 16'd443;
                8'd75: recip_trig_q8 = 16'd437;
                8'd76: recip_trig_q8 = 16'd431;
                8'd77: recip_trig_q8 = 16'd426;
                8'd78: recip_trig_q8 = 16'd420;
                8'd79: recip_trig_q8 = 16'd415;
                8'd80: recip_trig_q8 = 16'd410;
                8'd81: recip_trig_q8 = 16'd405;
                8'd82: recip_trig_q8 = 16'd400;
                8'd83: recip_trig_q8 = 16'd395;
                8'd84: recip_trig_q8 = 16'd390;
                8'd85: recip_trig_q8 = 16'd386;
                8'd86: recip_trig_q8 = 16'd381;
                8'd87: recip_trig_q8 = 16'd377;
                8'd88: recip_trig_q8 = 16'd372;
                8'd89: recip_trig_q8 = 16'd368;
                8'd90: recip_trig_q8 = 16'd364;
                8'd91: recip_trig_q8 = 16'd360;
                8'd92: recip_trig_q8 = 16'd356;
                8'd93: recip_trig_q8 = 16'd352;
                8'd94: recip_trig_q8 = 16'd349;
                8'd95: recip_trig_q8 = 16'd345;
                8'd96: recip_trig_q8 = 16'd341;
                8'd97: recip_trig_q8 = 16'd338;
                8'd98: recip_trig_q8 = 16'd334;
                8'd99: recip_trig_q8 = 16'd331;
                8'd100: recip_trig_q8 = 16'd328;
                8'd101: recip_trig_q8 = 16'd324;
                8'd102: recip_trig_q8 = 16'd321;
                8'd103: recip_trig_q8 = 16'd318;
                8'd104: recip_trig_q8 = 16'd315;
                8'd105: recip_trig_q8 = 16'd312;
                8'd106: recip_trig_q8 = 16'd309;
                8'd107: recip_trig_q8 = 16'd306;
                8'd108: recip_trig_q8 = 16'd303;
                8'd109: recip_trig_q8 = 16'd301;
                8'd110: recip_trig_q8 = 16'd298;
                8'd111: recip_trig_q8 = 16'd295;
                8'd112: recip_trig_q8 = 16'd293;
                8'd113: recip_trig_q8 = 16'd290;
                8'd114: recip_trig_q8 = 16'd287;
                8'd115: recip_trig_q8 = 16'd285;
                8'd116: recip_trig_q8 = 16'd282;
                8'd117: recip_trig_q8 = 16'd280;
                8'd118: recip_trig_q8 = 16'd278;
                8'd119: recip_trig_q8 = 16'd275;
                8'd120: recip_trig_q8 = 16'd273;
                8'd121: recip_trig_q8 = 16'd271;
                8'd122: recip_trig_q8 = 16'd269;
                8'd123: recip_trig_q8 = 16'd266;
                8'd124: recip_trig_q8 = 16'd264;
                8'd125: recip_trig_q8 = 16'd262;
                8'd126: recip_trig_q8 = 16'd260;
                8'd127: recip_trig_q8 = 16'd258;
                8'd128: recip_trig_q8 = 16'd256;
                default: recip_trig_q8 = 16'd256;
            endcase
        end
    endfunction

    // ------------------------------------------------------------------------
    // Perspective wall scale:
    //     Q8 scale ~= (FOCAL_LENGTH / depth) * 256
    //
    // Index is depth/4, which is more than precise enough for wall edges and
    // removes two more variable divisions from the pixel renderer.
    // ------------------------------------------------------------------------
    function [15:0] wall_scale_q8;
        input [8:0] depth_index;
        begin
            case (depth_index)
                9'd0: wall_scale_q8 = 16'd8192;
                9'd1: wall_scale_q8 = 16'd8192;
                9'd2: wall_scale_q8 = 16'd8192;
                9'd3: wall_scale_q8 = 16'd5461;
                9'd4: wall_scale_q8 = 16'd4096;
                9'd5: wall_scale_q8 = 16'd3277;
                9'd6: wall_scale_q8 = 16'd2731;
                9'd7: wall_scale_q8 = 16'd2341;
                9'd8: wall_scale_q8 = 16'd2048;
                9'd9: wall_scale_q8 = 16'd1820;
                9'd10: wall_scale_q8 = 16'd1638;
                9'd11: wall_scale_q8 = 16'd1489;
                9'd12: wall_scale_q8 = 16'd1365;
                9'd13: wall_scale_q8 = 16'd1260;
                9'd14: wall_scale_q8 = 16'd1170;
                9'd15: wall_scale_q8 = 16'd1092;
                9'd16: wall_scale_q8 = 16'd1024;
                9'd17: wall_scale_q8 = 16'd964;
                9'd18: wall_scale_q8 = 16'd910;
                9'd19: wall_scale_q8 = 16'd862;
                9'd20: wall_scale_q8 = 16'd819;
                9'd21: wall_scale_q8 = 16'd780;
                9'd22: wall_scale_q8 = 16'd745;
                9'd23: wall_scale_q8 = 16'd712;
                9'd24: wall_scale_q8 = 16'd683;
                9'd25: wall_scale_q8 = 16'd655;
                9'd26: wall_scale_q8 = 16'd630;
                9'd27: wall_scale_q8 = 16'd607;
                9'd28: wall_scale_q8 = 16'd585;
                9'd29: wall_scale_q8 = 16'd565;
                9'd30: wall_scale_q8 = 16'd546;
                9'd31: wall_scale_q8 = 16'd529;
                9'd32: wall_scale_q8 = 16'd512;
                9'd33: wall_scale_q8 = 16'd496;
                9'd34: wall_scale_q8 = 16'd482;
                9'd35: wall_scale_q8 = 16'd468;
                9'd36: wall_scale_q8 = 16'd455;
                9'd37: wall_scale_q8 = 16'd443;
                9'd38: wall_scale_q8 = 16'd431;
                9'd39: wall_scale_q8 = 16'd420;
                9'd40: wall_scale_q8 = 16'd410;
                9'd41: wall_scale_q8 = 16'd400;
                9'd42: wall_scale_q8 = 16'd390;
                9'd43: wall_scale_q8 = 16'd381;
                9'd44: wall_scale_q8 = 16'd372;
                9'd45: wall_scale_q8 = 16'd364;
                9'd46: wall_scale_q8 = 16'd356;
                9'd47: wall_scale_q8 = 16'd349;
                9'd48: wall_scale_q8 = 16'd341;
                9'd49: wall_scale_q8 = 16'd334;
                9'd50: wall_scale_q8 = 16'd328;
                9'd51: wall_scale_q8 = 16'd321;
                9'd52: wall_scale_q8 = 16'd315;
                9'd53: wall_scale_q8 = 16'd309;
                9'd54: wall_scale_q8 = 16'd303;
                9'd55: wall_scale_q8 = 16'd298;
                9'd56: wall_scale_q8 = 16'd293;
                9'd57: wall_scale_q8 = 16'd287;
                9'd58: wall_scale_q8 = 16'd282;
                9'd59: wall_scale_q8 = 16'd278;
                9'd60: wall_scale_q8 = 16'd273;
                9'd61: wall_scale_q8 = 16'd269;
                9'd62: wall_scale_q8 = 16'd264;
                9'd63: wall_scale_q8 = 16'd260;
                9'd64: wall_scale_q8 = 16'd256;
                9'd65: wall_scale_q8 = 16'd252;
                9'd66: wall_scale_q8 = 16'd248;
                9'd67: wall_scale_q8 = 16'd245;
                9'd68: wall_scale_q8 = 16'd241;
                9'd69: wall_scale_q8 = 16'd237;
                9'd70: wall_scale_q8 = 16'd234;
                9'd71: wall_scale_q8 = 16'd231;
                9'd72: wall_scale_q8 = 16'd228;
                9'd73: wall_scale_q8 = 16'd224;
                9'd74: wall_scale_q8 = 16'd221;
                9'd75: wall_scale_q8 = 16'd218;
                9'd76: wall_scale_q8 = 16'd216;
                9'd77: wall_scale_q8 = 16'd213;
                9'd78: wall_scale_q8 = 16'd210;
                9'd79: wall_scale_q8 = 16'd207;
                9'd80: wall_scale_q8 = 16'd205;
                9'd81: wall_scale_q8 = 16'd202;
                9'd82: wall_scale_q8 = 16'd200;
                9'd83: wall_scale_q8 = 16'd197;
                9'd84: wall_scale_q8 = 16'd195;
                9'd85: wall_scale_q8 = 16'd193;
                9'd86: wall_scale_q8 = 16'd191;
                9'd87: wall_scale_q8 = 16'd188;
                9'd88: wall_scale_q8 = 16'd186;
                9'd89: wall_scale_q8 = 16'd184;
                9'd90: wall_scale_q8 = 16'd182;
                9'd91: wall_scale_q8 = 16'd180;
                9'd92: wall_scale_q8 = 16'd178;
                9'd93: wall_scale_q8 = 16'd176;
                9'd94: wall_scale_q8 = 16'd174;
                9'd95: wall_scale_q8 = 16'd172;
                9'd96: wall_scale_q8 = 16'd171;
                9'd97: wall_scale_q8 = 16'd169;
                9'd98: wall_scale_q8 = 16'd167;
                9'd99: wall_scale_q8 = 16'd165;
                9'd100: wall_scale_q8 = 16'd164;
                9'd101: wall_scale_q8 = 16'd162;
                9'd102: wall_scale_q8 = 16'd161;
                9'd103: wall_scale_q8 = 16'd159;
                9'd104: wall_scale_q8 = 16'd158;
                9'd105: wall_scale_q8 = 16'd156;
                9'd106: wall_scale_q8 = 16'd155;
                9'd107: wall_scale_q8 = 16'd153;
                9'd108: wall_scale_q8 = 16'd152;
                9'd109: wall_scale_q8 = 16'd150;
                9'd110: wall_scale_q8 = 16'd149;
                9'd111: wall_scale_q8 = 16'd148;
                9'd112: wall_scale_q8 = 16'd146;
                9'd113: wall_scale_q8 = 16'd145;
                9'd114: wall_scale_q8 = 16'd144;
                9'd115: wall_scale_q8 = 16'd142;
                9'd116: wall_scale_q8 = 16'd141;
                9'd117: wall_scale_q8 = 16'd140;
                9'd118: wall_scale_q8 = 16'd139;
                9'd119: wall_scale_q8 = 16'd138;
                9'd120: wall_scale_q8 = 16'd137;
                9'd121: wall_scale_q8 = 16'd135;
                9'd122: wall_scale_q8 = 16'd134;
                9'd123: wall_scale_q8 = 16'd133;
                9'd124: wall_scale_q8 = 16'd132;
                9'd125: wall_scale_q8 = 16'd131;
                9'd126: wall_scale_q8 = 16'd130;
                9'd127: wall_scale_q8 = 16'd129;
                9'd128: wall_scale_q8 = 16'd128;
                9'd129: wall_scale_q8 = 16'd127;
                9'd130: wall_scale_q8 = 16'd126;
                9'd131: wall_scale_q8 = 16'd125;
                9'd132: wall_scale_q8 = 16'd124;
                9'd133: wall_scale_q8 = 16'd123;
                9'd134: wall_scale_q8 = 16'd122;
                9'd135: wall_scale_q8 = 16'd121;
                9'd136: wall_scale_q8 = 16'd120;
                9'd137: wall_scale_q8 = 16'd120;
                9'd138: wall_scale_q8 = 16'd119;
                9'd139: wall_scale_q8 = 16'd118;
                9'd140: wall_scale_q8 = 16'd117;
                9'd141: wall_scale_q8 = 16'd116;
                9'd142: wall_scale_q8 = 16'd115;
                9'd143: wall_scale_q8 = 16'd115;
                9'd144: wall_scale_q8 = 16'd114;
                9'd145: wall_scale_q8 = 16'd113;
                9'd146: wall_scale_q8 = 16'd112;
                9'd147: wall_scale_q8 = 16'd111;
                9'd148: wall_scale_q8 = 16'd111;
                9'd149: wall_scale_q8 = 16'd110;
                9'd150: wall_scale_q8 = 16'd109;
                9'd151: wall_scale_q8 = 16'd109;
                9'd152: wall_scale_q8 = 16'd108;
                9'd153: wall_scale_q8 = 16'd107;
                9'd154: wall_scale_q8 = 16'd106;
                9'd155: wall_scale_q8 = 16'd106;
                9'd156: wall_scale_q8 = 16'd105;
                9'd157: wall_scale_q8 = 16'd104;
                9'd158: wall_scale_q8 = 16'd104;
                9'd159: wall_scale_q8 = 16'd103;
                9'd160: wall_scale_q8 = 16'd102;
                9'd161: wall_scale_q8 = 16'd102;
                9'd162: wall_scale_q8 = 16'd101;
                9'd163: wall_scale_q8 = 16'd101;
                9'd164: wall_scale_q8 = 16'd100;
                9'd165: wall_scale_q8 = 16'd99;
                9'd166: wall_scale_q8 = 16'd99;
                9'd167: wall_scale_q8 = 16'd98;
                9'd168: wall_scale_q8 = 16'd98;
                9'd169: wall_scale_q8 = 16'd97;
                9'd170: wall_scale_q8 = 16'd96;
                9'd171: wall_scale_q8 = 16'd96;
                9'd172: wall_scale_q8 = 16'd95;
                9'd173: wall_scale_q8 = 16'd95;
                9'd174: wall_scale_q8 = 16'd94;
                9'd175: wall_scale_q8 = 16'd94;
                9'd176: wall_scale_q8 = 16'd93;
                9'd177: wall_scale_q8 = 16'd93;
                9'd178: wall_scale_q8 = 16'd92;
                9'd179: wall_scale_q8 = 16'd92;
                9'd180: wall_scale_q8 = 16'd91;
                9'd181: wall_scale_q8 = 16'd91;
                9'd182: wall_scale_q8 = 16'd90;
                9'd183: wall_scale_q8 = 16'd90;
                9'd184: wall_scale_q8 = 16'd89;
                9'd185: wall_scale_q8 = 16'd89;
                9'd186: wall_scale_q8 = 16'd88;
                9'd187: wall_scale_q8 = 16'd88;
                9'd188: wall_scale_q8 = 16'd87;
                9'd189: wall_scale_q8 = 16'd87;
                9'd190: wall_scale_q8 = 16'd86;
                9'd191: wall_scale_q8 = 16'd86;
                9'd192: wall_scale_q8 = 16'd85;
                9'd193: wall_scale_q8 = 16'd85;
                9'd194: wall_scale_q8 = 16'd84;
                9'd195: wall_scale_q8 = 16'd84;
                9'd196: wall_scale_q8 = 16'd84;
                9'd197: wall_scale_q8 = 16'd83;
                9'd198: wall_scale_q8 = 16'd83;
                9'd199: wall_scale_q8 = 16'd82;
                9'd200: wall_scale_q8 = 16'd82;
                9'd201: wall_scale_q8 = 16'd82;
                9'd202: wall_scale_q8 = 16'd81;
                9'd203: wall_scale_q8 = 16'd81;
                9'd204: wall_scale_q8 = 16'd80;
                9'd205: wall_scale_q8 = 16'd80;
                9'd206: wall_scale_q8 = 16'd80;
                9'd207: wall_scale_q8 = 16'd79;
                9'd208: wall_scale_q8 = 16'd79;
                9'd209: wall_scale_q8 = 16'd78;
                9'd210: wall_scale_q8 = 16'd78;
                9'd211: wall_scale_q8 = 16'd78;
                9'd212: wall_scale_q8 = 16'd77;
                9'd213: wall_scale_q8 = 16'd77;
                9'd214: wall_scale_q8 = 16'd77;
                9'd215: wall_scale_q8 = 16'd76;
                9'd216: wall_scale_q8 = 16'd76;
                9'd217: wall_scale_q8 = 16'd76;
                9'd218: wall_scale_q8 = 16'd75;
                9'd219: wall_scale_q8 = 16'd75;
                9'd220: wall_scale_q8 = 16'd74;
                9'd221: wall_scale_q8 = 16'd74;
                9'd222: wall_scale_q8 = 16'd74;
                9'd223: wall_scale_q8 = 16'd73;
                9'd224: wall_scale_q8 = 16'd73;
                9'd225: wall_scale_q8 = 16'd73;
                9'd226: wall_scale_q8 = 16'd72;
                9'd227: wall_scale_q8 = 16'd72;
                9'd228: wall_scale_q8 = 16'd72;
                9'd229: wall_scale_q8 = 16'd72;
                9'd230: wall_scale_q8 = 16'd71;
                9'd231: wall_scale_q8 = 16'd71;
                9'd232: wall_scale_q8 = 16'd71;
                9'd233: wall_scale_q8 = 16'd70;
                9'd234: wall_scale_q8 = 16'd70;
                9'd235: wall_scale_q8 = 16'd70;
                9'd236: wall_scale_q8 = 16'd69;
                9'd237: wall_scale_q8 = 16'd69;
                9'd238: wall_scale_q8 = 16'd69;
                9'd239: wall_scale_q8 = 16'd69;
                9'd240: wall_scale_q8 = 16'd68;
                9'd241: wall_scale_q8 = 16'd68;
                9'd242: wall_scale_q8 = 16'd68;
                9'd243: wall_scale_q8 = 16'd67;
                9'd244: wall_scale_q8 = 16'd67;
                9'd245: wall_scale_q8 = 16'd67;
                9'd246: wall_scale_q8 = 16'd67;
                9'd247: wall_scale_q8 = 16'd66;
                9'd248: wall_scale_q8 = 16'd66;
                9'd249: wall_scale_q8 = 16'd66;
                9'd250: wall_scale_q8 = 16'd66;
                9'd251: wall_scale_q8 = 16'd65;
                9'd252: wall_scale_q8 = 16'd65;
                9'd253: wall_scale_q8 = 16'd65;
                9'd254: wall_scale_q8 = 16'd65;
                9'd255: wall_scale_q8 = 16'd64;
                9'd256: wall_scale_q8 = 16'd64;
                9'd257: wall_scale_q8 = 16'd64;
                9'd258: wall_scale_q8 = 16'd64;
                9'd259: wall_scale_q8 = 16'd63;
                9'd260: wall_scale_q8 = 16'd63;
                9'd261: wall_scale_q8 = 16'd63;
                9'd262: wall_scale_q8 = 16'd63;
                9'd263: wall_scale_q8 = 16'd62;
                9'd264: wall_scale_q8 = 16'd62;
                9'd265: wall_scale_q8 = 16'd62;
                9'd266: wall_scale_q8 = 16'd62;
                9'd267: wall_scale_q8 = 16'd61;
                9'd268: wall_scale_q8 = 16'd61;
                9'd269: wall_scale_q8 = 16'd61;
                9'd270: wall_scale_q8 = 16'd61;
                9'd271: wall_scale_q8 = 16'd60;
                9'd272: wall_scale_q8 = 16'd60;
                9'd273: wall_scale_q8 = 16'd60;
                9'd274: wall_scale_q8 = 16'd60;
                9'd275: wall_scale_q8 = 16'd60;
                9'd276: wall_scale_q8 = 16'd59;
                9'd277: wall_scale_q8 = 16'd59;
                9'd278: wall_scale_q8 = 16'd59;
                9'd279: wall_scale_q8 = 16'd59;
                9'd280: wall_scale_q8 = 16'd59;
                9'd281: wall_scale_q8 = 16'd58;
                9'd282: wall_scale_q8 = 16'd58;
                9'd283: wall_scale_q8 = 16'd58;
                9'd284: wall_scale_q8 = 16'd58;
                9'd285: wall_scale_q8 = 16'd57;
                9'd286: wall_scale_q8 = 16'd57;
                9'd287: wall_scale_q8 = 16'd57;
                9'd288: wall_scale_q8 = 16'd57;
                9'd289: wall_scale_q8 = 16'd57;
                9'd290: wall_scale_q8 = 16'd56;
                9'd291: wall_scale_q8 = 16'd56;
                9'd292: wall_scale_q8 = 16'd56;
                9'd293: wall_scale_q8 = 16'd56;
                9'd294: wall_scale_q8 = 16'd56;
                9'd295: wall_scale_q8 = 16'd56;
                9'd296: wall_scale_q8 = 16'd55;
                9'd297: wall_scale_q8 = 16'd55;
                9'd298: wall_scale_q8 = 16'd55;
                9'd299: wall_scale_q8 = 16'd55;
                9'd300: wall_scale_q8 = 16'd55;
                9'd301: wall_scale_q8 = 16'd54;
                9'd302: wall_scale_q8 = 16'd54;
                9'd303: wall_scale_q8 = 16'd54;
                9'd304: wall_scale_q8 = 16'd54;
                9'd305: wall_scale_q8 = 16'd54;
                9'd306: wall_scale_q8 = 16'd54;
                9'd307: wall_scale_q8 = 16'd53;
                9'd308: wall_scale_q8 = 16'd53;
                9'd309: wall_scale_q8 = 16'd53;
                9'd310: wall_scale_q8 = 16'd53;
                9'd311: wall_scale_q8 = 16'd53;
                9'd312: wall_scale_q8 = 16'd53;
                9'd313: wall_scale_q8 = 16'd52;
                9'd314: wall_scale_q8 = 16'd52;
                9'd315: wall_scale_q8 = 16'd52;
                9'd316: wall_scale_q8 = 16'd52;
                9'd317: wall_scale_q8 = 16'd52;
                9'd318: wall_scale_q8 = 16'd52;
                9'd319: wall_scale_q8 = 16'd51;
                9'd320: wall_scale_q8 = 16'd51;
                9'd321: wall_scale_q8 = 16'd51;
                9'd322: wall_scale_q8 = 16'd51;
                9'd323: wall_scale_q8 = 16'd51;
                9'd324: wall_scale_q8 = 16'd51;
                9'd325: wall_scale_q8 = 16'd50;
                9'd326: wall_scale_q8 = 16'd50;
                9'd327: wall_scale_q8 = 16'd50;
                9'd328: wall_scale_q8 = 16'd50;
                9'd329: wall_scale_q8 = 16'd50;
                9'd330: wall_scale_q8 = 16'd50;
                9'd331: wall_scale_q8 = 16'd49;
                9'd332: wall_scale_q8 = 16'd49;
                9'd333: wall_scale_q8 = 16'd49;
                9'd334: wall_scale_q8 = 16'd49;
                9'd335: wall_scale_q8 = 16'd49;
                9'd336: wall_scale_q8 = 16'd49;
                9'd337: wall_scale_q8 = 16'd49;
                9'd338: wall_scale_q8 = 16'd48;
                9'd339: wall_scale_q8 = 16'd48;
                9'd340: wall_scale_q8 = 16'd48;
                9'd341: wall_scale_q8 = 16'd48;
                9'd342: wall_scale_q8 = 16'd48;
                9'd343: wall_scale_q8 = 16'd48;
                9'd344: wall_scale_q8 = 16'd48;
                9'd345: wall_scale_q8 = 16'd47;
                9'd346: wall_scale_q8 = 16'd47;
                9'd347: wall_scale_q8 = 16'd47;
                9'd348: wall_scale_q8 = 16'd47;
                9'd349: wall_scale_q8 = 16'd47;
                9'd350: wall_scale_q8 = 16'd47;
                9'd351: wall_scale_q8 = 16'd47;
                9'd352: wall_scale_q8 = 16'd47;
                9'd353: wall_scale_q8 = 16'd46;
                9'd354: wall_scale_q8 = 16'd46;
                9'd355: wall_scale_q8 = 16'd46;
                9'd356: wall_scale_q8 = 16'd46;
                9'd357: wall_scale_q8 = 16'd46;
                9'd358: wall_scale_q8 = 16'd46;
                9'd359: wall_scale_q8 = 16'd46;
                9'd360: wall_scale_q8 = 16'd46;
                9'd361: wall_scale_q8 = 16'd45;
                9'd362: wall_scale_q8 = 16'd45;
                9'd363: wall_scale_q8 = 16'd45;
                9'd364: wall_scale_q8 = 16'd45;
                9'd365: wall_scale_q8 = 16'd45;
                9'd366: wall_scale_q8 = 16'd45;
                9'd367: wall_scale_q8 = 16'd45;
                9'd368: wall_scale_q8 = 16'd45;
                9'd369: wall_scale_q8 = 16'd44;
                9'd370: wall_scale_q8 = 16'd44;
                9'd371: wall_scale_q8 = 16'd44;
                9'd372: wall_scale_q8 = 16'd44;
                9'd373: wall_scale_q8 = 16'd44;
                9'd374: wall_scale_q8 = 16'd44;
                9'd375: wall_scale_q8 = 16'd44;
                9'd376: wall_scale_q8 = 16'd44;
                9'd377: wall_scale_q8 = 16'd43;
                9'd378: wall_scale_q8 = 16'd43;
                9'd379: wall_scale_q8 = 16'd43;
                9'd380: wall_scale_q8 = 16'd43;
                9'd381: wall_scale_q8 = 16'd43;
                9'd382: wall_scale_q8 = 16'd43;
                9'd383: wall_scale_q8 = 16'd43;
                9'd384: wall_scale_q8 = 16'd43;
                9'd385: wall_scale_q8 = 16'd43;
                9'd386: wall_scale_q8 = 16'd42;
                9'd387: wall_scale_q8 = 16'd42;
                9'd388: wall_scale_q8 = 16'd42;
                9'd389: wall_scale_q8 = 16'd42;
                9'd390: wall_scale_q8 = 16'd42;
                9'd391: wall_scale_q8 = 16'd42;
                9'd392: wall_scale_q8 = 16'd42;
                9'd393: wall_scale_q8 = 16'd42;
                9'd394: wall_scale_q8 = 16'd42;
                9'd395: wall_scale_q8 = 16'd41;
                9'd396: wall_scale_q8 = 16'd41;
                9'd397: wall_scale_q8 = 16'd41;
                9'd398: wall_scale_q8 = 16'd41;
                9'd399: wall_scale_q8 = 16'd41;
                9'd400: wall_scale_q8 = 16'd41;
                9'd401: wall_scale_q8 = 16'd41;
                9'd402: wall_scale_q8 = 16'd41;
                9'd403: wall_scale_q8 = 16'd41;
                9'd404: wall_scale_q8 = 16'd41;
                9'd405: wall_scale_q8 = 16'd40;
                9'd406: wall_scale_q8 = 16'd40;
                9'd407: wall_scale_q8 = 16'd40;
                9'd408: wall_scale_q8 = 16'd40;
                9'd409: wall_scale_q8 = 16'd40;
                9'd410: wall_scale_q8 = 16'd40;
                9'd411: wall_scale_q8 = 16'd40;
                9'd412: wall_scale_q8 = 16'd40;
                9'd413: wall_scale_q8 = 16'd40;
                9'd414: wall_scale_q8 = 16'd40;
                9'd415: wall_scale_q8 = 16'd39;
                9'd416: wall_scale_q8 = 16'd39;
                9'd417: wall_scale_q8 = 16'd39;
                9'd418: wall_scale_q8 = 16'd39;
                9'd419: wall_scale_q8 = 16'd39;
                9'd420: wall_scale_q8 = 16'd39;
                9'd421: wall_scale_q8 = 16'd39;
                9'd422: wall_scale_q8 = 16'd39;
                9'd423: wall_scale_q8 = 16'd39;
                9'd424: wall_scale_q8 = 16'd39;
                9'd425: wall_scale_q8 = 16'd39;
                9'd426: wall_scale_q8 = 16'd38;
                9'd427: wall_scale_q8 = 16'd38;
                9'd428: wall_scale_q8 = 16'd38;
                9'd429: wall_scale_q8 = 16'd38;
                9'd430: wall_scale_q8 = 16'd38;
                9'd431: wall_scale_q8 = 16'd38;
                9'd432: wall_scale_q8 = 16'd38;
                9'd433: wall_scale_q8 = 16'd38;
                9'd434: wall_scale_q8 = 16'd38;
                9'd435: wall_scale_q8 = 16'd38;
                9'd436: wall_scale_q8 = 16'd38;
                9'd437: wall_scale_q8 = 16'd37;
                9'd438: wall_scale_q8 = 16'd37;
                9'd439: wall_scale_q8 = 16'd37;
                9'd440: wall_scale_q8 = 16'd37;
                9'd441: wall_scale_q8 = 16'd37;
                9'd442: wall_scale_q8 = 16'd37;
                9'd443: wall_scale_q8 = 16'd37;
                9'd444: wall_scale_q8 = 16'd37;
                9'd445: wall_scale_q8 = 16'd37;
                9'd446: wall_scale_q8 = 16'd37;
                9'd447: wall_scale_q8 = 16'd37;
                9'd448: wall_scale_q8 = 16'd37;
                9'd449: wall_scale_q8 = 16'd36;
                9'd450: wall_scale_q8 = 16'd36;
                9'd451: wall_scale_q8 = 16'd36;
                9'd452: wall_scale_q8 = 16'd36;
                9'd453: wall_scale_q8 = 16'd36;
                9'd454: wall_scale_q8 = 16'd36;
                9'd455: wall_scale_q8 = 16'd36;
                9'd456: wall_scale_q8 = 16'd36;
                9'd457: wall_scale_q8 = 16'd36;
                9'd458: wall_scale_q8 = 16'd36;
                9'd459: wall_scale_q8 = 16'd36;
                9'd460: wall_scale_q8 = 16'd36;
                9'd461: wall_scale_q8 = 16'd36;
                9'd462: wall_scale_q8 = 16'd35;
                9'd463: wall_scale_q8 = 16'd35;
                9'd464: wall_scale_q8 = 16'd35;
                9'd465: wall_scale_q8 = 16'd35;
                9'd466: wall_scale_q8 = 16'd35;
                9'd467: wall_scale_q8 = 16'd35;
                9'd468: wall_scale_q8 = 16'd35;
                9'd469: wall_scale_q8 = 16'd35;
                9'd470: wall_scale_q8 = 16'd35;
                9'd471: wall_scale_q8 = 16'd35;
                9'd472: wall_scale_q8 = 16'd35;
                9'd473: wall_scale_q8 = 16'd35;
                9'd474: wall_scale_q8 = 16'd35;
                9'd475: wall_scale_q8 = 16'd34;
                9'd476: wall_scale_q8 = 16'd34;
                9'd477: wall_scale_q8 = 16'd34;
                9'd478: wall_scale_q8 = 16'd34;
                9'd479: wall_scale_q8 = 16'd34;
                9'd480: wall_scale_q8 = 16'd34;
                9'd481: wall_scale_q8 = 16'd34;
                9'd482: wall_scale_q8 = 16'd34;
                9'd483: wall_scale_q8 = 16'd34;
                9'd484: wall_scale_q8 = 16'd34;
                9'd485: wall_scale_q8 = 16'd34;
                9'd486: wall_scale_q8 = 16'd34;
                9'd487: wall_scale_q8 = 16'd34;
                9'd488: wall_scale_q8 = 16'd34;
                9'd489: wall_scale_q8 = 16'd34;
                9'd490: wall_scale_q8 = 16'd33;
                9'd491: wall_scale_q8 = 16'd33;
                9'd492: wall_scale_q8 = 16'd33;
                9'd493: wall_scale_q8 = 16'd33;
                9'd494: wall_scale_q8 = 16'd33;
                9'd495: wall_scale_q8 = 16'd33;
                9'd496: wall_scale_q8 = 16'd33;
                9'd497: wall_scale_q8 = 16'd33;
                9'd498: wall_scale_q8 = 16'd33;
                9'd499: wall_scale_q8 = 16'd33;
                9'd500: wall_scale_q8 = 16'd33;
                9'd501: wall_scale_q8 = 16'd33;
                9'd502: wall_scale_q8 = 16'd33;
                9'd503: wall_scale_q8 = 16'd33;
                9'd504: wall_scale_q8 = 16'd33;
                9'd505: wall_scale_q8 = 16'd32;
                9'd506: wall_scale_q8 = 16'd32;
                9'd507: wall_scale_q8 = 16'd32;
                9'd508: wall_scale_q8 = 16'd32;
                9'd509: wall_scale_q8 = 16'd32;
                9'd510: wall_scale_q8 = 16'd32;
                9'd511: wall_scale_q8 = 16'd32;
                default: wall_scale_q8 = 16'd32;
            endcase
        end
    endfunction


    // ------------------------------------------------------------------------
    // FPS pitch projection.
    //
    // 256 camera phase units = 360 degrees.
    // Horizon shift ~= focal_length * tan(pitch), focal_length = 256.
    //
    // This gives a real perspective-style vertical look rather than moving
    // the horizon a fixed two pixels per pitch step.
    // ------------------------------------------------------------------------
    function signed [11:0] pitch_shift_lut;
        input [5:0] magnitude;
        begin
            case (magnitude)
                6'd0: pitch_shift_lut = 12'sd0;
                6'd1: pitch_shift_lut = 12'sd6;
                6'd2: pitch_shift_lut = 12'sd13;
                6'd3: pitch_shift_lut = 12'sd19;
                6'd4: pitch_shift_lut = 12'sd25;
                6'd5: pitch_shift_lut = 12'sd32;
                6'd6: pitch_shift_lut = 12'sd38;
                6'd7: pitch_shift_lut = 12'sd44;
                6'd8: pitch_shift_lut = 12'sd51;
                6'd9: pitch_shift_lut = 12'sd57;
                6'd10: pitch_shift_lut = 12'sd64;
                6'd11: pitch_shift_lut = 12'sd71;
                6'd12: pitch_shift_lut = 12'sd78;
                6'd13: pitch_shift_lut = 12'sd85;
                6'd14: pitch_shift_lut = 12'sd92;
                6'd15: pitch_shift_lut = 12'sd99;
                6'd16: pitch_shift_lut = 12'sd106;
                6'd17: pitch_shift_lut = 12'sd113;
                6'd18: pitch_shift_lut = 12'sd121;
                6'd19: pitch_shift_lut = 12'sd129;
                6'd20: pitch_shift_lut = 12'sd137;
                6'd21: pitch_shift_lut = 12'sd145;
                6'd22: pitch_shift_lut = 12'sd153;
                6'd23: pitch_shift_lut = 12'sd162;
                6'd24: pitch_shift_lut = 12'sd171;
                6'd25: pitch_shift_lut = 12'sd180;
                6'd26: pitch_shift_lut = 12'sd190;
                6'd27: pitch_shift_lut = 12'sd200;
                6'd28: pitch_shift_lut = 12'sd210;
                6'd29: pitch_shift_lut = 12'sd221;
                6'd30: pitch_shift_lut = 12'sd232;
                6'd31: pitch_shift_lut = 12'sd244;
                6'd32: pitch_shift_lut = 12'sd256;
                6'd33: pitch_shift_lut = 12'sd269;
                6'd34: pitch_shift_lut = 12'sd282;
                6'd35: pitch_shift_lut = 12'sd297;
                6'd36: pitch_shift_lut = 12'sd312;
                6'd37: pitch_shift_lut = 12'sd328;
                6'd38: pitch_shift_lut = 12'sd345;
                6'd39: pitch_shift_lut = 12'sd363;
                6'd40: pitch_shift_lut = 12'sd383;
                6'd41: pitch_shift_lut = 12'sd404;
                6'd42: pitch_shift_lut = 12'sd427;
                default: pitch_shift_lut = 12'sd427;
            endcase
        end
    endfunction

    function signed [11:0] fps_horizon_y;
        input signed [8:0] pitch;
        reg [5:0] mag;
        reg signed [11:0] shift;
        begin
            if (pitch < 0) begin
                if ((-pitch) > 9'sd42)
                    mag = 6'd42;
                else
                    mag = -pitch;

                shift = -pitch_shift_lut(mag);
            end else begin
                if (pitch > 9'sd42)
                    mag = 6'd42;
                else
                    mag = pitch[5:0];

                shift = pitch_shift_lut(mag);
            end

            fps_horizon_y = 12'sd240 + shift;
        end
    endfunction

    function [15:0] floor_depth_lut;
        input [8:0] d;
        begin
            case (d)
                9'd0: floor_depth_lut = 16'd32767;
                9'd1: floor_depth_lut = 16'd20480;
                9'd2: floor_depth_lut = 16'd10240;
                9'd3: floor_depth_lut = 16'd6827;
                9'd4: floor_depth_lut = 16'd5120;
                9'd5: floor_depth_lut = 16'd4096;
                9'd6: floor_depth_lut = 16'd3413;
                9'd7: floor_depth_lut = 16'd2926;
                9'd8: floor_depth_lut = 16'd2560;
                9'd9: floor_depth_lut = 16'd2276;
                9'd10: floor_depth_lut = 16'd2048;
                9'd11: floor_depth_lut = 16'd1862;
                9'd12: floor_depth_lut = 16'd1707;
                9'd13: floor_depth_lut = 16'd1575;
                9'd14: floor_depth_lut = 16'd1463;
                9'd15: floor_depth_lut = 16'd1365;
                9'd16: floor_depth_lut = 16'd1280;
                9'd17: floor_depth_lut = 16'd1205;
                9'd18: floor_depth_lut = 16'd1138;
                9'd19: floor_depth_lut = 16'd1078;
                9'd20: floor_depth_lut = 16'd1024;
                9'd21: floor_depth_lut = 16'd975;
                9'd22: floor_depth_lut = 16'd931;
                9'd23: floor_depth_lut = 16'd890;
                9'd24: floor_depth_lut = 16'd853;
                9'd25: floor_depth_lut = 16'd819;
                9'd26: floor_depth_lut = 16'd788;
                9'd27: floor_depth_lut = 16'd759;
                9'd28: floor_depth_lut = 16'd731;
                9'd29: floor_depth_lut = 16'd706;
                9'd30: floor_depth_lut = 16'd683;
                9'd31: floor_depth_lut = 16'd661;
                9'd32: floor_depth_lut = 16'd640;
                9'd33: floor_depth_lut = 16'd621;
                9'd34: floor_depth_lut = 16'd602;
                9'd35: floor_depth_lut = 16'd585;
                9'd36: floor_depth_lut = 16'd569;
                9'd37: floor_depth_lut = 16'd554;
                9'd38: floor_depth_lut = 16'd539;
                9'd39: floor_depth_lut = 16'd525;
                9'd40: floor_depth_lut = 16'd512;
                9'd41: floor_depth_lut = 16'd500;
                9'd42: floor_depth_lut = 16'd488;
                9'd43: floor_depth_lut = 16'd476;
                9'd44: floor_depth_lut = 16'd465;
                9'd45: floor_depth_lut = 16'd455;
                9'd46: floor_depth_lut = 16'd445;
                9'd47: floor_depth_lut = 16'd436;
                9'd48: floor_depth_lut = 16'd427;
                9'd49: floor_depth_lut = 16'd418;
                9'd50: floor_depth_lut = 16'd410;
                9'd51: floor_depth_lut = 16'd402;
                9'd52: floor_depth_lut = 16'd394;
                9'd53: floor_depth_lut = 16'd386;
                9'd54: floor_depth_lut = 16'd379;
                9'd55: floor_depth_lut = 16'd372;
                9'd56: floor_depth_lut = 16'd366;
                9'd57: floor_depth_lut = 16'd359;
                9'd58: floor_depth_lut = 16'd353;
                9'd59: floor_depth_lut = 16'd347;
                9'd60: floor_depth_lut = 16'd341;
                9'd61: floor_depth_lut = 16'd336;
                9'd62: floor_depth_lut = 16'd330;
                9'd63: floor_depth_lut = 16'd325;
                9'd64: floor_depth_lut = 16'd320;
                9'd65: floor_depth_lut = 16'd315;
                9'd66: floor_depth_lut = 16'd310;
                9'd67: floor_depth_lut = 16'd306;
                9'd68: floor_depth_lut = 16'd301;
                9'd69: floor_depth_lut = 16'd297;
                9'd70: floor_depth_lut = 16'd293;
                9'd71: floor_depth_lut = 16'd288;
                9'd72: floor_depth_lut = 16'd284;
                9'd73: floor_depth_lut = 16'd281;
                9'd74: floor_depth_lut = 16'd277;
                9'd75: floor_depth_lut = 16'd273;
                9'd76: floor_depth_lut = 16'd269;
                9'd77: floor_depth_lut = 16'd266;
                9'd78: floor_depth_lut = 16'd263;
                9'd79: floor_depth_lut = 16'd259;
                9'd80: floor_depth_lut = 16'd256;
                9'd81: floor_depth_lut = 16'd253;
                9'd82: floor_depth_lut = 16'd250;
                9'd83: floor_depth_lut = 16'd247;
                9'd84: floor_depth_lut = 16'd244;
                9'd85: floor_depth_lut = 16'd241;
                9'd86: floor_depth_lut = 16'd238;
                9'd87: floor_depth_lut = 16'd235;
                9'd88: floor_depth_lut = 16'd233;
                9'd89: floor_depth_lut = 16'd230;
                9'd90: floor_depth_lut = 16'd228;
                9'd91: floor_depth_lut = 16'd225;
                9'd92: floor_depth_lut = 16'd223;
                9'd93: floor_depth_lut = 16'd220;
                9'd94: floor_depth_lut = 16'd218;
                9'd95: floor_depth_lut = 16'd216;
                9'd96: floor_depth_lut = 16'd213;
                9'd97: floor_depth_lut = 16'd211;
                9'd98: floor_depth_lut = 16'd209;
                9'd99: floor_depth_lut = 16'd207;
                9'd100: floor_depth_lut = 16'd205;
                9'd101: floor_depth_lut = 16'd203;
                9'd102: floor_depth_lut = 16'd201;
                9'd103: floor_depth_lut = 16'd199;
                9'd104: floor_depth_lut = 16'd197;
                9'd105: floor_depth_lut = 16'd195;
                9'd106: floor_depth_lut = 16'd193;
                9'd107: floor_depth_lut = 16'd191;
                9'd108: floor_depth_lut = 16'd190;
                9'd109: floor_depth_lut = 16'd188;
                9'd110: floor_depth_lut = 16'd186;
                9'd111: floor_depth_lut = 16'd185;
                9'd112: floor_depth_lut = 16'd183;
                9'd113: floor_depth_lut = 16'd181;
                9'd114: floor_depth_lut = 16'd180;
                9'd115: floor_depth_lut = 16'd178;
                9'd116: floor_depth_lut = 16'd177;
                9'd117: floor_depth_lut = 16'd175;
                9'd118: floor_depth_lut = 16'd174;
                9'd119: floor_depth_lut = 16'd172;
                9'd120: floor_depth_lut = 16'd171;
                9'd121: floor_depth_lut = 16'd169;
                9'd122: floor_depth_lut = 16'd168;
                9'd123: floor_depth_lut = 16'd167;
                9'd124: floor_depth_lut = 16'd165;
                9'd125: floor_depth_lut = 16'd164;
                9'd126: floor_depth_lut = 16'd163;
                9'd127: floor_depth_lut = 16'd161;
                9'd128: floor_depth_lut = 16'd160;
                9'd129: floor_depth_lut = 16'd159;
                9'd130: floor_depth_lut = 16'd158;
                9'd131: floor_depth_lut = 16'd156;
                9'd132: floor_depth_lut = 16'd155;
                9'd133: floor_depth_lut = 16'd154;
                9'd134: floor_depth_lut = 16'd153;
                9'd135: floor_depth_lut = 16'd152;
                9'd136: floor_depth_lut = 16'd151;
                9'd137: floor_depth_lut = 16'd149;
                9'd138: floor_depth_lut = 16'd148;
                9'd139: floor_depth_lut = 16'd147;
                9'd140: floor_depth_lut = 16'd146;
                9'd141: floor_depth_lut = 16'd145;
                9'd142: floor_depth_lut = 16'd144;
                9'd143: floor_depth_lut = 16'd143;
                9'd144: floor_depth_lut = 16'd142;
                9'd145: floor_depth_lut = 16'd141;
                9'd146: floor_depth_lut = 16'd140;
                9'd147: floor_depth_lut = 16'd139;
                9'd148: floor_depth_lut = 16'd138;
                9'd149: floor_depth_lut = 16'd137;
                9'd150: floor_depth_lut = 16'd137;
                9'd151: floor_depth_lut = 16'd136;
                9'd152: floor_depth_lut = 16'd135;
                9'd153: floor_depth_lut = 16'd134;
                9'd154: floor_depth_lut = 16'd133;
                9'd155: floor_depth_lut = 16'd132;
                9'd156: floor_depth_lut = 16'd131;
                9'd157: floor_depth_lut = 16'd130;
                9'd158: floor_depth_lut = 16'd130;
                9'd159: floor_depth_lut = 16'd129;
                9'd160: floor_depth_lut = 16'd128;
                9'd161: floor_depth_lut = 16'd127;
                9'd162: floor_depth_lut = 16'd126;
                9'd163: floor_depth_lut = 16'd126;
                9'd164: floor_depth_lut = 16'd125;
                9'd165: floor_depth_lut = 16'd124;
                9'd166: floor_depth_lut = 16'd123;
                9'd167: floor_depth_lut = 16'd123;
                9'd168: floor_depth_lut = 16'd122;
                9'd169: floor_depth_lut = 16'd121;
                9'd170: floor_depth_lut = 16'd120;
                9'd171: floor_depth_lut = 16'd120;
                9'd172: floor_depth_lut = 16'd119;
                9'd173: floor_depth_lut = 16'd118;
                9'd174: floor_depth_lut = 16'd118;
                9'd175: floor_depth_lut = 16'd117;
                9'd176: floor_depth_lut = 16'd116;
                9'd177: floor_depth_lut = 16'd116;
                9'd178: floor_depth_lut = 16'd115;
                9'd179: floor_depth_lut = 16'd114;
                9'd180: floor_depth_lut = 16'd114;
                9'd181: floor_depth_lut = 16'd113;
                9'd182: floor_depth_lut = 16'd113;
                9'd183: floor_depth_lut = 16'd112;
                9'd184: floor_depth_lut = 16'd111;
                9'd185: floor_depth_lut = 16'd111;
                9'd186: floor_depth_lut = 16'd110;
                9'd187: floor_depth_lut = 16'd110;
                9'd188: floor_depth_lut = 16'd109;
                9'd189: floor_depth_lut = 16'd108;
                9'd190: floor_depth_lut = 16'd108;
                9'd191: floor_depth_lut = 16'd107;
                9'd192: floor_depth_lut = 16'd107;
                9'd193: floor_depth_lut = 16'd106;
                9'd194: floor_depth_lut = 16'd106;
                9'd195: floor_depth_lut = 16'd105;
                9'd196: floor_depth_lut = 16'd104;
                9'd197: floor_depth_lut = 16'd104;
                9'd198: floor_depth_lut = 16'd103;
                9'd199: floor_depth_lut = 16'd103;
                9'd200: floor_depth_lut = 16'd102;
                9'd201: floor_depth_lut = 16'd102;
                9'd202: floor_depth_lut = 16'd101;
                9'd203: floor_depth_lut = 16'd101;
                9'd204: floor_depth_lut = 16'd100;
                9'd205: floor_depth_lut = 16'd100;
                9'd206: floor_depth_lut = 16'd99;
                9'd207: floor_depth_lut = 16'd99;
                9'd208: floor_depth_lut = 16'd98;
                9'd209: floor_depth_lut = 16'd98;
                9'd210: floor_depth_lut = 16'd98;
                9'd211: floor_depth_lut = 16'd97;
                9'd212: floor_depth_lut = 16'd97;
                9'd213: floor_depth_lut = 16'd96;
                9'd214: floor_depth_lut = 16'd96;
                9'd215: floor_depth_lut = 16'd95;
                9'd216: floor_depth_lut = 16'd95;
                9'd217: floor_depth_lut = 16'd94;
                9'd218: floor_depth_lut = 16'd94;
                9'd219: floor_depth_lut = 16'd94;
                9'd220: floor_depth_lut = 16'd93;
                9'd221: floor_depth_lut = 16'd93;
                9'd222: floor_depth_lut = 16'd92;
                9'd223: floor_depth_lut = 16'd92;
                9'd224: floor_depth_lut = 16'd91;
                9'd225: floor_depth_lut = 16'd91;
                9'd226: floor_depth_lut = 16'd91;
                9'd227: floor_depth_lut = 16'd90;
                9'd228: floor_depth_lut = 16'd90;
                9'd229: floor_depth_lut = 16'd89;
                9'd230: floor_depth_lut = 16'd89;
                9'd231: floor_depth_lut = 16'd89;
                9'd232: floor_depth_lut = 16'd88;
                9'd233: floor_depth_lut = 16'd88;
                9'd234: floor_depth_lut = 16'd88;
                9'd235: floor_depth_lut = 16'd87;
                9'd236: floor_depth_lut = 16'd87;
                9'd237: floor_depth_lut = 16'd86;
                9'd238: floor_depth_lut = 16'd86;
                9'd239: floor_depth_lut = 16'd86;
                9'd240: floor_depth_lut = 16'd85;
                9'd241: floor_depth_lut = 16'd85;
                9'd242: floor_depth_lut = 16'd85;
                9'd243: floor_depth_lut = 16'd84;
                9'd244: floor_depth_lut = 16'd84;
                9'd245: floor_depth_lut = 16'd84;
                9'd246: floor_depth_lut = 16'd83;
                9'd247: floor_depth_lut = 16'd83;
                9'd248: floor_depth_lut = 16'd83;
                9'd249: floor_depth_lut = 16'd82;
                9'd250: floor_depth_lut = 16'd82;
                9'd251: floor_depth_lut = 16'd82;
                9'd252: floor_depth_lut = 16'd81;
                9'd253: floor_depth_lut = 16'd81;
                9'd254: floor_depth_lut = 16'd81;
                9'd255: floor_depth_lut = 16'd80;
                9'd256: floor_depth_lut = 16'd80;
                9'd257: floor_depth_lut = 16'd80;
                9'd258: floor_depth_lut = 16'd79;
                9'd259: floor_depth_lut = 16'd79;
                9'd260: floor_depth_lut = 16'd79;
                9'd261: floor_depth_lut = 16'd78;
                9'd262: floor_depth_lut = 16'd78;
                9'd263: floor_depth_lut = 16'd78;
                9'd264: floor_depth_lut = 16'd78;
                9'd265: floor_depth_lut = 16'd77;
                9'd266: floor_depth_lut = 16'd77;
                9'd267: floor_depth_lut = 16'd77;
                9'd268: floor_depth_lut = 16'd76;
                9'd269: floor_depth_lut = 16'd76;
                9'd270: floor_depth_lut = 16'd76;
                9'd271: floor_depth_lut = 16'd76;
                9'd272: floor_depth_lut = 16'd75;
                9'd273: floor_depth_lut = 16'd75;
                9'd274: floor_depth_lut = 16'd75;
                9'd275: floor_depth_lut = 16'd74;
                9'd276: floor_depth_lut = 16'd74;
                9'd277: floor_depth_lut = 16'd74;
                9'd278: floor_depth_lut = 16'd74;
                9'd279: floor_depth_lut = 16'd73;
                9'd280: floor_depth_lut = 16'd73;
                9'd281: floor_depth_lut = 16'd73;
                9'd282: floor_depth_lut = 16'd73;
                9'd283: floor_depth_lut = 16'd72;
                9'd284: floor_depth_lut = 16'd72;
                9'd285: floor_depth_lut = 16'd72;
                9'd286: floor_depth_lut = 16'd72;
                9'd287: floor_depth_lut = 16'd71;
                9'd288: floor_depth_lut = 16'd71;
                9'd289: floor_depth_lut = 16'd71;
                9'd290: floor_depth_lut = 16'd71;
                9'd291: floor_depth_lut = 16'd70;
                9'd292: floor_depth_lut = 16'd70;
                9'd293: floor_depth_lut = 16'd70;
                9'd294: floor_depth_lut = 16'd70;
                9'd295: floor_depth_lut = 16'd69;
                9'd296: floor_depth_lut = 16'd69;
                9'd297: floor_depth_lut = 16'd69;
                9'd298: floor_depth_lut = 16'd69;
                9'd299: floor_depth_lut = 16'd68;
                9'd300: floor_depth_lut = 16'd68;
                9'd301: floor_depth_lut = 16'd68;
                9'd302: floor_depth_lut = 16'd68;
                9'd303: floor_depth_lut = 16'd68;
                9'd304: floor_depth_lut = 16'd67;
                9'd305: floor_depth_lut = 16'd67;
                9'd306: floor_depth_lut = 16'd67;
                9'd307: floor_depth_lut = 16'd67;
                9'd308: floor_depth_lut = 16'd66;
                9'd309: floor_depth_lut = 16'd66;
                9'd310: floor_depth_lut = 16'd66;
                9'd311: floor_depth_lut = 16'd66;
                9'd312: floor_depth_lut = 16'd66;
                9'd313: floor_depth_lut = 16'd65;
                9'd314: floor_depth_lut = 16'd65;
                9'd315: floor_depth_lut = 16'd65;
                9'd316: floor_depth_lut = 16'd65;
                9'd317: floor_depth_lut = 16'd65;
                9'd318: floor_depth_lut = 16'd64;
                9'd319: floor_depth_lut = 16'd64;
                9'd320: floor_depth_lut = 16'd64;
                9'd321: floor_depth_lut = 16'd64;
                9'd322: floor_depth_lut = 16'd64;
                9'd323: floor_depth_lut = 16'd63;
                9'd324: floor_depth_lut = 16'd63;
                9'd325: floor_depth_lut = 16'd63;
                9'd326: floor_depth_lut = 16'd63;
                9'd327: floor_depth_lut = 16'd63;
                9'd328: floor_depth_lut = 16'd62;
                9'd329: floor_depth_lut = 16'd62;
                9'd330: floor_depth_lut = 16'd62;
                9'd331: floor_depth_lut = 16'd62;
                9'd332: floor_depth_lut = 16'd62;
                9'd333: floor_depth_lut = 16'd62;
                9'd334: floor_depth_lut = 16'd61;
                9'd335: floor_depth_lut = 16'd61;
                9'd336: floor_depth_lut = 16'd61;
                9'd337: floor_depth_lut = 16'd61;
                9'd338: floor_depth_lut = 16'd61;
                9'd339: floor_depth_lut = 16'd60;
                9'd340: floor_depth_lut = 16'd60;
                9'd341: floor_depth_lut = 16'd60;
                9'd342: floor_depth_lut = 16'd60;
                9'd343: floor_depth_lut = 16'd60;
                9'd344: floor_depth_lut = 16'd60;
                9'd345: floor_depth_lut = 16'd59;
                9'd346: floor_depth_lut = 16'd59;
                9'd347: floor_depth_lut = 16'd59;
                9'd348: floor_depth_lut = 16'd59;
                9'd349: floor_depth_lut = 16'd59;
                9'd350: floor_depth_lut = 16'd59;
                9'd351: floor_depth_lut = 16'd58;
                9'd352: floor_depth_lut = 16'd58;
                9'd353: floor_depth_lut = 16'd58;
                9'd354: floor_depth_lut = 16'd58;
                9'd355: floor_depth_lut = 16'd58;
                9'd356: floor_depth_lut = 16'd58;
                9'd357: floor_depth_lut = 16'd57;
                9'd358: floor_depth_lut = 16'd57;
                9'd359: floor_depth_lut = 16'd57;
                9'd360: floor_depth_lut = 16'd57;
                9'd361: floor_depth_lut = 16'd57;
                9'd362: floor_depth_lut = 16'd57;
                9'd363: floor_depth_lut = 16'd56;
                9'd364: floor_depth_lut = 16'd56;
                9'd365: floor_depth_lut = 16'd56;
                9'd366: floor_depth_lut = 16'd56;
                9'd367: floor_depth_lut = 16'd56;
                9'd368: floor_depth_lut = 16'd56;
                9'd369: floor_depth_lut = 16'd56;
                9'd370: floor_depth_lut = 16'd55;
                9'd371: floor_depth_lut = 16'd55;
                9'd372: floor_depth_lut = 16'd55;
                9'd373: floor_depth_lut = 16'd55;
                9'd374: floor_depth_lut = 16'd55;
                9'd375: floor_depth_lut = 16'd55;
                9'd376: floor_depth_lut = 16'd54;
                9'd377: floor_depth_lut = 16'd54;
                9'd378: floor_depth_lut = 16'd54;
                9'd379: floor_depth_lut = 16'd54;
                9'd380: floor_depth_lut = 16'd54;
                9'd381: floor_depth_lut = 16'd54;
                9'd382: floor_depth_lut = 16'd54;
                9'd383: floor_depth_lut = 16'd53;
                9'd384: floor_depth_lut = 16'd53;
                9'd385: floor_depth_lut = 16'd53;
                9'd386: floor_depth_lut = 16'd53;
                9'd387: floor_depth_lut = 16'd53;
                9'd388: floor_depth_lut = 16'd53;
                9'd389: floor_depth_lut = 16'd53;
                9'd390: floor_depth_lut = 16'd53;
                9'd391: floor_depth_lut = 16'd52;
                9'd392: floor_depth_lut = 16'd52;
                9'd393: floor_depth_lut = 16'd52;
                9'd394: floor_depth_lut = 16'd52;
                9'd395: floor_depth_lut = 16'd52;
                9'd396: floor_depth_lut = 16'd52;
                9'd397: floor_depth_lut = 16'd52;
                9'd398: floor_depth_lut = 16'd51;
                9'd399: floor_depth_lut = 16'd51;
                9'd400: floor_depth_lut = 16'd51;
                9'd401: floor_depth_lut = 16'd51;
                9'd402: floor_depth_lut = 16'd51;
                9'd403: floor_depth_lut = 16'd51;
                9'd404: floor_depth_lut = 16'd51;
                9'd405: floor_depth_lut = 16'd51;
                9'd406: floor_depth_lut = 16'd50;
                9'd407: floor_depth_lut = 16'd50;
                9'd408: floor_depth_lut = 16'd50;
                9'd409: floor_depth_lut = 16'd50;
                9'd410: floor_depth_lut = 16'd50;
                9'd411: floor_depth_lut = 16'd50;
                9'd412: floor_depth_lut = 16'd50;
                9'd413: floor_depth_lut = 16'd50;
                9'd414: floor_depth_lut = 16'd49;
                9'd415: floor_depth_lut = 16'd49;
                9'd416: floor_depth_lut = 16'd49;
                9'd417: floor_depth_lut = 16'd49;
                9'd418: floor_depth_lut = 16'd49;
                9'd419: floor_depth_lut = 16'd49;
                9'd420: floor_depth_lut = 16'd49;
                9'd421: floor_depth_lut = 16'd49;
                9'd422: floor_depth_lut = 16'd49;
                9'd423: floor_depth_lut = 16'd48;
                9'd424: floor_depth_lut = 16'd48;
                9'd425: floor_depth_lut = 16'd48;
                9'd426: floor_depth_lut = 16'd48;
                9'd427: floor_depth_lut = 16'd48;
                9'd428: floor_depth_lut = 16'd48;
                9'd429: floor_depth_lut = 16'd48;
                9'd430: floor_depth_lut = 16'd48;
                9'd431: floor_depth_lut = 16'd48;
                9'd432: floor_depth_lut = 16'd47;
                9'd433: floor_depth_lut = 16'd47;
                9'd434: floor_depth_lut = 16'd47;
                9'd435: floor_depth_lut = 16'd47;
                9'd436: floor_depth_lut = 16'd47;
                9'd437: floor_depth_lut = 16'd47;
                9'd438: floor_depth_lut = 16'd47;
                9'd439: floor_depth_lut = 16'd47;
                9'd440: floor_depth_lut = 16'd47;
                9'd441: floor_depth_lut = 16'd46;
                9'd442: floor_depth_lut = 16'd46;
                9'd443: floor_depth_lut = 16'd46;
                9'd444: floor_depth_lut = 16'd46;
                9'd445: floor_depth_lut = 16'd46;
                9'd446: floor_depth_lut = 16'd46;
                9'd447: floor_depth_lut = 16'd46;
                9'd448: floor_depth_lut = 16'd46;
                9'd449: floor_depth_lut = 16'd46;
                9'd450: floor_depth_lut = 16'd46;
                9'd451: floor_depth_lut = 16'd45;
                9'd452: floor_depth_lut = 16'd45;
                9'd453: floor_depth_lut = 16'd45;
                9'd454: floor_depth_lut = 16'd45;
                9'd455: floor_depth_lut = 16'd45;
                9'd456: floor_depth_lut = 16'd45;
                9'd457: floor_depth_lut = 16'd45;
                9'd458: floor_depth_lut = 16'd45;
                9'd459: floor_depth_lut = 16'd45;
                9'd460: floor_depth_lut = 16'd45;
                9'd461: floor_depth_lut = 16'd44;
                9'd462: floor_depth_lut = 16'd44;
                9'd463: floor_depth_lut = 16'd44;
                9'd464: floor_depth_lut = 16'd44;
                9'd465: floor_depth_lut = 16'd44;
                9'd466: floor_depth_lut = 16'd44;
                9'd467: floor_depth_lut = 16'd44;
                9'd468: floor_depth_lut = 16'd44;
                9'd469: floor_depth_lut = 16'd44;
                9'd470: floor_depth_lut = 16'd44;
                9'd471: floor_depth_lut = 16'd43;
                9'd472: floor_depth_lut = 16'd43;
                9'd473: floor_depth_lut = 16'd43;
                9'd474: floor_depth_lut = 16'd43;
                9'd475: floor_depth_lut = 16'd43;
                9'd476: floor_depth_lut = 16'd43;
                9'd477: floor_depth_lut = 16'd43;
                9'd478: floor_depth_lut = 16'd43;
                9'd479: floor_depth_lut = 16'd43;
                9'd480: floor_depth_lut = 16'd43;
                9'd481: floor_depth_lut = 16'd43;
                9'd482: floor_depth_lut = 16'd42;
                9'd483: floor_depth_lut = 16'd42;
                9'd484: floor_depth_lut = 16'd42;
                9'd485: floor_depth_lut = 16'd42;
                9'd486: floor_depth_lut = 16'd42;
                9'd487: floor_depth_lut = 16'd42;
                9'd488: floor_depth_lut = 16'd42;
                9'd489: floor_depth_lut = 16'd42;
                9'd490: floor_depth_lut = 16'd42;
                9'd491: floor_depth_lut = 16'd42;
                9'd492: floor_depth_lut = 16'd42;
                9'd493: floor_depth_lut = 16'd42;
                9'd494: floor_depth_lut = 16'd41;
                9'd495: floor_depth_lut = 16'd41;
                9'd496: floor_depth_lut = 16'd41;
                9'd497: floor_depth_lut = 16'd41;
                9'd498: floor_depth_lut = 16'd41;
                9'd499: floor_depth_lut = 16'd41;
                9'd500: floor_depth_lut = 16'd41;
                9'd501: floor_depth_lut = 16'd41;
                9'd502: floor_depth_lut = 16'd41;
                9'd503: floor_depth_lut = 16'd41;
                9'd504: floor_depth_lut = 16'd41;
                9'd505: floor_depth_lut = 16'd41;
                9'd506: floor_depth_lut = 16'd40;
                9'd507: floor_depth_lut = 16'd40;
                9'd508: floor_depth_lut = 16'd40;
                9'd509: floor_depth_lut = 16'd40;
                9'd510: floor_depth_lut = 16'd40;
                9'd511: floor_depth_lut = 16'd40;
                default: floor_depth_lut = 16'd40;
            endcase
        end
    endfunction

    always @(*) begin
        // ====================================================================
        // 1. Build current column ray
        // ====================================================================
        screen_offset_x =
            $signed({1'b0, pixel_x}) - 12'sd320;

        ray_x_q7 =
            ($signed(sin_yaw) * 32'sd256) +
            ($signed(cos_yaw) * $signed(screen_offset_x));

        ray_z_q7 =
            ($signed(cos_yaw) * 32'sd256) -
            ($signed(sin_yaw) * $signed(screen_offset_x));

        // ====================================================================
        // 2-5. Read the cached five-room wall intersection for this column.
        // ====================================================================
        x_plane_delta = 17'sd0;
        z_plane_delta = 17'sd0;
        x_depth_num = 48'sd0;
        z_depth_num = 48'sd0;
        x_wall_depth = 32'sd0;
        z_wall_depth = 32'sd0;
        x_wall_hit_z = 32'sd0;
        z_wall_hit_x = 32'sd0;
        x_wall_valid = 1'b0;
        z_wall_valid = 1'b0;

        wall_ray_distance = $signed({1'b0, map_wall_depth});
        wall_depth        = $signed({1'b0, map_wall_depth});
        // Solid-wall debug: wall U/orientation are intentionally ignored.
        wall_u_world      = 32'sd0;
        wall_side         = 2'd0;
        wall_forward_mul  = 48'sd0;

        abs_wall_sin = 8'd0;
        abs_wall_cos = 8'd0;
        inv_wall_sin_q8 = 16'd0;
        inv_wall_cos_q8 = 16'd0;

        if (!map_wall_valid || (map_wall_depth <= NEAR_DEPTH))
            wall_depth_index = 9'd511;
        else if (map_wall_depth >= 16'd2044)
            wall_depth_index = 9'd511;
        else
            wall_depth_index = map_wall_depth[10:2];

        wall_proj_scale = wall_scale_q8(wall_depth_index);

        // ====================================================================
        // 6. Pitch shifts the horizon.
        // ====================================================================
        horizon_y = fps_horizon_y(camera_pitch);

        wall_top    = -32'sd2048;
        wall_bottom =  32'sd2048;
        wall_y_world = 32'sd0;

        if (map_wall_valid &&
            (wall_depth > NEAR_DEPTH)) begin

            wall_top =
                $signed(horizon_y) -
                ((($signed(CEILING_Y) - $signed(camera_y)) *
                  $signed({1'b0, wall_proj_scale})) >>> 8);

            wall_bottom =
                $signed(horizon_y) +
                (($signed(camera_y) *
                  $signed({1'b0, wall_proj_scale})) >>> 8);

            wall_y_world =
                $signed(camera_y) +
                ((($signed(horizon_y) -
                   $signed({2'b00, pixel_y})) *
                  wall_depth) >>> 8);
        end

        // ====================================================================
        // 7. Floor / ceiling plane world coordinate
        // ====================================================================
        horizon_delta =
            $signed({2'b00, pixel_y}) -
            $signed(horizon_y);

        if (horizon_delta < 0) begin
            if ((-horizon_delta) > 13'sd511)
                plane_dy = 9'd511;
            else
                plane_dy = -horizon_delta;
        end
        else begin
            if (horizon_delta > 13'sd511)
                plane_dy = 9'd511;
            else
                plane_dy = horizon_delta[8:0];
        end

        // floor_depth_lut is normalized for an 80-unit eye height.
        // Scale both floor and ceiling depths by the CURRENT camera Y so
        // jumping changes the room perspective rather than merely shifting
        // objects on screen.
        floor_depth_base = floor_depth_lut(plane_dy);

        camera_y_unsigned = camera_y[15:0];
        ceiling_height_from_camera =
            ($signed(CEILING_Y) - $signed(camera_y));

        // Same exact products as V14, but forced into fabric shift/add logic
        // so the jump feature does not consume two additional DSP48E1 blocks.
        floor_depth_product =
            mul_u16_u9_fabric(
                floor_depth_base,
                camera_y_unsigned[8:0]
            );

        ceiling_depth_product =
            mul_u16_u9_fabric(
                floor_depth_base,
                ceiling_height_from_camera[8:0]
            );

        floor_depth =
            floor_depth_product / BASE_EYE_Y;

        ceiling_depth =
            ceiling_depth_product / BASE_EYE_Y;

        floor_x_mul =
            $signed(ray_x_q7) * $signed({1'b0, floor_depth});

        floor_z_mul =
            $signed(ray_z_q7) * $signed({1'b0, floor_depth});

        ceil_x_mul =
            $signed(ray_x_q7) * $signed({1'b0, ceiling_depth});

        ceil_z_mul =
            $signed(ray_z_q7) * $signed({1'b0, ceiling_depth});

        plane_world_x = 32'sd0;
        plane_world_z = 32'sd0;

        if (horizon_delta >= 0) begin
            plane_world_x =
                $signed(camera_x) + (floor_x_mul >>> 15);

            plane_world_z =
                $signed(camera_z) + (floor_z_mul >>> 15);
        end
        else begin
            plane_world_x =
                $signed(camera_x) + (ceil_x_mul >>> 15);

            plane_world_z =
                $signed(camera_z) + (ceil_z_mul >>> 15);
        end

        // ====================================================================
        // 8. Repeating 64x64 unit panel pattern
        // ====================================================================
        wall_u_mod = 6'd0;
        wall_y_mod = 6'd0;

        plane_x_mod = plane_world_x[5:0];
        plane_z_mod = plane_world_z[5:0];

        plane_grid_line =
            (plane_x_mod <= 6'd2) ||
            (plane_x_mod >= 6'd62) ||
            (plane_z_mod <= 6'd2) ||
            (plane_z_mod >= 6'd62);

        plane_checker =
            plane_world_x[6] ^ plane_world_z[6];

        // ====================================================================
        // 9. ROOM COLOR
        // ====================================================================

        // Default dark background for the exact horizon / fallback case.
        raw_rgb = 12'h111;

        // ------------------------------------------------------------
        // Wall
        // ------------------------------------------------------------
        if (map_wall_valid &&
            ($signed({2'b00, pixel_y}) >= wall_top) &&
            ($signed({2'b00, pixel_y}) <= wall_bottom)) begin

            // DEBUG: every wall is exactly the same solid red.
            // No checker pattern, no grid lines, no orientation shading.
            raw_rgb = 12'hF00;
        end

        // ------------------------------------------------------------
        // Ceiling
        // ------------------------------------------------------------
        else if ($signed({2'b00, pixel_y}) < wall_top) begin
            // Blue ceiling/sky panels.
            raw_rgb = plane_checker ? 12'h148 : 12'h259;

            if (plane_grid_line)
                raw_rgb = 12'h6CF;
        end

        // ------------------------------------------------------------
        // Floor
        // ------------------------------------------------------------
        else begin
            raw_rgb = plane_checker ? 12'h323 : 12'h434;

            if (plane_grid_line)
                raw_rgb = 12'h7A7;
        end

        // Crosshair on top of everything.
        if (crosshair)
            raw_rgb = 12'hFFF;

        // Red indicator if Python heartbeat disappears.
        if (host_warning)
            raw_rgb = 12'hF00;
    end

endmodule
