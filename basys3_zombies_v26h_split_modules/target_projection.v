// ============================================================================
// WORLD -> CAMERA TRANSFORM + PERSPECTIVE TARGET PROJECTION
// Target V7: wall-anchored target + shared FPS tan-based pitch projection
// ============================================================================
module target_projection (
    input  wire signed [15:0] camera_x,
    input  wire signed [15:0] camera_y,
    input  wire signed [15:0] camera_z,
    input  wire [7:0]         camera_yaw,
    input  wire signed [8:0]  camera_pitch,

    input  wire signed [15:0] target_x,
    input  wire signed [15:0] target_y,
    input  wire signed [15:0] target_z,
    input  wire               half_size,

    output reg signed [11:0]  screen_x,
    output reg signed [11:0]  screen_y,
    output reg [7:0]          screen_radius,
    output reg                visible,
    output reg                crosshair_hit
);

    localparam integer FOCAL_LENGTH = 256;
    localparam integer TARGET_RADIUS_WORLD = 24;
    localparam integer NEAR_Z = 24;

    wire signed [8:0] sin_yaw;
    wire signed [8:0] cos_yaw;
    wire signed [8:0] sin_pitch;
    wire signed [8:0] cos_pitch;

    wire [7:0] pitch_phase = camera_pitch[7:0];

    trig_q17 yaw_trig (
        .angle(camera_yaw),
        .sin_value(sin_yaw),
        .cos_value(cos_yaw)
    );

    trig_q17 pitch_trig (
        .angle(pitch_phase),
        .sin_value(sin_pitch),
        .cos_value(cos_pitch)
    );

    reg signed [16:0] rel_x;
    reg signed [16:0] rel_y;
    reg signed [16:0] rel_z;

    reg signed [31:0] yaw_x_num;
    reg signed [31:0] yaw_z_num;
    reg signed [17:0] yaw_x;
    reg signed [17:0] yaw_z;

    reg signed [31:0] pitch_y_num;
    reg signed [31:0] pitch_z_num;
    reg signed [18:0] cam_y;
    reg signed [18:0] cam_z_depth;

    reg signed [31:0] projected_x_temp;
    reg signed [31:0] projected_y_temp;
    reg signed [31:0] radius_temp;
    reg signed [11:0] horizon_y;

    reg signed [31:0] hit_dx;
    reg signed [31:0] hit_dy;
    reg signed [63:0] hit_dist_sq;
    reg signed [63:0] hit_radius_sq;

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

    always @(*) begin
        rel_x = $signed(target_x) - $signed(camera_x);
        rel_y = $signed(target_y) - $signed(camera_y);
        rel_z = $signed(target_z) - $signed(camera_z);

        yaw_x_num =
            ($signed(rel_x) * $signed(cos_yaw)) -
            ($signed(rel_z) * $signed(sin_yaw));

        yaw_z_num =
            ($signed(rel_x) * $signed(sin_yaw)) +
            ($signed(rel_z) * $signed(cos_yaw));

        yaw_x = yaw_x_num >>> 7;
        yaw_z = yaw_z_num >>> 7;

        // Use the same vertical camera convention as the room renderer.
        // Horizontal direction/depth comes from the yaw transform.
        // Pitch is represented by shifting the screen horizon, exactly like
        // the wall/floor/ceiling renderer, so the target stays attached to
        // the world instead of following the crosshair.
        cam_y       = rel_y;
        cam_z_depth = yaw_z;

        horizon_y = fps_horizon_y(camera_pitch);

        screen_x = 12'sd320;
        screen_y = horizon_y;
        screen_radius = 8'd0;
        visible = 1'b0;
        crosshair_hit = 1'b0;

        projected_x_temp = 32'sd0;
        projected_y_temp = 32'sd0;
        radius_temp = 32'sd0;

        hit_dx = 32'sd0;
        hit_dy = 32'sd0;
        hit_dist_sq = 64'sd0;
        hit_radius_sq = 64'sd0;

        if (cam_z_depth > NEAR_Z) begin
            projected_x_temp =
                32'sd320 +
                (($signed(yaw_x) * FOCAL_LENGTH) / cam_z_depth);

            projected_y_temp =
                $signed(horizon_y) -
                (($signed(cam_y) * FOCAL_LENGTH) / cam_z_depth);

            radius_temp =
                ((half_size ? (TARGET_RADIUS_WORLD / 2) : TARGET_RADIUS_WORLD) *
                 FOCAL_LENGTH) / cam_z_depth;

            if (radius_temp < 32'sd4)
                radius_temp = 32'sd4;
            else if (radius_temp > 32'sd80)
                radius_temp = 32'sd80;

            screen_x = projected_x_temp[11:0];
            screen_y = projected_y_temp[11:0];
            screen_radius = radius_temp[7:0];

            // Only declare the target visible when its projected circle
            // overlaps the actual 640x480 viewport.
            if ((projected_x_temp + radius_temp >= 0) &&
                (projected_x_temp - radius_temp < 640) &&
                (projected_y_temp + radius_temp >= 0) &&
                (projected_y_temp - radius_temp < 480))
                visible = 1'b1;

            hit_dx = projected_x_temp - 32'sd320;
            hit_dy = projected_y_temp - 32'sd240;

            hit_dist_sq =
                (hit_dx * hit_dx) +
                (hit_dy * hit_dy);

            hit_radius_sq =
                radius_temp * radius_temp;

            if (visible && (hit_dist_sq <= hit_radius_sq))
                crosshair_hit = 1'b1;
        end
    end

endmodule
