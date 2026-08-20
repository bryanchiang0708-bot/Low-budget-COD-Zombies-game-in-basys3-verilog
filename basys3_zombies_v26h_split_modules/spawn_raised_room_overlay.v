// ============================================================================
// V21C DISPLAY-ONLY SPAWN GEOMETRY
//
// V21E preserves this module's exact V21C math.
// Only the horizontal Y=64 surface is shown by the final RGB mux.
// The vertical side-wall outputs remain calculated but are not displayed.
//
// Cross-multiplied projection avoids division:
//   Y*256 = camera_y*256 + (horizon_y - pixel_y)*depth
//
// No output from this module is allowed to feed synchronous game state.
// ============================================================================
module spawn_raised_room_overlay (
    input  wire [9:0]         pixel_y,

    input  wire signed [15:0] camera_y,
    input  wire signed [8:0]  camera_pitch,

    // Near/far vertical sides of the 3x3 spawn footprint.
    input  wire [15:0]        spawn_depth,
    input  wire               spawn_valid,

    input  wire [15:0]        spawn_far_depth,
    input  wire               spawn_far_valid,

    // V21J independent fourth wall at the room-facing side.
    input  wire [15:0]        entry_wall_depth,
    input  wire               entry_wall_valid,

    input  wire [15:0]        map_wall_depth,
    input  wire               map_wall_valid,

    output reg                room_floor_pixel,
    output reg                room_wall_pixel,
    output reg                room_roof_pixel,
    output reg                room_entry_wall_pixel
);

    // The platform you liked remains the ROOM FLOOR at Y=64.
    // The walls now extend all the way to the same Y=256 ceiling used by
    // the large playable rooms.
    localparam signed [31:0] ROOM_FLOOR_Q8 = 32'sd16384; // 64 * 256
    localparam signed [31:0] ENTRY_WALL_TOP_Q8 = 32'sd32768; // 128 * 256
                                                               // 64 tall from ground up to the raised room floor
    localparam signed [31:0] ROOM_ROOF_Q8  = 32'sd65536; // 256 * 256
                                                           // same as CEILING_Y
    localparam signed [31:0] PLANE_EPS_Q8  = 32'sd768;   // ~3 world units
    localparam integer NEAR_DEPTH = 8;

    function signed [11:0] pitch_shift_lut;
        input [5:0] magnitude;
        begin
            case (magnitude)
                6'd0:  pitch_shift_lut = 12'sd0;
                6'd1:  pitch_shift_lut = 12'sd6;
                6'd2:  pitch_shift_lut = 12'sd13;
                6'd3:  pitch_shift_lut = 12'sd19;
                6'd4:  pitch_shift_lut = 12'sd25;
                6'd5:  pitch_shift_lut = 12'sd32;
                6'd6:  pitch_shift_lut = 12'sd38;
                6'd7:  pitch_shift_lut = 12'sd44;
                6'd8:  pitch_shift_lut = 12'sd51;
                6'd9:  pitch_shift_lut = 12'sd57;
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
            end
            else begin
                if (pitch > 9'sd42)
                    mag = 6'd42;
                else
                    mag = pitch[5:0];
                shift = pitch_shift_lut(mag);
            end
            fps_horizon_y = 12'sd240 + shift;
        end
    endfunction

    wire signed [11:0] horizon_y =
        fps_horizon_y(camera_pitch);

    wire signed [12:0] vertical_delta =
        $signed({horizon_y[11], horizon_y}) -
        $signed({3'b000, pixel_y});

    wire signed [29:0] near_vertical_product =
        $signed(vertical_delta) *
        $signed({1'b0, spawn_depth});

    wire signed [29:0] far_vertical_product =
        $signed(vertical_delta) *
        $signed({1'b0, spawn_far_depth});

    wire signed [31:0] camera_y_q8 =
        $signed({{16{camera_y[15]}}, camera_y}) <<< 8;

    wire signed [31:0] near_world_y_q8 =
        camera_y_q8 + $signed(near_vertical_product);

    wire signed [31:0] far_world_y_q8 =
        camera_y_q8 + $signed(far_vertical_product);

    // Independent projection for the missing fourth wall.
    wire signed [29:0] entry_vertical_product =
        $signed(vertical_delta) *
        $signed({1'b0, entry_wall_depth});

    wire signed [31:0] entry_world_y_q8 =
        camera_y_q8 + $signed(entry_vertical_product);

    wire [16:0] wall_depth_with_tolerance =
        {1'b0, map_wall_depth} + 17'd6;

    wire room_not_behind_wall =
        !map_wall_valid ||
        ({1'b0, spawn_depth} <= wall_depth_with_tolerance);

    wire entry_wall_not_behind_wall =
        !map_wall_valid ||
        ({1'b0, entry_wall_depth} <= wall_depth_with_tolerance);

    // Horizontal floor plane at Y=64 over the 3x3 footprint.
    wire floor_crosses_plane =
        spawn_valid &&
        spawn_far_valid &&
        (spawn_depth > NEAR_DEPTH) &&
        (spawn_far_depth > spawn_depth) &&
        (
            ((near_world_y_q8 >= (ROOM_FLOOR_Q8 - PLANE_EPS_Q8)) &&
             (far_world_y_q8  <= (ROOM_FLOOR_Q8 + PLANE_EPS_Q8)))
            ||
            ((near_world_y_q8 <= (ROOM_FLOOR_Q8 + PLANE_EPS_Q8)) &&
             (far_world_y_q8  >= (ROOM_FLOOR_Q8 - PLANE_EPS_Q8)))
        );

    // Horizontal roof plane at Y=128 over the same footprint.
    wire roof_crosses_plane =
        spawn_valid &&
        spawn_far_valid &&
        (spawn_depth > NEAR_DEPTH) &&
        (spawn_far_depth > spawn_depth) &&
        (
            ((near_world_y_q8 >= (ROOM_ROOF_Q8 - PLANE_EPS_Q8)) &&
             (far_world_y_q8  <= (ROOM_ROOF_Q8 + PLANE_EPS_Q8)))
            ||
            ((near_world_y_q8 <= (ROOM_ROOF_Q8 + PLANE_EPS_Q8)) &&
             (far_world_y_q8  >= (ROOM_ROOF_Q8 - PLANE_EPS_Q8)))
        );

    always @(*) begin
        room_floor_pixel = 1'b0;
        room_wall_pixel  = 1'b0;
        room_roof_pixel  = 1'b0;
        room_entry_wall_pixel = 1'b0;

        // ------------------------------------------------------------
        // V21H NORMAL ROOM — UNCHANGED.
        // ------------------------------------------------------------
        // Vertical blue side walls: only above the floor plane.
        if (spawn_valid &&
            (spawn_depth > NEAR_DEPTH) &&
            room_not_behind_wall &&
            (near_world_y_q8 >= ROOM_FLOOR_Q8) &&
            (near_world_y_q8 <= ROOM_ROOF_Q8)) begin

            room_wall_pixel = 1'b1;
        end

        // ------------------------------------------------------------
        // V21K: ADD the previously missing FRONT PLATFORM FACE.
        //
        // This is the vertical face UNDER the raised room floor on the
        // side facing the playable room. So it goes from ground Y=0 up to
        // the raised floor at Y=64.
        // ------------------------------------------------------------
        if (entry_wall_valid &&
            (entry_wall_depth > NEAR_DEPTH) &&
            entry_wall_not_behind_wall &&
            (entry_world_y_q8 >= 32'sd0) &&
            (entry_world_y_q8 <= ROOM_FLOOR_Q8)) begin

            room_entry_wall_pixel = 1'b1;
        end

        // Raised room floor.
        if (floor_crosses_plane &&
            room_not_behind_wall) begin
            room_floor_pixel = 1'b1;
        end

        // Raised room roof.
        if (roof_crosses_plane &&
            room_not_behind_wall) begin
            room_roof_pixel = 1'b1;
        end
    end

endmodule
