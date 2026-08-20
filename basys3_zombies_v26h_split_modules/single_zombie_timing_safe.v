module single_zombie_timing_safe (
    input  wire               clk_100mhz,
    input  wire               reset,
    input  wire               frame_tick,

    input  wire signed [15:0] player_x,
    input  wire signed [15:0] player_z,

    input  wire               door_ul_open,
    input  wire               door_ur_open,
    input  wire               door_ll_open,
    input  wire               door_lr_open,

    input  wire               debug_shot_pulse,

    output reg signed [15:0]  zombie_x,
    output reg signed [15:0]  zombie_z,
    output reg                zombie_alive,
    output reg [2:0]          zombie_hp,

    output reg [1:0]          player_hp,

    output reg                zombie_damage_pulse,
    output reg                zombie_spawn_pulse
);

    localparam [2:0] ZOMBIE_MAX_HP = 3'd3;

    localparam signed [15:0] NODE_NEG = -16'sd500;
    localparam signed [15:0] NODE_POS =  16'sd500;

    localparam signed [15:0] ZOMBIE_CARDINAL_STEP = 16'sd2;
    localparam signed [15:0] ZOMBIE_DIAGONAL_STEP = 16'sd1;

    localparam [16:0] ATTACK_TRIGGER_RANGE = 17'd48;
    localparam [16:0] ATTACK_HIT_RANGE     = 17'd56;

    // ~60 Hz frame tick.
    localparam [8:0] SPAWN_DELAY_FRAMES        = 9'd300; // 5.0 s
    localparam [5:0] ATTACK_WINDUP_FRAMES      = 6'd30;  // 0.5 s
    localparam [5:0] ATTACK_RECOVERY_FRAMES    = 6'd42;  // 0.7 s
    localparam [5:0] PLAYER_INVULN_FRAMES      = 6'd30;  // 0.5 s
    localparam [8:0] PLAYER_REGEN_DELAY_FRAMES = 9'd300; // 5.0 s
    localparam [4:0] PLAYER_REGEN_STEP_FRAMES  = 5'd12;  // 5 HP/s

    localparam [2:0]
        Z_WAIT     = 3'd0,
        Z_CHASE    = 3'd1,
        Z_WINDUP   = 3'd2,
        Z_RECOVERY = 3'd3,
        Z_DEAD     = 3'd4;

    localparam [1:0]
        NAV_IDLE   = 2'd0,
        NAV_DIRECT = 2'd1,
        NAV_NODE   = 2'd2;

    reg [2:0] zombie_state;
    reg [8:0] spawn_counter;
    reg [5:0] attack_counter;

    reg [5:0] player_invuln_counter;
    reg [8:0] player_regen_delay;
    reg [4:0] player_regen_step;

    reg melee_hit_attempt_pulse;

    // ------------------------------------------------------------------------
    // Static five-room walkable map.
    // Same collision margins as the V16B player controller.
    // ------------------------------------------------------------------------
    function inside_zombies_map;
        input signed [17:0] px;
        input signed [17:0] pz;
        begin
            inside_zombies_map = 1'b0;

            // Main 20x20
            if ((px >= -18'sd620) && (px <= 18'sd620) &&
                (pz >= -18'sd620) && (pz <= 18'sd620))
                inside_zombies_map = 1'b1;

            // Upper-left 14x14
            else if (door_ul_open &&
                     (px >= -18'sd1196) && (px <= -18'sd340) &&
                     (pz >=  18'sd340)  && (pz <=  18'sd1196))
                inside_zombies_map = 1'b1;

            // Upper-right 12x12
            else if (door_ur_open &&
                     (px >= 18'sd340) && (px <= 18'sd1068) &&
                     (pz >= 18'sd340) && (pz <= 18'sd1068))
                inside_zombies_map = 1'b1;

            // Lower-left 10x10
            else if (door_ll_open &&
                     (px >= -18'sd940) && (px <= -18'sd340) &&
                     (pz >= -18'sd940) && (pz <= -18'sd340))
                inside_zombies_map = 1'b1;

            // Lower-right 10x10
            else if (door_lr_open &&
                     (px >= 18'sd340) && (px <= 18'sd940) &&
                     (pz >= -18'sd940) && (pz <= -18'sd340))
                inside_zombies_map = 1'b1;
        end
    endfunction

    // ------------------------------------------------------------------------
    // Current player distance - cheap Chebyshev approximation.
    // ------------------------------------------------------------------------
    wire signed [16:0] player_dx_now =
        $signed(player_x) - $signed(zombie_x);

    wire signed [16:0] player_dz_now =
        $signed(player_z) - $signed(zombie_z);

    wire [16:0] player_abs_dx_now =
        player_dx_now[16] ? -player_dx_now : player_dx_now;

    wire [16:0] player_abs_dz_now =
        player_dz_now[16] ? -player_dz_now : player_dz_now;

    wire [16:0] player_distance_now =
        (player_abs_dx_now >= player_abs_dz_now)
        ? player_abs_dx_now
        : player_abs_dz_now;

    // ------------------------------------------------------------------------
    // Sequential navigation engine.
    // ------------------------------------------------------------------------
    reg [1:0] nav_state;
    reg [2:0] nav_frame_div;

    reg signed [15:0] nav_goal_x;
    reg signed [15:0] nav_goal_z;

    reg signed [15:0] snap_player_x;
    reg signed [15:0] snap_player_z;
    reg signed [15:0] snap_zombie_x;
    reg signed [15:0] snap_zombie_z;

    reg signed [15:0] player_node_x;
    reg signed [15:0] player_node_z;
    reg signed [15:0] zombie_node_x;
    reg signed [15:0] zombie_node_z;

    reg signed [17:0] los_x;
    reg signed [17:0] los_z;
    reg signed [17:0] los_step_x;
    reg signed [17:0] los_step_z;
    reg [2:0]         los_sample_count;
    reg               los_blocked;

    wire signed [17:0] los_next_x =
        $signed(los_x) + $signed(los_step_x);

    wire signed [17:0] los_next_z =
        $signed(los_z) + $signed(los_step_z);

    wire los_next_inside =
        inside_zombies_map(los_next_x, los_next_z);

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            nav_state       <= NAV_IDLE;
            nav_frame_div   <= 3'd5;

            nav_goal_x      <= 16'sd0;
            nav_goal_z      <= 16'sd0;

            snap_player_x   <= 16'sd0;
            snap_player_z   <= 16'sd0;
            snap_zombie_x   <= 16'sd0;
            snap_zombie_z   <= 16'sd0;

            player_node_x   <= NODE_POS;
            player_node_z   <= NODE_POS;
            zombie_node_x   <= NODE_POS;
            zombie_node_z   <= NODE_POS;

            los_x           <= 18'sd0;
            los_z           <= 18'sd0;
            los_step_x      <= 18'sd0;
            los_step_z      <= 18'sd0;
            los_sample_count<= 3'd0;
            los_blocked     <= 1'b0;
        end
        else begin
            if (!zombie_alive) begin
                nav_state     <= NAV_IDLE;
                nav_frame_div <= 3'd5;
                nav_goal_x    <= player_x;
                nav_goal_z    <= player_z;
            end
            else begin
                // Request one navigation solution every ~6 frames (~10 Hz).
                if (frame_tick && (nav_state == NAV_IDLE)) begin
                    if (nav_frame_div >= 3'd5) begin
                        nav_frame_div <= 3'd0;

                        snap_player_x <= player_x;
                        snap_player_z <= player_z;
                        snap_zombie_x <= zombie_x;
                        snap_zombie_z <= zombie_z;

                        // Nearest of four +/-500 corner nodes is determined
                        // only by the coordinate signs.
                        player_node_x <= player_x[15] ? NODE_NEG : NODE_POS;
                        player_node_z <= player_z[15] ? NODE_NEG : NODE_POS;

                        zombie_node_x <= zombie_x[15] ? NODE_NEG : NODE_POS;
                        zombie_node_z <= zombie_z[15] ? NODE_NEG : NODE_POS;

                        // Start zombie -> player LOS.
                        los_x <= {{2{zombie_x[15]}}, zombie_x};
                        los_z <= {{2{zombie_z[15]}}, zombie_z};

                        los_step_x <=
                            ($signed({{2{player_x[15]}}, player_x}) -
                             $signed({{2{zombie_x[15]}}, zombie_x})) >>> 3;

                        los_step_z <=
                            ($signed({{2{player_z[15]}}, player_z}) -
                             $signed({{2{zombie_z[15]}}, zombie_z})) >>> 3;

                        los_sample_count <= 3'd0;
                        los_blocked      <= 1'b0;
                        nav_state        <= NAV_DIRECT;
                    end
                    else begin
                        nav_frame_div <= nav_frame_div + 3'd1;
                    end
                end

                // Seven interior samples, one per 100 MHz clock.
                if (nav_state == NAV_DIRECT) begin
                    los_x <= los_next_x;
                    los_z <= los_next_z;

                    if (!los_next_inside)
                        los_blocked <= 1'b1;

                    if (los_sample_count == 3'd6) begin
                        if (!los_blocked && los_next_inside) begin
                            // Direct route to player is clear.
                            nav_goal_x <= snap_player_x;
                            nav_goal_z <= snap_player_z;
                            nav_state  <= NAV_IDLE;
                        end
                        else begin
                            // Direct route blocked. Test player-nearest node.
                            los_x <= {{2{snap_zombie_x[15]}}, snap_zombie_x};
                            los_z <= {{2{snap_zombie_z[15]}}, snap_zombie_z};

                            los_step_x <=
                                ($signed({{2{player_node_x[15]}}, player_node_x}) -
                                 $signed({{2{snap_zombie_x[15]}}, snap_zombie_x})) >>> 3;

                            los_step_z <=
                                ($signed({{2{player_node_z[15]}}, player_node_z}) -
                                 $signed({{2{snap_zombie_z[15]}}, snap_zombie_z})) >>> 3;

                            los_sample_count <= 3'd0;
                            los_blocked      <= 1'b0;
                            nav_state        <= NAV_NODE;
                        end
                    end
                    else begin
                        los_sample_count <= los_sample_count + 3'd1;
                    end
                end
                else if (nav_state == NAV_NODE) begin
                    los_x <= los_next_x;
                    los_z <= los_next_z;

                    if (!los_next_inside)
                        los_blocked <= 1'b1;

                    if (los_sample_count == 3'd6) begin
                        if (!los_blocked && los_next_inside) begin
                            nav_goal_x <= player_node_x;
                            nav_goal_z <= player_node_z;
                        end
                        else begin
                            nav_goal_x <= zombie_node_x;
                            nav_goal_z <= zombie_node_z;
                        end

                        nav_state <= NAV_IDLE;
                    end
                    else begin
                        los_sample_count <= los_sample_count + 3'd1;
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // V20D PIPELINED ZOMBIE MOVEMENT
    //
    // The old timing path was:
    // zombie_x/z -> goal subtraction -> abs/ratio -> step direction
    // -> proposed X/Z -> map collision -> zombie_x/z CE.
    //
    // It is now split into:
    //
    // frame_tick : capture goal delta
    // ZM_VECTOR  : choose movement direction
    // ZM_PROPOSE : form proposed X/Z
    // ZM_CHECK   : evaluate map/door collision
    // ZM_APPLY   : update zombie X/Z using REGISTERED collision results
    //
    // Total delay is only a few 100 MHz clocks (~50 ns), invisible at 60 Hz.
    // ------------------------------------------------------------------------
    localparam [2:0]
        ZM_IDLE    = 3'd0,
        ZM_VECTOR  = 3'd1,
        ZM_PROPOSE = 3'd2,
        ZM_CHECK   = 3'd3,
        ZM_APPLY   = 3'd4;

    reg [2:0] zmove_state;

    reg signed [16:0] zmove_goal_dx_reg;
    reg signed [16:0] zmove_goal_dz_reg;

    wire [16:0] zmove_goal_abs_dx =
        zmove_goal_dx_reg[16]
        ? -zmove_goal_dx_reg
        : zmove_goal_dx_reg;

    wire [16:0] zmove_goal_abs_dz =
        zmove_goal_dz_reg[16]
        ? -zmove_goal_dz_reg
        : zmove_goal_dz_reg;

    reg signed [15:0] zmove_step_x_calc;
    reg signed [15:0] zmove_step_z_calc;

    // This stage depends ONLY on registered goal deltas.
    always @(*) begin
        zmove_step_x_calc = 16'sd0;
        zmove_step_z_calc = 16'sd0;

        // Mostly X.
        if (zmove_goal_abs_dx > (zmove_goal_abs_dz << 1)) begin
            if (zmove_goal_dx_reg > 0)
                zmove_step_x_calc = ZOMBIE_CARDINAL_STEP;
            else if (zmove_goal_dx_reg < 0)
                zmove_step_x_calc = -ZOMBIE_CARDINAL_STEP;
        end
        // Mostly Z.
        else if (zmove_goal_abs_dz > (zmove_goal_abs_dx << 1)) begin
            if (zmove_goal_dz_reg > 0)
                zmove_step_z_calc = ZOMBIE_CARDINAL_STEP;
            else if (zmove_goal_dz_reg < 0)
                zmove_step_z_calc = -ZOMBIE_CARDINAL_STEP;
        end
        // Diagonal.
        else begin
            if (zmove_goal_dx_reg > 0)
                zmove_step_x_calc = ZOMBIE_DIAGONAL_STEP;
            else if (zmove_goal_dx_reg < 0)
                zmove_step_x_calc = -ZOMBIE_DIAGONAL_STEP;

            if (zmove_goal_dz_reg > 0)
                zmove_step_z_calc = ZOMBIE_DIAGONAL_STEP;
            else if (zmove_goal_dz_reg < 0)
                zmove_step_z_calc = -ZOMBIE_DIAGONAL_STEP;
        end
    end

    reg signed [15:0] zmove_step_x_reg;
    reg signed [15:0] zmove_step_z_reg;

    reg signed [17:0] zmove_proposed_x_reg;
    reg signed [17:0] zmove_proposed_z_reg;

    // Collision is evaluated from REGISTERED proposed coordinates.
    wire zmove_full_valid_calc =
        inside_zombies_map(
            zmove_proposed_x_reg,
            zmove_proposed_z_reg);

    wire zmove_x_valid_calc =
        inside_zombies_map(
            zmove_proposed_x_reg,
            $signed({{2{zombie_z[15]}}, zombie_z}));

    wire zmove_z_valid_calc =
        inside_zombies_map(
            $signed({{2{zombie_x[15]}}, zombie_x}),
            zmove_proposed_z_reg);

    reg zmove_full_valid_reg;
    reg zmove_x_valid_reg;
    reg zmove_z_valid_reg;

    // ------------------------------------------------------------------------
    // Zombie lifecycle / chase / melee.
    // ------------------------------------------------------------------------
    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            zombie_x            <= 16'sd0;
            zombie_z            <= 16'sd0;
            zombie_alive        <= 1'b0;
            zombie_hp           <= ZOMBIE_MAX_HP;

            zombie_state        <= Z_WAIT;
            spawn_counter       <= 9'd0;
            attack_counter      <= 6'd0;

            zmove_state       <= ZM_IDLE;
            zmove_goal_dx_reg <= 17'sd0;
            zmove_goal_dz_reg <= 17'sd0;
            zmove_step_x_reg  <= 16'sd0;
            zmove_step_z_reg  <= 16'sd0;
            zmove_proposed_x_reg <= 18'sd0;
            zmove_proposed_z_reg <= 18'sd0;
            zmove_full_valid_reg <= 1'b0;
            zmove_x_valid_reg    <= 1'b0;
            zmove_z_valid_reg    <= 1'b0;

            melee_hit_attempt_pulse <= 1'b0;
            zombie_damage_pulse <= 1'b0;
            zombie_spawn_pulse  <= 1'b0;
        end
        else begin
            melee_hit_attempt_pulse <= 1'b0;
            zombie_damage_pulse     <= 1'b0;
            zombie_spawn_pulse      <= 1'b0;

            // ------------------------------------------------------------
            // Registered zombie movement pipeline.
            // ------------------------------------------------------------
            case (zmove_state)
                ZM_VECTOR: begin
                    zmove_step_x_reg <= zmove_step_x_calc;
                    zmove_step_z_reg <= zmove_step_z_calc;
                    zmove_state <= ZM_PROPOSE;
                end

                ZM_PROPOSE: begin
                    zmove_proposed_x_reg <=
                        $signed({{2{zombie_x[15]}}, zombie_x}) +
                        $signed({{2{zmove_step_x_reg[15]}}, zmove_step_x_reg});

                    zmove_proposed_z_reg <=
                        $signed({{2{zombie_z[15]}}, zombie_z}) +
                        $signed({{2{zmove_step_z_reg[15]}}, zmove_step_z_reg});

                    zmove_state <= ZM_CHECK;
                end

                ZM_CHECK: begin
                    zmove_full_valid_reg <= zmove_full_valid_calc;
                    zmove_x_valid_reg    <= zmove_x_valid_calc;
                    zmove_z_valid_reg    <= zmove_z_valid_calc;

                    zmove_state <= ZM_APPLY;
                end

                ZM_APPLY: begin
                    // Only registered flags select the final position update.
                    if (zmove_full_valid_reg) begin
                        zombie_x <= zmove_proposed_x_reg[15:0];
                        zombie_z <= zmove_proposed_z_reg[15:0];
                    end
                    else if (zmove_x_valid_reg) begin
                        zombie_x <= zmove_proposed_x_reg[15:0];
                    end
                    else if (zmove_z_valid_reg) begin
                        zombie_z <= zmove_proposed_z_reg[15:0];
                    end

                    zmove_state <= ZM_IDLE;
                end

                default: begin
                    // ZM_IDLE waits for a chase update at frame_tick.
                end
            endcase

            // TEMPORARY shooting test:
            // every click damages the live zombie by exactly 1 HP.
            if (debug_shot_pulse && zombie_alive) begin
                zombie_damage_pulse <= 1'b1;

                if (zombie_hp <= 3'd1) begin
                    zombie_hp    <= 3'd0;
                    zombie_alive <= 1'b0;
                    zombie_state <= Z_DEAD;
                    zmove_state  <= ZM_IDLE;
                end
                else begin
                    zombie_hp <= zombie_hp - 3'd1;
                end
            end
            else if (frame_tick) begin
                case (zombie_state)
                    Z_WAIT: begin
                        zombie_alive <= 1'b0;

                        if (spawn_counter >= SPAWN_DELAY_FRAMES - 1'b1) begin
                            // User-requested first spawn: exact world origin.
                            zombie_x     <= 16'sd0;
                            zombie_z     <= 16'sd0;
                            zombie_hp    <= ZOMBIE_MAX_HP;
                            zombie_alive <= 1'b1;

                            zmove_state <= ZM_IDLE;

                            attack_counter     <= 6'd0;
                            zombie_spawn_pulse <= 1'b1;
                            zombie_state       <= Z_CHASE;
                        end
                        else begin
                            spawn_counter <= spawn_counter + 9'd1;
                        end
                    end

                    Z_CHASE: begin
                        if (player_hp == 0) begin
                            // Player-death screen/state comes later.
                            zombie_x <= zombie_x;
                            zombie_z <= zombie_z;
                        end
                        else if (player_distance_now <= ATTACK_TRIGGER_RANGE) begin
                            attack_counter <= ATTACK_WINDUP_FRAMES;
                            zombie_state   <= Z_WINDUP;
                            zmove_state    <= ZM_IDLE;
                        end
                        else begin
                            // Launch one pipelined movement update.
                            // Goal subtraction is the only arithmetic done
                            // directly from zombie position on this frame.
                            if (zmove_state == ZM_IDLE) begin
                                zmove_goal_dx_reg <=
                                    $signed(nav_goal_x) - $signed(zombie_x);

                                zmove_goal_dz_reg <=
                                    $signed(nav_goal_z) - $signed(zombie_z);

                                zmove_state <= ZM_VECTOR;
                            end
                        end
                    end

                    Z_WINDUP: begin
                        if (attack_counter > 6'd1) begin
                            attack_counter <= attack_counter - 6'd1;
                        end
                        else begin
                            // Wind-up completed. The hit distance is slightly
                            // larger than the trigger distance as requested.
                            if ((player_distance_now <= ATTACK_HIT_RANGE) &&
                                (player_hp != 0))
                                melee_hit_attempt_pulse <= 1'b1;

                            attack_counter <= ATTACK_RECOVERY_FRAMES;
                            zombie_state   <= Z_RECOVERY;
                        end
                    end

                    Z_RECOVERY: begin
                        if (attack_counter > 6'd1)
                            attack_counter <= attack_counter - 6'd1;
                        else
                            zombie_state <= Z_CHASE;
                    end

                    default: begin
                        // Z_DEAD remains dead in this one-zombie prototype.
                        zombie_alive <= 1'b0;
                        zmove_state  <= ZM_IDLE;
                    end
                endcase
            end
        end
    end

    // ------------------------------------------------------------------------
    // Player HP / invulnerability / regeneration.
    //
    // 3 HP maximum.
    // Successful zombie attack = exactly 1 damage.
    // After damage:
    //   0.5 s invulnerability
    //   5.0 s regen delay
    //   then +1 HP every 0.2 s = 5 HP/s
    //
    // HP 0 is death and does NOT regenerate.
    // ------------------------------------------------------------------------
    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            player_hp             <= 2'd3;
            player_invuln_counter <= 6'd0;
            player_regen_delay    <= 9'd0;
            player_regen_step     <= 5'd0;
        end
        else if (melee_hit_attempt_pulse &&
                 (player_invuln_counter == 0) &&
                 (player_hp != 0)) begin

            player_hp <= player_hp - 2'd1;

            player_invuln_counter <= PLAYER_INVULN_FRAMES;
            player_regen_delay    <= PLAYER_REGEN_DELAY_FRAMES;
            player_regen_step     <= 5'd0;
        end
        else if (frame_tick) begin
            if (player_invuln_counter != 0)
                player_invuln_counter <= player_invuln_counter - 6'd1;

            if (player_regen_delay != 0) begin
                player_regen_delay <= player_regen_delay - 9'd1;
                player_regen_step  <= 5'd0;
            end
            else if ((player_hp != 0) && (player_hp < 2'd3)) begin
                if (player_regen_step >= PLAYER_REGEN_STEP_FRAMES - 1'b1) begin
                    player_regen_step <= 5'd0;
                    player_hp         <= player_hp + 2'd1;
                end
                else begin
                    player_regen_step <= player_regen_step + 5'd1;
                end
            end
            else begin
                player_regen_step <= 5'd0;
            end
        end
    end

endmodule
