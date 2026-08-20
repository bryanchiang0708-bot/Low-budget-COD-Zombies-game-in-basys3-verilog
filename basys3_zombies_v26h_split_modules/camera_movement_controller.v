// ============================================================================
// CAMERA ROTATION + 60 Hz WASD MOVEMENT + ROOM COLLISION
// ============================================================================
module camera_movement_controller (
    input  wire              clk_100mhz,
    input  wire              reset,
    input  wire              frame_tick,

    input  wire signed [7:0] mouse_dx,
    input  wire signed [7:0] mouse_dy,
    input  wire              mouse_move_valid,

    input  wire              key_w,
    input  wire              key_a,
    input  wire              key_s,
    input  wire              key_d,
    input  wire              key_space,

    input  wire              door_ul_open,
    input  wire              door_ur_open,
    input  wire              door_ll_open,
    input  wire              door_lr_open,

    input  wire              move_speed_boost,
    input  wire [2:0]        sensitivity_level,

    output reg [7:0]         camera_yaw,
    output reg signed [8:0]  camera_pitch,
    output reg signed [15:0] camera_x,
    output reg signed [15:0] camera_y,
    output reg signed [15:0] camera_z
);

    // ------------------------------------------------------------------------
    // Zombies map collision geometry
    //
    // One visible floor grid = 64 world units.
    // Player collision keeps a 20-unit margin away from wall planes.
    //
    //                   +Z
    //
    //       14x14                  12x12
    //          \                    /
    //           \---- 20x20 -------/
    //           /                   \
    //       10x10                  10x10
    //
    // The four corner side rooms are now gated by V20 purchase flags.
    // While locked, only the main 20x20 room is walkable at that connector.
    // ------------------------------------------------------------------------
    localparam signed [16:0] WALL_MARGIN = 17'sd20;

    function inside_zombies_map;
        input signed [16:0] px;
        input signed [16:0] pz;
        begin
            inside_zombies_map = 1'b0;

            // Main/start room: 20 x 20 grids
            if ((px >= -17'sd620) && (px <= 17'sd620) &&
                (pz >= -17'sd620) && (pz <= 17'sd620))
                inside_zombies_map = 1'b1;

            // Upper-left room: 14 x 14 grids
            else if (door_ul_open &&
                     (px >= -17'sd1196) && (px <= -17'sd340) &&
                     (pz >=  17'sd340)  && (pz <=  17'sd1196))
                inside_zombies_map = 1'b1;

            // Upper-right room: 12 x 12 grids
            else if (door_ur_open &&
                     (px >=  17'sd340) && (px <= 17'sd1068) &&
                     (pz >=  17'sd340) && (pz <= 17'sd1068))
                inside_zombies_map = 1'b1;

            // Lower-left room: 10 x 10 grids
            else if (door_ll_open &&
                     (px >= -17'sd940) && (px <= -17'sd340) &&
                     (pz >= -17'sd940) && (pz <= -17'sd340))
                inside_zombies_map = 1'b1;

            // Lower-right room: 10 x 10 grids
            else if (door_lr_open &&
                     (px >=  17'sd340) && (px <= 17'sd940) &&
                     (pz >= -17'sd940) && (pz <= -17'sd340))
                inside_zombies_map = 1'b1;
        end
    endfunction

    // FPS-style vertical look limit: about +/-59 degrees.
    localparam signed [8:0] PITCH_MIN = -9'sd42;
    localparam signed [8:0] PITCH_MAX =  9'sd42;

    // ------------------------------------------------------------------------
    // FPS jump - velocity + acceleration only
    //
    // No fixed jump-height clamp is used.
    // The apex is determined naturally by:
    //     JUMP_START_VELOCITY
    //     JUMP_GRAVITY
    //
    // Physics updates at the 60 Hz frame tick.
    // Gravity is currently applied once every 2 frames.
    // ------------------------------------------------------------------------
    localparam signed [15:0] CAMERA_GROUND_Y = 16'sd80;
    localparam signed [7:0]  JUMP_START_VELOCITY = 8'sd7;
    localparam signed [7:0]  JUMP_GRAVITY = 8'sd1;

    reg signed [15:0] mouse_dx_accum;
    reg signed [15:0] mouse_dy_accum;

    // Mouse sensitivity:
    // V7 used accumulator >>> 1.
    // V8 base uses accumulator >>> 3 = exactly 4x lower.
    // sensitivity_level multiplies that base by 1,2,3,4.
    reg signed [20:0] scaled_mouse_dx;
    reg signed [20:0] scaled_mouse_dy;

    // Fractional sub-step remainder.
    // Sensitivity is represented in eighths of one camera phase step.
    // Keeping the remainder prevents low-sensitivity mouse counts from
    // disappearing between 60 Hz frames.
    reg signed [7:0] mouse_x_remainder;
    reg signed [7:0] mouse_y_remainder;

    reg signed [20:0] yaw_step;
    reg signed [20:0] pitch_step;

    wire signed [8:0] sin_yaw;
    wire signed [8:0] cos_yaw;

    trig_q17 yaw_trig (
        .angle(camera_yaw),
        .sin_value(sin_yaw),
        .cos_value(cos_yaw)
    );

    // ------------------------------------------------------------------------
    // V20C HORIZONTAL MOVEMENT PIPELINE
    //
    // The old path was:
    // camera_yaw -> trig -> WASD vector -> diagonal multiply -> proposed X/Z
    // -> map collision -> camera_x/z register enable.
    //
    // That path took >22 ns.  Movement now takes a few 100 MHz clocks after
    // each 60 Hz frame_tick, which is completely imperceptible but gives each
    // arithmetic/collision stage its own timing budget.
    // ------------------------------------------------------------------------
    localparam [1:0]
        MOVE_IDLE    = 2'd0,
        MOVE_VECTOR  = 2'd1,
        MOVE_PROPOSE = 2'd2,
        MOVE_COLLIDE = 2'd3;

    reg [1:0] move_state;

    reg signed [8:0] move_sin_reg;
    reg signed [8:0] move_cos_reg;

    reg move_key_w;
    reg move_key_a;
    reg move_key_s;
    reg move_key_d;
    reg move_speed_boost_reg;

    reg signed [15:0] frame_move_x;
    reg signed [15:0] frame_move_z;

    reg signed [16:0] proposed_x_reg;
    reg signed [16:0] proposed_z_reg;

    reg signed [20:0] pitch_candidate;

    // Jump state.
    reg              key_space_d;
    reg              jump_request;
    reg              airborne;
    reg signed [7:0] jump_velocity;
    reg signed [16:0] proposed_y;

    // Gravity is applied once every 2 frame ticks.
    reg              jump_gravity_tick;

    // Divide by 8 with truncation toward zero.
    // Verilog arithmetic >>> rounds negative numbers toward -infinity,
    // which caused directional asymmetry at low sensitivity.
    function signed [20:0] div8_toward_zero;
        input signed [20:0] value;
        reg signed [20:0] magnitude;
        begin
            if (value < 0) begin
                magnitude = -value;
                div8_toward_zero = -(magnitude >>> 3);
            end else begin
                div8_toward_zero = value >>> 3;
            end
        end
    endfunction

    // V26 movement speed:
    // base = 6; speed perk = ceil(6*1.30) = 8.
    // Shift/add only; no DSP.
    function signed [15:0] move_speed_q7;
        input signed [8:0] trig_value;
        input              boost;
        reg signed [12:0] ext;
        reg signed [15:0] scaled;
        begin
            ext = {{4{trig_value[8]}}, trig_value};

            if (boost)
                scaled = $signed(ext) <<< 3;       // *8
            else
                scaled = ($signed(ext) <<< 2) +   // *6 = *4 + *2
                         ($signed(ext) <<< 1);

            move_speed_q7 = $signed(scaled) >>> 7;
        end
    endfunction

    // 45/64 = 0.703125, close to 1/sqrt(2)=0.7071.
    // Shift/add implementation avoids the old diagonal DSP multiplier.
    function signed [15:0] diagonal_scale_45_64;
        input signed [15:0] value;
        reg signed [20:0] ext;
        reg signed [22:0] scaled;
        begin
            ext = {{5{value[15]}}, value};

            // *45 = *32 + *8 + *4 + *1
            scaled = ($signed(ext) <<< 5) +
                     ($signed(ext) <<< 3) +
                     ($signed(ext) <<< 2) +
                     $signed(ext);

            diagonal_scale_45_64 = $signed(scaled) >>> 6;
        end
    endfunction

    reg signed [15:0] move_raw_x_calc;
    reg signed [15:0] move_raw_z_calc;
    reg signed [15:0] move_vector_x_calc;
    reg signed [15:0] move_vector_z_calc;

    wire signed [15:0] move_sin_step =
        move_speed_q7(move_sin_reg, move_speed_boost_reg);

    wire signed [15:0] move_cos_step =
        move_speed_q7(move_cos_reg, move_speed_boost_reg);

    // This stage depends only on REGISTERS captured at frame_tick.
    always @(*) begin
        move_raw_x_calc = 16'sd0;
        move_raw_z_calc = 16'sd0;

        if (move_key_w) begin
            move_raw_x_calc = move_raw_x_calc + move_sin_step;
            move_raw_z_calc = move_raw_z_calc + move_cos_step;
        end

        if (move_key_s) begin
            move_raw_x_calc = move_raw_x_calc - move_sin_step;
            move_raw_z_calc = move_raw_z_calc - move_cos_step;
        end

        if (move_key_d) begin
            move_raw_x_calc = move_raw_x_calc + move_cos_step;
            move_raw_z_calc = move_raw_z_calc - move_sin_step;
        end

        if (move_key_a) begin
            move_raw_x_calc = move_raw_x_calc - move_cos_step;
            move_raw_z_calc = move_raw_z_calc + move_sin_step;
        end

        if ((move_key_w ^ move_key_s) &&
            (move_key_a ^ move_key_d)) begin

            move_vector_x_calc =
                diagonal_scale_45_64(move_raw_x_calc);

            move_vector_z_calc =
                diagonal_scale_45_64(move_raw_z_calc);
        end
        else begin
            move_vector_x_calc = move_raw_x_calc;
            move_vector_z_calc = move_raw_z_calc;
        end
    end

    always @(*) begin
        // Jump Y is still tiny enough to remain combinational.
        proposed_y = $signed(camera_y) + $signed(jump_velocity);

        // ------------------------------------------------------------
        // Mouse sensitivity.
        // Base = previous V7 sensitivity / 4.
        //
        // level 1: 1/8 phase unit per mouse count
        // level 2: 2/8
        // level 3: 3/8
        // level 4: 4/8 = previous V7 sensitivity
        // ------------------------------------------------------------
        scaled_mouse_dx =
            ($signed(mouse_dx_accum) *
             $signed({1'b0, sensitivity_level})) +
            $signed(mouse_x_remainder);

        scaled_mouse_dy =
            ($signed(mouse_dy_accum) *
             $signed({1'b0, sensitivity_level})) +
            $signed(mouse_y_remainder);

        // Convert eighth-step fixed-point motion into whole camera steps.
        // Any fraction that cannot be applied this frame is retained below.
        yaw_step   = div8_toward_zero(scaled_mouse_dx);
        pitch_step = div8_toward_zero(scaled_mouse_dy);

        pitch_candidate =
            $signed(camera_pitch) -
            $signed(pitch_step);
    end

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            camera_yaw <= 8'd0;
            camera_pitch <= 9'sd0;
            camera_x <= 16'sd0;
            camera_y <= CAMERA_GROUND_Y;
            camera_z <= 16'sd0;

            move_state <= MOVE_IDLE;
            move_sin_reg <= 9'sd0;
            move_cos_reg <= 9'sd127;

            move_key_w <= 1'b0;
            move_key_a <= 1'b0;
            move_key_s <= 1'b0;
            move_key_d <= 1'b0;
            move_speed_boost_reg <= 1'b0;

            frame_move_x <= 16'sd0;
            frame_move_z <= 16'sd0;

            proposed_x_reg <= 17'sd0;
            proposed_z_reg <= 17'sd0;

            key_space_d <= 1'b0;
            jump_request <= 1'b0;
            airborne <= 1'b0;
            jump_velocity <= 8'sd0;
            jump_gravity_tick <= 1'b0;

            mouse_dx_accum <= 16'sd0;
            mouse_dy_accum <= 16'sd0;
            mouse_x_remainder <= 8'sd0;
            mouse_y_remainder <= 8'sd0;
        end else begin

            // Capture a single jump request on the rising edge of Space.
            // Presses while already airborne are ignored, preventing
            // mid-air double jumps and held-Space auto-bunny-hopping.
            key_space_d <= key_space;

            if (key_space && !key_space_d && !airborne)
                jump_request <= 1'b1;

            if (mouse_move_valid) begin
                mouse_dx_accum <= mouse_dx_accum +
                                  {{8{mouse_dx[7]}}, mouse_dx};
                mouse_dy_accum <= mouse_dy_accum +
                                  {{8{mouse_dy[7]}}, mouse_dy};
            end

            // ------------------------------------------------------------
            // V20C horizontal movement pipeline.
            // ------------------------------------------------------------
            case (move_state)
                MOVE_VECTOR: begin
                    // Registered yaw trig + registered keys -> movement vector.
                    frame_move_x <= move_vector_x_calc;
                    frame_move_z <= move_vector_z_calc;
                    move_state <= MOVE_PROPOSE;
                end

                MOVE_PROPOSE: begin
                    // Movement vector -> proposed world coordinate.
                    proposed_x_reg <=
                        $signed({camera_x[15], camera_x}) +
                        $signed(frame_move_x);

                    proposed_z_reg <=
                        $signed({camera_z[15], camera_z}) +
                        $signed(frame_move_z);

                    move_state <= MOVE_COLLIDE;
                end

                MOVE_COLLIDE: begin
                    // Proposed coordinate -> static-map collision -> position.
                    // First try full X/Z, then one axis at a time for sliding.
                    if (inside_zombies_map(
                            proposed_x_reg,
                            proposed_z_reg)) begin

                        camera_x <= proposed_x_reg[15:0];
                        camera_z <= proposed_z_reg[15:0];
                    end
                    else if (inside_zombies_map(
                                 proposed_x_reg,
                                 $signed({camera_z[15], camera_z}))) begin

                        camera_x <= proposed_x_reg[15:0];
                    end
                    else if (inside_zombies_map(
                                 $signed({camera_x[15], camera_x}),
                                 proposed_z_reg)) begin

                        camera_z <= proposed_z_reg[15:0];
                    end

                    move_state <= MOVE_IDLE;
                end

                default: begin
                    // MOVE_IDLE waits for the next frame_tick.
                end
            endcase

            if (frame_tick) begin
                camera_yaw <= camera_yaw +
                              $signed(yaw_step);

                if (pitch_candidate > PITCH_MAX)
                    camera_pitch <= PITCH_MAX;
                else if (pitch_candidate < PITCH_MIN)
                    camera_pitch <= PITCH_MIN;
                else
                    camera_pitch <= pitch_candidate[8:0];

                // Keep the unused fractional portion instead of discarding it.
                // Remainder stays in the range -7..+7.
                mouse_x_remainder <=
                    $signed(scaled_mouse_dx) -
                    ($signed(yaw_step) <<< 3);

                mouse_y_remainder <=
                    $signed(scaled_mouse_dy) -
                    ($signed(pitch_step) <<< 3);

                // A UART mouse packet arriving exactly on frame_tick is carried
                // into the next frame, as in V8.
                if (mouse_move_valid) begin
                    mouse_dx_accum <= {{8{mouse_dx[7]}}, mouse_dx};
                    mouse_dy_accum <= {{8{mouse_dy[7]}}, mouse_dy};
                end else begin
                    mouse_dx_accum <= 16'sd0;
                    mouse_dy_accum <= 16'sd0;
                end

                // --------------------------------------------------------
                // Launch one horizontal movement transaction.
                //
                // camera_x/z are NOT modified here. The next three 100 MHz
                // clocks compute vector -> proposal -> collision separately.
                // --------------------------------------------------------
                if (move_state == MOVE_IDLE) begin
                    move_sin_reg <= sin_yaw;
                    move_cos_reg <= cos_yaw;

                    move_key_w <= key_w;
                    move_key_a <= key_a;
                    move_key_s <= key_s;
                    move_key_d <= key_d;
                    move_speed_boost_reg <= move_speed_boost;

                    move_state <= MOVE_VECTOR;
                end

                // --------------------------------------------------------
                // Vertical jump physics.
                // Horizontal movement and mouse look remain active in air.
                // --------------------------------------------------------
                if (!airborne) begin
                    camera_y <= CAMERA_GROUND_Y;
                    jump_velocity <= 8'sd0;
                    jump_gravity_tick <= 1'b0;

                    if (jump_request) begin
                        airborne <= 1'b1;
                        jump_request <= 1'b0;
                        jump_gravity_tick <= 1'b0;

                        // Start the jump with the configured upward velocity.
                        camera_y <= CAMERA_GROUND_Y + JUMP_START_VELOCITY;
                        jump_velocity <= JUMP_START_VELOCITY;
                    end
                end else begin
                    // Toggle every 60 Hz frame while airborne.
                    // Gravity is applied once every 2 frames.
                    jump_gravity_tick <= ~jump_gravity_tick;

                    // Land when falling back to the ground plane.
                    if ((jump_velocity <= 0) &&
                        (proposed_y <= CAMERA_GROUND_Y)) begin
                        camera_y <= CAMERA_GROUND_Y;
                        jump_velocity <= 8'sd0;
                        airborne <= 1'b0;
                        jump_request <= 1'b0;
                        jump_gravity_tick <= 1'b0;
                    end
                    else begin
                        // Natural ballistic motion:
                        // position += velocity
                        camera_y <= proposed_y[15:0];

                        // velocity -= gravity
                        if (jump_gravity_tick)
                            jump_velocity <= jump_velocity - JUMP_GRAVITY;
                    end
                end
            end
        end
    end

endmodule
