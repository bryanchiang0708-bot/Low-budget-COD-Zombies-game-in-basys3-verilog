// ============================================================================
// ZOMBIES FIVE-ROOM MAP WALL RAYCASTER
//
// Map geometry from the user's sketch.
// One grid block = 64 world units.
//
// Room rectangles:
//   Main/start       20 x 20 : X [-640,  640], Z [-640,  640]
//   Upper-left       14 x 14 : X [-1216,-320], Z [ 320, 1216]
//   Upper-right      12 x 12 : X [ 320, 1088], Z [ 320, 1088]
//   Lower-left       10 x 10 : X [-960, -320], Z [-960, -320]
//   Lower-right      10 x 10 : X [ 320,  960], Z [-960, -320]
//
// The union produces four 5x5-grid open connections to the main room.
// There are 20 exposed axis-aligned wall segments.
//
// Instead of intersecting all 20 segments for every VGA pixel, this module
// checks one segment per 100 MHz clock and caches one result per screen column.
// 640 columns * 21 clocks ~= 0.134 ms per complete wall update.
// ============================================================================
module zombies_map_wall_raycaster (
    input  wire               clk_100mhz,
    input  wire               reset,
    input  wire               frame_tick,
    input  wire               pixel_tick,

    input  wire signed [15:0] camera_x,
    input  wire signed [15:0] camera_z,
    input  wire [7:0]         camera_yaw,

    input  wire               door_ul_open,
    input  wire               door_ur_open,
    input  wire               door_ll_open,
    input  wire               door_lr_open,

    input  wire [9:0]         pixel_x,

    output reg [15:0]         wall_depth,
    output reg                wall_valid,
    output reg                wall_is_door,
    output reg                wall_is_shotgun_buy,
    output reg                wall_is_rifle_buy,

    output reg                wall_is_power_station,
    output reg                wall_is_ultimate_station,
    output reg                wall_is_powerup_station,
    output reg                wall_is_luckybox_station,

    output reg [15:0]         spawn_depth,
    output reg                spawn_valid,

    output reg [15:0]         spawn_far_depth,
    output reg                spawn_far_valid,

    output reg [15:0]         entry_wall_depth,
    output reg                entry_wall_valid
);

    localparam integer NEAR_DEPTH    = 8;
    localparam integer SEGMENT_COUNT = 63;

    // ========================================================================
    // BLOCK-RAM DUAL-SURFACE CACHE
    //
    // [35]    full-height wall valid
    // [34:33] full-height surface type:
    //          00 normal red wall
    //          01 locked brown door
    //          10 shotgun wall-buy strip
    //          11 rifle wall-buy strip
    // [32:17] full-height wall forward depth
    // [16]    low spawn-block valid
    // [15:0]  low spawn-block forward depth
    //
    // 640 x 36 bits still maps naturally to one 36-Kbit BRAM.
    // ========================================================================
    (* ram_style = "block" *) reg [35:0] wall_cache [0:639];

    // Secondary BRAM:
    // [33]    FAR spawn surface valid
    // [32:17] FAR spawn forward depth
    // [16]    missing fourth-wall valid
    // [15:0]  missing fourth-wall forward depth
    //
    // This remains within one 36-Kbit BRAM.
    (* ram_style = "block" *) reg [33:0] spawn_far_cache [0:639];

    // V24 3-bit pink-surface subtype cache:
    // 0 none, 1 shotgun, 2 rifle, 3 power, 4 ultimate, 5 powerup, 6 lucky box.
    (* ram_style = "block" *) reg [2:0] buy_kind_cache [0:639];

    reg [35:0] cache_read_data;
    reg [33:0] spawn_far_read_data;
    reg [2:0]  buy_kind_read_data;
    reg [9:0]  cache_read_addr;

    reg        cache_we;
    reg [9:0]  cache_write_addr;
    reg [35:0] cache_write_data;
    reg [33:0] spawn_far_write_data;
    reg [2:0]  buy_kind_write_data;

    reg        cache_ready;

    always @(*) begin
        if (pixel_tick) begin
            if (pixel_x == 10'd799)
                cache_read_addr = 10'd0;
            else if (pixel_x < 10'd639)
                cache_read_addr = pixel_x + 10'd1;
            else
                cache_read_addr = 10'd639;
        end
        else begin
            if (pixel_x < 10'd640)
                cache_read_addr = pixel_x;
            else
                cache_read_addr = 10'd639;
        end
    end

    always @(posedge clk_100mhz) begin
        if (cache_we) begin
            wall_cache[cache_write_addr] <= cache_write_data;
            spawn_far_cache[cache_write_addr] <= spawn_far_write_data;
            buy_kind_cache[cache_write_addr] <= buy_kind_write_data;
        end

        cache_read_data <= wall_cache[cache_read_addr];
        spawn_far_read_data <= spawn_far_cache[cache_read_addr];
        buy_kind_read_data <= buy_kind_cache[cache_read_addr];
    end

    always @(*) begin
        if ((pixel_x < 10'd640) && cache_ready) begin
            wall_valid   = cache_read_data[35];
            wall_is_door = (cache_read_data[34:33] == 2'b01);

            wall_is_shotgun_buy      = (buy_kind_read_data == 3'd1);
            wall_is_rifle_buy        = (buy_kind_read_data == 3'd2);
            wall_is_power_station    = (buy_kind_read_data == 3'd3);
            wall_is_ultimate_station = (buy_kind_read_data == 3'd4);
            wall_is_powerup_station  = (buy_kind_read_data == 3'd5);
            wall_is_luckybox_station = (buy_kind_read_data == 3'd6);

            wall_depth   = cache_read_data[32:17];

            spawn_valid  = cache_read_data[16];
            spawn_depth  = cache_read_data[15:0];

            spawn_far_valid = spawn_far_read_data[33];
            spawn_far_depth = spawn_far_read_data[32:17];

            entry_wall_valid = spawn_far_read_data[16];
            entry_wall_depth = spawn_far_read_data[15:0];
        end
        else begin
            wall_valid   = 1'b0;
            wall_is_door = 1'b0;
            wall_is_shotgun_buy = 1'b0;
            wall_is_rifle_buy   = 1'b0;
            wall_is_power_station = 1'b0;
            wall_is_ultimate_station = 1'b0;
            wall_is_powerup_station = 1'b0;
            wall_is_luckybox_station = 1'b0;
            wall_depth   = 16'd2047;

            spawn_valid  = 1'b0;
            spawn_depth  = 16'd2047;

            spawn_far_valid = 1'b0;
            spawn_far_depth = 16'd2047;

            entry_wall_valid = 1'b0;
            entry_wall_depth = 16'd2047;
        end
    end

    // ========================================================================
    // PIPELINED RAYCASTER
    //
    // V20 chained angle, trig, two DSP multiplies, and comparisons in one
    // 10 ns path. V20B puts registers between those operations.
    // ========================================================================

    localparam [3:0]
        ST_IDLE         = 4'd0,
        ST_PREP_ANGLE   = 4'd1,
        ST_PREP_TRIG    = 4'd2,
        ST_SEG_SETUP    = 4'd3,
        ST_SEG_DISTANCE = 4'd4,
        ST_SEG_HIT      = 4'd5,
        ST_SEG_COMPARE      = 4'd6,
        ST_FINAL_WALL       = 4'd7,
        ST_FINAL_SPAWN      = 4'd8,
        ST_FINAL_SPAWN_FAR  = 4'd9,
        ST_FINAL_ENTRY_WALL = 4'd10,
        ST_WRITE_CACHE      = 4'd11;

    reg [3:0] state;

    reg [9:0] column_index;
    reg [5:0] segment_index;

    // Freeze one coherent camera/door state for the whole cache rebuild.
    reg signed [15:0] build_camera_x;
    reg signed [15:0] build_camera_z;
    reg [7:0]         build_camera_yaw;
    reg               build_door_ul_open;
    reg               build_door_ur_open;
    reg               build_door_ll_open;
    reg               build_door_lr_open;

    // ------------------------------------------------------------------------
    // Column angle. Constant *29 is shift/add, so it no longer consumes a DSP.
    // ------------------------------------------------------------------------
    wire signed [11:0] column_offset =
        $signed({1'b0, column_index}) - 12'sd320;

    wire signed [17:0] column_offset_ext =
        {{6{column_offset[11]}}, column_offset};

    wire signed [17:0] wall_angle_mul_fast =
        (column_offset_ext <<< 5) -
        (column_offset_ext <<< 1) -
        column_offset_ext;

    wire signed [12:0] wall_angle_offset_calc =
        $signed(wall_angle_mul_fast) >>> 8;

    reg [7:0] ray_angle_reg;
    reg [7:0] offset_angle_reg;

    wire signed [8:0] trig_ray_sin;
    wire signed [8:0] trig_ray_cos;
    wire signed [8:0] trig_offset_sin_unused;
    wire signed [8:0] trig_offset_cos;

    trig_q17 map_wall_ray_trig (
        .angle(ray_angle_reg),
        .sin_value(trig_ray_sin),
        .cos_value(trig_ray_cos)
    );

    trig_q17 map_wall_offset_trig (
        .angle(offset_angle_reg),
        .sin_value(trig_offset_sin_unused),
        .cos_value(trig_offset_cos)
    );

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

    wire [7:0] trig_abs_sin =
        trig_ray_sin[8] ? -$signed(trig_ray_sin) : trig_ray_sin;

    wire [7:0] trig_abs_cos =
        trig_ray_cos[8] ? -$signed(trig_ray_cos) : trig_ray_cos;

    wire [15:0] trig_inv_sin_q8 = recip_trig_q8(trig_abs_sin);
    wire [15:0] trig_inv_cos_q8 = recip_trig_q8(trig_abs_cos);

    reg signed [8:0] ray_sin_reg;
    reg signed [8:0] ray_cos_reg;
    reg [15:0]       inv_sin_reg;
    reg [15:0]       inv_cos_reg;
    reg signed [8:0] offset_cos_reg;

    // ------------------------------------------------------------------------
    // Current segment.
    // ------------------------------------------------------------------------
    reg               seg_vertical;
    reg signed [15:0] seg_plane;
    reg signed [15:0] seg_min;
    reg signed [15:0] seg_max;
    reg               seg_enabled;
    reg               seg_is_door;
    reg [2:0]         seg_buy_kind; // 0 none, 1 shotgun, 2 rifle, 3 power, 4 ultimate, 5 powerup, 6 luckybox
    reg               seg_is_spawn;
    reg               seg_is_entry_wall;

    // V21B: some full-height red walls have a 3-grid-wide opening where a
    // blue spawn block attaches. The raycaster ignores the red wall only
    // inside this coordinate interval.
    reg               seg_has_spawn_opening;
    reg signed [15:0] seg_opening_min;
    reg signed [15:0] seg_opening_max;

    always @(*) begin
        seg_vertical = 1'b0;
        seg_plane    = 16'sd0;
        seg_min      = 16'sd0;
        seg_max      = 16'sd0;
        seg_enabled  = 1'b1;
        seg_is_door  = 1'b0;
        seg_buy_kind = 3'd0;
        seg_is_spawn = 1'b0;
        seg_is_entry_wall = 1'b0;

        seg_has_spawn_opening = 1'b0;
        seg_opening_min = 16'sd0;
        seg_opening_max = 16'sd0;

        case (segment_index)
            5'd0:  begin seg_vertical=1'b0; seg_plane=-16'sd320;  seg_min=-16'sd960;  seg_max=-16'sd640;  end
            5'd1:  begin
                seg_vertical=1'b1; seg_plane=-16'sd640;
                seg_min=-16'sd320; seg_max=16'sd320;
                seg_has_spawn_opening=1'b1;
                seg_opening_min=-16'sd96; seg_opening_max=16'sd96;
            end
            5'd2:  begin seg_vertical=1'b0; seg_plane= 16'sd320;  seg_min=-16'sd1216; seg_max=-16'sd640;  end
            5'd3:  begin
                seg_vertical=1'b1; seg_plane=-16'sd1216;
                seg_min=16'sd320; seg_max=16'sd1216;
                seg_has_spawn_opening=1'b1;
                seg_opening_min=16'sd672; seg_opening_max=16'sd864;
            end
            5'd4: begin
                seg_vertical=1'b0; seg_plane=16'sd1216;
                seg_min=-16'sd1216; seg_max=-16'sd320;
                seg_has_spawn_opening=1'b1;
                seg_opening_min=-16'sd864; seg_opening_max=-16'sd672;
            end
            5'd5:  begin seg_vertical=1'b1; seg_plane=-16'sd320;  seg_min= 16'sd640;  seg_max= 16'sd1216; end
            5'd6:  begin
                seg_vertical=1'b0; seg_plane=16'sd640;
                seg_min=-16'sd320; seg_max=16'sd320;
                // V23 shotgun wall-buy insert occupies x=-96..+96.
                seg_has_spawn_opening=1'b1;
                seg_opening_min=-16'sd96; seg_opening_max=16'sd96;
            end
            5'd7:  begin seg_vertical=1'b1; seg_plane= 16'sd320;  seg_min= 16'sd640;  seg_max= 16'sd1088; end
            5'd8: begin
                seg_vertical=1'b0; seg_plane=16'sd1088;
                seg_min=16'sd320; seg_max=16'sd1088;
                seg_has_spawn_opening=1'b1;
                seg_opening_min=16'sd608; seg_opening_max=16'sd800;
            end
            5'd9:  begin
                seg_vertical=1'b1; seg_plane=16'sd1088;
                seg_min=16'sd320; seg_max=16'sd1088;
                seg_has_spawn_opening=1'b1;
                seg_opening_min=16'sd608; seg_opening_max=16'sd800;
            end
            5'd10: begin seg_vertical=1'b0; seg_plane= 16'sd320;  seg_min= 16'sd640;  seg_max= 16'sd1088; end
            5'd11: begin
                seg_vertical=1'b1; seg_plane=16'sd640;
                seg_min=-16'sd320; seg_max=16'sd320;
                seg_has_spawn_opening=1'b1;
                seg_opening_min=-16'sd96; seg_opening_max=16'sd96;
            end
            5'd12: begin seg_vertical=1'b0; seg_plane=-16'sd320;  seg_min= 16'sd640;  seg_max= 16'sd960;  end
            5'd13: begin
                seg_vertical=1'b1; seg_plane=16'sd960;
                seg_min=-16'sd960; seg_max=-16'sd320;
                // V23 rifle wall-buy insert occupies z=-736..-544.
                seg_has_spawn_opening=1'b1;
                seg_opening_min=-16'sd736; seg_opening_max=-16'sd544;
            end
            5'd14: begin
                seg_vertical=1'b0; seg_plane=-16'sd960;
                seg_min=16'sd320; seg_max=16'sd960;
                seg_has_spawn_opening=1'b1;
                seg_opening_min=16'sd544; seg_opening_max=16'sd736;
            end
            5'd15: begin seg_vertical=1'b1; seg_plane= 16'sd320;  seg_min=-16'sd960;  seg_max=-16'sd640;  end
            5'd16: begin
                seg_vertical=1'b0; seg_plane=-16'sd640;
                seg_min=-16'sd320; seg_max=16'sd320;
                seg_has_spawn_opening=1'b1;
                seg_opening_min=-16'sd96; seg_opening_max=16'sd96;
            end
            5'd17: begin seg_vertical=1'b1; seg_plane=-16'sd320;  seg_min=-16'sd960;  seg_max=-16'sd640;  end
            5'd18: begin
                // LL bottom wall left piece only.
                seg_vertical=1'b0; seg_plane=-16'sd960;
                seg_min=-16'sd960; seg_max=-16'sd736;
            end
            5'd19: begin
                seg_vertical=1'b1; seg_plane=-16'sd960;
                seg_min=-16'sd960; seg_max=-16'sd320;
                seg_has_spawn_opening=1'b1;
                seg_opening_min=-16'sd736; seg_opening_max=-16'sd544;
            end

            5'd20: begin seg_vertical=1'b0; seg_plane= 16'sd640; seg_min=-16'sd640; seg_max=-16'sd320; seg_enabled=!build_door_ul_open; seg_is_door=1'b1; end
            5'd21: begin seg_vertical=1'b1; seg_plane=-16'sd640; seg_min= 16'sd320; seg_max= 16'sd640; seg_enabled=!build_door_ul_open; seg_is_door=1'b1; end
            5'd22: begin seg_vertical=1'b0; seg_plane= 16'sd640; seg_min= 16'sd320; seg_max= 16'sd640; seg_enabled=!build_door_ur_open; seg_is_door=1'b1; end
            5'd23: begin seg_vertical=1'b1; seg_plane= 16'sd640; seg_min= 16'sd320; seg_max= 16'sd640; seg_enabled=!build_door_ur_open; seg_is_door=1'b1; end
            5'd24: begin seg_vertical=1'b0; seg_plane=-16'sd640; seg_min=-16'sd640; seg_max=-16'sd320; seg_enabled=!build_door_ll_open; seg_is_door=1'b1; end
            5'd25: begin seg_vertical=1'b1; seg_plane=-16'sd640; seg_min=-16'sd640; seg_max=-16'sd320; seg_enabled=!build_door_ll_open; seg_is_door=1'b1; end
            5'd26: begin seg_vertical=1'b0; seg_plane=-16'sd640; seg_min= 16'sd320; seg_max= 16'sd640; seg_enabled=!build_door_lr_open; seg_is_door=1'b1; end
            5'd27: begin seg_vertical=1'b1; seg_plane= 16'sd640; seg_min=-16'sd640; seg_max=-16'sd320; seg_enabled=!build_door_lr_open; seg_is_door=1'b1; end

            // ============================================================
            // V21: seven 3x3-grid spawn blocks, 192x192 world units.
            // Each is represented by four LOW (Y=0..64) side segments.
            // The low/full-height distinction is kept in a separate cache.
            //
            // Main left: X[-832,-640], Z[-96,+96]
            // ============================================================
            6'd28: begin seg_vertical=1'b1; seg_plane=-16'sd832; seg_min=-16'sd96;  seg_max= 16'sd96;  seg_is_spawn=1'b1; end
            6'd29: begin seg_vertical=1'b1; seg_plane=-16'sd640; seg_min=-16'sd96;  seg_max= 16'sd96;  seg_is_spawn=1'b1; seg_is_entry_wall=1'b1; end
            6'd30: begin seg_vertical=1'b0; seg_plane=-16'sd96;  seg_min=-16'sd832; seg_max=-16'sd640; seg_is_spawn=1'b1; end
            6'd31: begin seg_vertical=1'b0; seg_plane= 16'sd96;  seg_min=-16'sd832; seg_max=-16'sd640; seg_is_spawn=1'b1; end

            // Main right: X[+640,+832], Z[-96,+96]
            6'd32: begin seg_vertical=1'b1; seg_plane= 16'sd640; seg_min=-16'sd96; seg_max= 16'sd96; seg_is_spawn=1'b1; seg_is_entry_wall=1'b1; end
            6'd33: begin seg_vertical=1'b1; seg_plane= 16'sd832; seg_min=-16'sd96; seg_max= 16'sd96; seg_is_spawn=1'b1; end
            6'd34: begin seg_vertical=1'b0; seg_plane=-16'sd96;  seg_min= 16'sd640; seg_max= 16'sd832; seg_is_spawn=1'b1; end
            6'd35: begin seg_vertical=1'b0; seg_plane= 16'sd96;  seg_min= 16'sd640; seg_max= 16'sd832; seg_is_spawn=1'b1; end

            // Main bottom: X[-96,+96], Z[-832,-640]
            6'd36: begin seg_vertical=1'b0; seg_plane=-16'sd832; seg_min=-16'sd96; seg_max= 16'sd96; seg_is_spawn=1'b1; end
            6'd37: begin seg_vertical=1'b0; seg_plane=-16'sd640; seg_min=-16'sd96; seg_max= 16'sd96; seg_is_spawn=1'b1; seg_is_entry_wall=1'b1; end
            6'd38: begin seg_vertical=1'b1; seg_plane=-16'sd96;  seg_min=-16'sd832; seg_max=-16'sd640; seg_is_spawn=1'b1; end
            6'd39: begin seg_vertical=1'b1; seg_plane= 16'sd96;  seg_min=-16'sd832; seg_max=-16'sd640; seg_is_spawn=1'b1; end

            // Upper-left: X[-1408,-1216], Z[672,864]
            6'd40: begin seg_vertical=1'b1; seg_plane=-16'sd1408; seg_min= 16'sd672; seg_max= 16'sd864; seg_is_spawn=1'b1; end
            6'd41: begin seg_vertical=1'b1; seg_plane=-16'sd1216; seg_min= 16'sd672; seg_max= 16'sd864; seg_is_spawn=1'b1; seg_is_entry_wall=1'b1; end
            6'd42: begin seg_vertical=1'b0; seg_plane= 16'sd672;  seg_min=-16'sd1408; seg_max=-16'sd1216; seg_is_spawn=1'b1; end
            6'd43: begin seg_vertical=1'b0; seg_plane= 16'sd864;  seg_min=-16'sd1408; seg_max=-16'sd1216; seg_is_spawn=1'b1; end

            // Upper-right: X[1088,1280], Z[608,800]
            6'd44: begin seg_vertical=1'b1; seg_plane= 16'sd1088; seg_min= 16'sd608; seg_max= 16'sd800; seg_is_spawn=1'b1; seg_is_entry_wall=1'b1; end
            6'd45: begin seg_vertical=1'b1; seg_plane= 16'sd1280; seg_min= 16'sd608; seg_max= 16'sd800; seg_is_spawn=1'b1; end
            6'd46: begin seg_vertical=1'b0; seg_plane= 16'sd608;  seg_min= 16'sd1088; seg_max= 16'sd1280; seg_is_spawn=1'b1; end
            6'd47: begin seg_vertical=1'b0; seg_plane= 16'sd800;  seg_min= 16'sd1088; seg_max= 16'sd1280; seg_is_spawn=1'b1; end

            // Lower-left: X[-736,-544], Z[-1152,-960]
            6'd48: begin seg_vertical=1'b0; seg_plane=-16'sd1152; seg_min=-16'sd736; seg_max=-16'sd544; seg_is_spawn=1'b1; end
            6'd49: begin seg_vertical=1'b0; seg_plane=-16'sd960;  seg_min=-16'sd736; seg_max=-16'sd544; seg_is_spawn=1'b1; seg_is_entry_wall=1'b1; end
            6'd50: begin seg_vertical=1'b1; seg_plane=-16'sd736;  seg_min=-16'sd1152; seg_max=-16'sd960; seg_is_spawn=1'b1; end
            6'd51: begin seg_vertical=1'b1; seg_plane=-16'sd544;  seg_min=-16'sd1152; seg_max=-16'sd960; seg_is_spawn=1'b1; end

            // Lower-right: X[544,736], Z[-1152,-960]
            6'd52: begin seg_vertical=1'b0; seg_plane=-16'sd1152; seg_min= 16'sd544; seg_max= 16'sd736; seg_is_spawn=1'b1; end
            6'd53: begin seg_vertical=1'b0; seg_plane=-16'sd960;  seg_min= 16'sd544; seg_max= 16'sd736; seg_is_spawn=1'b1; seg_is_entry_wall=1'b1; end
            6'd54: begin seg_vertical=1'b1; seg_plane= 16'sd544;  seg_min=-16'sd1152; seg_max=-16'sd960; seg_is_spawn=1'b1; end
            6'd55: begin seg_vertical=1'b1; seg_plane= 16'sd736;  seg_min=-16'sd1152; seg_max=-16'sd960; seg_is_spawn=1'b1; end

            // ============================================================
            // V23 wall-buy inserts.
            // They replace the small intervals cut out of map segments 6/13.
            // ============================================================
            6'd56: begin
                // Shotgun: top-center wall of main room.
                seg_vertical=1'b0; seg_plane=16'sd640;
                seg_min=-16'sd96; seg_max=16'sd96;
                seg_buy_kind=3'd1;
            end

            6'd57: begin
                // Rifle: outer right wall of lower-right 10x10 room.
                seg_vertical=1'b1; seg_plane=16'sd960;
                seg_min=-16'sd736; seg_max=-16'sd544;
                seg_buy_kind=3'd2;
            end

            // V24 visual-only stations.
            6'd58: begin
                // POWER 1000 — LL left wall.
                seg_vertical=1'b1; seg_plane=-16'sd960;
                seg_min=-16'sd736; seg_max=-16'sd544;
                seg_buy_kind=3'd3;
            end

            6'd59: begin
                // ULTIMATE 1500 — UL top wall.
                seg_vertical=1'b0; seg_plane=16'sd1216;
                seg_min=-16'sd864; seg_max=-16'sd672;
                seg_buy_kind=3'd4;
            end

            6'd60: begin
                // POWER UP — UR top wall.
                seg_vertical=1'b0; seg_plane=16'sd1088;
                seg_min=16'sd608; seg_max=16'sd800;
                seg_buy_kind=3'd5;
            end

            6'd61: begin
                // LUCKY BOX 1000 — LL bottom-right wall.
                seg_vertical=1'b0; seg_plane=-16'sd960;
                seg_min=-16'sd544; seg_max=-16'sd352;
                seg_buy_kind=3'd6;
            end

            6'd62: begin
                // Remaining LL bottom red wall.
                seg_vertical=1'b0; seg_plane=-16'sd960;
                seg_min=-16'sd352; seg_max=-16'sd320;
            end

            default: begin
                seg_enabled  = 1'b0;
                seg_buy_kind = 3'd0;
                seg_is_spawn = 1'b0;
                seg_is_entry_wall = 1'b0;
                seg_has_spawn_opening = 1'b0;
                seg_opening_min = 16'sd0;
                seg_opening_max = 16'sd0;
            end
        endcase
    end

    // ------------------------------------------------------------------------
    // Stage 1: register plane delta and metadata BEFORE any multiplier.
    // ------------------------------------------------------------------------
    wire signed [16:0] setup_camera_axis =
        seg_vertical
        ? $signed({build_camera_x[15], build_camera_x})
        : $signed({build_camera_z[15], build_camera_z});

    wire signed [16:0] setup_plane_ext =
        $signed({seg_plane[15], seg_plane});

    wire signed [16:0] setup_plane_delta =
        setup_plane_ext - setup_camera_axis;

    wire [16:0] setup_abs_plane_delta =
        setup_plane_delta[16] ? -setup_plane_delta : setup_plane_delta;

    wire signed [8:0] setup_direction_component =
        seg_vertical ? ray_sin_reg : ray_cos_reg;

    wire setup_direction_ok =
        seg_enabled &&
        (((setup_plane_delta > 0) && (setup_direction_component > 0)) ||
         ((setup_plane_delta < 0) && (setup_direction_component < 0)));

    wire [15:0] setup_inverse =
        seg_vertical ? inv_sin_reg : inv_cos_reg;

    wire signed [8:0] setup_hit_direction =
        seg_vertical ? ray_cos_reg : ray_sin_reg;

    wire signed [15:0] setup_hit_base =
        seg_vertical ? build_camera_z : build_camera_x;

    reg [16:0]        stage_abs_delta;
    reg [15:0]        stage_inverse;
    reg signed [8:0]  stage_hit_direction;
    reg signed [15:0] stage_hit_base;
    reg signed [15:0] stage_seg_min;
    reg signed [15:0] stage_seg_max;
    reg               stage_direction_ok;
    reg               stage_is_door;
    reg [2:0]         stage_buy_kind;
    reg               stage_is_spawn;
    reg               stage_is_entry_wall;

    reg               stage_has_spawn_opening;
    reg signed [15:0] stage_opening_min;
    reg signed [15:0] stage_opening_max;

    // ------------------------------------------------------------------------
    // Stage 2: distance multiply -> register.
    // ------------------------------------------------------------------------
    wire signed [33:0] distance_product =
        $signed({1'b0, stage_abs_delta}) *
        $signed({1'b0, stage_inverse});

    wire signed [31:0] distance_calc =
        $signed(distance_product) >>> 8;

    reg signed [31:0] distance_reg;

    // ------------------------------------------------------------------------
    // Stage 3: hit coordinate multiply -> register.
    // ------------------------------------------------------------------------
    wire signed [40:0] hit_product =
        $signed(stage_hit_direction) * $signed(distance_reg);

    wire signed [31:0] hit_calc =
        $signed(stage_hit_base) +
        ($signed(hit_product) >>> 7);

    reg signed [31:0] hit_reg;

    // ------------------------------------------------------------------------
    // Stage 4: bounds / nearest comparison.
    // ------------------------------------------------------------------------
    // Nearest FULL-HEIGHT wall/door.
    reg signed [31:0] best_distance;
    reg               best_valid;
    reg               best_is_door;
    reg [2:0]         best_buy_kind;

    // Nearest LOW spawn block.
    reg signed [31:0] best_spawn_distance;
    reg               best_spawn_valid;

    // V21J independent missing fourth wall.
    reg signed [31:0] best_entry_wall_distance;
    reg               best_entry_wall_valid;

    // Farthest valid side hit of the same closed spawn-box footprint.
    // Used only by the display layer to draw the horizontal roof.
    reg signed [31:0] far_spawn_distance;
    reg               far_spawn_valid;

    wire hit_inside_spawn_opening =
        stage_has_spawn_opening &&
        (hit_reg >= $signed(stage_opening_min)) &&
        (hit_reg <= $signed(stage_opening_max));

    wire current_candidate_valid =
        stage_direction_ok &&
        (distance_reg > NEAR_DEPTH) &&
        (hit_reg >= $signed(stage_seg_min)) &&
        (hit_reg <= $signed(stage_seg_max)) &&
        !hit_inside_spawn_opening;

    wire current_wall_better =
        current_candidate_valid &&
        !stage_is_spawn &&
        (!best_valid || (distance_reg < best_distance));

    wire current_spawn_better =
        current_candidate_valid &&
        stage_is_spawn &&
        (!best_spawn_valid || (distance_reg < best_spawn_distance));

    wire current_spawn_farther =
        current_candidate_valid &&
        stage_is_spawn &&
        (!far_spawn_valid || (distance_reg > far_spawn_distance));

    wire current_entry_wall_better =
        current_candidate_valid &&
        stage_is_entry_wall &&
        (!best_entry_wall_valid ||
         (distance_reg < best_entry_wall_distance));

    // ------------------------------------------------------------------------
    // Stage 5/6: shared forward-depth correction multiplier.
    // Wall and spawn are corrected on separate clocks, so this remains one
    // short DSP path rather than duplicating/composing multipliers.
    // ------------------------------------------------------------------------
    wire signed [31:0] final_selected_distance =
        (state == ST_FINAL_SPAWN)
        ? best_spawn_distance
        : ((state == ST_FINAL_SPAWN_FAR)
            ? far_spawn_distance
            : ((state == ST_FINAL_ENTRY_WALL)
                ? best_entry_wall_distance
                : best_distance));

    wire signed [40:0] final_depth_product =
        $signed(final_selected_distance) * $signed(offset_cos_reg);

    wire signed [31:0] final_depth_calc =
        $signed(final_depth_product) >>> 7;

    reg signed [31:0] final_depth_reg;
    reg               final_valid_reg;
    reg               final_door_reg;
    reg [2:0]         final_buy_kind_reg;

    reg signed [31:0] final_spawn_depth_reg;
    reg               final_spawn_valid_reg;

    reg signed [31:0] final_spawn_far_depth_reg;
    reg               final_spawn_far_valid_reg;

    reg signed [31:0] final_entry_wall_depth_reg;
    reg               final_entry_wall_valid_reg;

    // Very short registered-data -> BRAM write path.
    reg [15:0] packed_wall_depth;
    reg [15:0] packed_spawn_depth;
    reg        packed_wall_valid;
    reg [1:0]  packed_wall_type;
    reg        packed_spawn_valid;

    always @(*) begin
        cache_we         = (state == ST_WRITE_CACHE);
        cache_write_addr = column_index;

        packed_wall_valid = 1'b0;
        packed_wall_type  = 2'b00;
        packed_wall_depth = 16'd2047;

        if (final_door_reg)
            packed_wall_type = 2'b01;
        else if (final_buy_kind_reg != 3'd0)
            packed_wall_type = 2'b10;

        packed_spawn_valid = 1'b0;
        packed_spawn_depth = 16'd2047;

        if (final_valid_reg && (final_depth_reg > NEAR_DEPTH)) begin
            packed_wall_valid = 1'b1;

            if (final_depth_reg > 32'sd65535)
                packed_wall_depth = 16'hFFFF;
            else
                packed_wall_depth = final_depth_reg[15:0];
        end

        if (final_spawn_valid_reg &&
            (final_spawn_depth_reg > NEAR_DEPTH)) begin

            packed_spawn_valid = 1'b1;

            if (final_spawn_depth_reg > 32'sd65535)
                packed_spawn_depth = 16'hFFFF;
            else
                packed_spawn_depth = final_spawn_depth_reg[15:0];
        end

        cache_write_data = {
            packed_wall_valid,
            packed_wall_type,
            packed_wall_depth,
            packed_spawn_valid,
            packed_spawn_depth
        };

        buy_kind_write_data =
            packed_wall_valid ? final_buy_kind_reg : 3'd0;

        spawn_far_write_data = {
            1'b0, 16'd2047,
            1'b0, 16'd2047
        };

        if (final_spawn_far_valid_reg &&
            (final_spawn_far_depth_reg > NEAR_DEPTH)) begin

            if (final_spawn_far_depth_reg > 32'sd65535) begin
                spawn_far_write_data[33] = 1'b1;
                spawn_far_write_data[32:17] = 16'hFFFF;
            end
            else begin
                spawn_far_write_data[33] = 1'b1;
                spawn_far_write_data[32:17] =
                    final_spawn_far_depth_reg[15:0];
            end
        end

        if (final_entry_wall_valid_reg &&
            (final_entry_wall_depth_reg > NEAR_DEPTH)) begin

            if (final_entry_wall_depth_reg > 32'sd65535) begin
                spawn_far_write_data[16] = 1'b1;
                spawn_far_write_data[15:0] = 16'hFFFF;
            end
            else begin
                spawn_far_write_data[16] = 1'b1;
                spawn_far_write_data[15:0] =
                    final_entry_wall_depth_reg[15:0];
            end
        end
    end

    // ------------------------------------------------------------------------
    // Sequencer.
    // 56 segments x 4 clocks + setup/final/write ~= 230 clocks/column.
    // V21J adds one extra final-depth clock for the missing fourth wall.
    // The complete 640-column cache still finishes in roughly 1.5 ms,
    // far below the ~16.7 ms VGA frame period.
    // ------------------------------------------------------------------------
    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            state         <= ST_PREP_ANGLE;
            cache_ready   <= 1'b0;

            column_index  <= 10'd0;
            segment_index <= 6'd0;

            build_camera_x   <= 16'sd0;
            build_camera_z   <= 16'sd0;
            build_camera_yaw <= 8'd0;

            build_door_ul_open <= 1'b0;
            build_door_ur_open <= 1'b0;
            build_door_ll_open <= 1'b0;
            build_door_lr_open <= 1'b0;

            ray_angle_reg    <= 8'd0;
            offset_angle_reg <= 8'd0;

            ray_sin_reg    <= 9'sd0;
            ray_cos_reg    <= 9'sd127;
            inv_sin_reg    <= 16'hFFFF;
            inv_cos_reg    <= 16'd258;
            offset_cos_reg <= 9'sd127;

            stage_abs_delta     <= 17'd0;
            stage_inverse       <= 16'd0;
            stage_hit_direction <= 9'sd0;
            stage_hit_base      <= 16'sd0;
            stage_seg_min       <= 16'sd0;
            stage_seg_max       <= 16'sd0;
            stage_direction_ok  <= 1'b0;
            stage_is_door       <= 1'b0;
            stage_buy_kind      <= 3'd0;
            stage_is_spawn      <= 1'b0;
            stage_is_entry_wall <= 1'b0;

            stage_has_spawn_opening <= 1'b0;
            stage_opening_min <= 16'sd0;
            stage_opening_max <= 16'sd0;

            distance_reg <= 32'sd0;
            hit_reg      <= 32'sd0;

            best_distance <= 32'sd32767;
            best_valid    <= 1'b0;
            best_is_door  <= 1'b0;
            best_buy_kind <= 3'd0;

            best_spawn_distance <= 32'sd32767;
            best_spawn_valid    <= 1'b0;

            best_entry_wall_distance <= 32'sd32767;
            best_entry_wall_valid    <= 1'b0;

            far_spawn_distance <= 32'sd0;
            far_spawn_valid    <= 1'b0;

            final_depth_reg <= 32'sd0;
            final_valid_reg <= 1'b0;
            final_door_reg  <= 1'b0;
            final_buy_kind_reg <= 3'd0;

            final_spawn_depth_reg <= 32'sd0;
            final_spawn_valid_reg <= 1'b0;

            final_spawn_far_depth_reg <= 32'sd0;
            final_spawn_far_valid_reg <= 1'b0;

            final_entry_wall_depth_reg <= 32'sd0;
            final_entry_wall_valid_reg <= 1'b0;
        end
        else begin
            case (state)
                ST_IDLE: begin
                    if (frame_tick) begin
                        build_camera_x   <= camera_x;
                        build_camera_z   <= camera_z;
                        build_camera_yaw <= camera_yaw;

                        build_door_ul_open <= door_ul_open;
                        build_door_ur_open <= door_ur_open;
                        build_door_ll_open <= door_ll_open;
                        build_door_lr_open <= door_lr_open;

                        column_index <= 10'd0;
                        state <= ST_PREP_ANGLE;
                    end
                end

                ST_PREP_ANGLE: begin
                    ray_angle_reg <=
                        build_camera_yaw + wall_angle_offset_calc[7:0];

                    offset_angle_reg <= wall_angle_offset_calc[7:0];

                    state <= ST_PREP_TRIG;
                end

                ST_PREP_TRIG: begin
                    ray_sin_reg    <= trig_ray_sin;
                    ray_cos_reg    <= trig_ray_cos;
                    inv_sin_reg    <= trig_inv_sin_q8;
                    inv_cos_reg    <= trig_inv_cos_q8;
                    offset_cos_reg <= trig_offset_cos;

                    segment_index <= 6'd0;
                    best_distance <= 32'sd32767;
                    best_valid    <= 1'b0;
                    best_is_door  <= 1'b0;
                    best_buy_kind <= 3'd0;

                    best_spawn_distance <= 32'sd32767;
                    best_spawn_valid    <= 1'b0;

                    best_entry_wall_distance <= 32'sd32767;
                    best_entry_wall_valid    <= 1'b0;

                    far_spawn_distance <= 32'sd0;
                    far_spawn_valid    <= 1'b0;

                    state <= ST_SEG_SETUP;
                end

                ST_SEG_SETUP: begin
                    stage_abs_delta     <= setup_abs_plane_delta;
                    stage_inverse       <= setup_inverse;
                    stage_hit_direction <= setup_hit_direction;
                    stage_hit_base      <= setup_hit_base;
                    stage_seg_min       <= seg_min;
                    stage_seg_max       <= seg_max;
                    stage_direction_ok  <= setup_direction_ok;
                    stage_is_door       <= seg_is_door;
                    stage_buy_kind      <= seg_buy_kind;
                    stage_is_spawn      <= seg_is_spawn;
                    stage_is_entry_wall <= seg_is_entry_wall;

                    stage_has_spawn_opening <= seg_has_spawn_opening;
                    stage_opening_min <= seg_opening_min;
                    stage_opening_max <= seg_opening_max;

                    state <= ST_SEG_DISTANCE;
                end

                ST_SEG_DISTANCE: begin
                    if (stage_direction_ok)
                        distance_reg <= distance_calc;
                    else
                        distance_reg <= 32'sd0;

                    state <= ST_SEG_HIT;
                end

                ST_SEG_HIT: begin
                    if (stage_direction_ok)
                        hit_reg <= hit_calc;
                    else
                        hit_reg <= 32'sd0;

                    state <= ST_SEG_COMPARE;
                end

                ST_SEG_COMPARE: begin
                    if (current_wall_better) begin
                        best_distance <= distance_reg;
                        best_valid    <= 1'b1;
                        best_is_door  <= stage_is_door;
                        best_buy_kind <= stage_buy_kind;
                    end

                    if (current_spawn_better) begin
                        best_spawn_distance <= distance_reg;
                        best_spawn_valid    <= 1'b1;
                    end

                    if (current_spawn_farther) begin
                        far_spawn_distance <= distance_reg;
                        far_spawn_valid    <= 1'b1;
                    end

                    if (current_entry_wall_better) begin
                        best_entry_wall_distance <= distance_reg;
                        best_entry_wall_valid    <= 1'b1;
                    end

                    if (segment_index == SEGMENT_COUNT - 1) begin
                        state <= ST_FINAL_WALL;
                    end
                    else begin
                        segment_index <= segment_index + 6'd1;
                        state <= ST_SEG_SETUP;
                    end
                end

                ST_FINAL_WALL: begin
                    final_depth_reg <= final_depth_calc;
                    final_valid_reg <= best_valid;
                    final_door_reg  <= best_is_door;
                    final_buy_kind_reg <= best_buy_kind;

                    state <= ST_FINAL_SPAWN;
                end

                ST_FINAL_SPAWN: begin
                    final_spawn_depth_reg <= final_depth_calc;
                    final_spawn_valid_reg <= best_spawn_valid;

                    state <= ST_FINAL_SPAWN_FAR;
                end

                ST_FINAL_SPAWN_FAR: begin
                    final_spawn_far_depth_reg <= final_depth_calc;
                    final_spawn_far_valid_reg <= far_spawn_valid;

                    state <= ST_FINAL_ENTRY_WALL;
                end

                ST_FINAL_ENTRY_WALL: begin
                    final_entry_wall_depth_reg <= final_depth_calc;
                    final_entry_wall_valid_reg <= best_entry_wall_valid;

                    state <= ST_WRITE_CACHE;
                end

                ST_WRITE_CACHE: begin
                    if (column_index == 10'd639) begin
                        cache_ready <= 1'b1;
                        state <= ST_IDLE;
                    end
                    else begin
                        column_index <= column_index + 10'd1;
                        state <= ST_PREP_ANGLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
