// ============================================================================
// ONE MULTI-ZOMBIE AGENT SLOT
// Sequential LOS + four-node routing + pipelined movement.
// ============================================================================
module zombie_agent_round (
    input wire clk_100mhz,
    input wire reset,
    input wire soft_reset,
    input wire frame_tick,

    input wire spawn_pulse,
    input wire signed [15:0] spawn_x,
    input wire signed [15:0] spawn_z,
    input wire signed [15:0] spawn_exit_x,
    input wire signed [15:0] spawn_exit_z,

    input wire signed [15:0] player_x,
    input wire signed [15:0] player_z,
    input wire player_alive,

    input wire door_ul_open,
    input wire door_ur_open,
    input wire door_ll_open,
    input wire door_lr_open,

    input wire [6:0] spawn_hp,
    input wire movement_enable,
    input wire [6:0] shot_damage,
    input wire debug_shot_pulse,

    output reg signed [15:0] zombie_x,
    output reg signed [15:0] zombie_z,
    output reg zombie_alive,
    output reg [6:0] zombie_hp,

    // High from the first WINDUP frame through the end of RECOVERY.
    output wire attack_active,

    output reg melee_attempt_pulse,
    output reg damage_pulse,
    output reg death_pulse
);
    // V25B: spawn_hp is shared from top level.
    localparam signed [15:0] NODE_NEG = -16'sd500;
    localparam signed [15:0] NODE_POS =  16'sd500;
    localparam signed [15:0] ZOMBIE_CARDINAL_STEP = 16'sd2;
    localparam signed [15:0] ZOMBIE_DIAGONAL_STEP = 16'sd1;
    localparam [16:0] ATTACK_TRIGGER_RANGE = 17'd48;
    localparam [16:0] ATTACK_HIT_RANGE     = 17'd56;
    localparam [5:0] ATTACK_WINDUP_FRAMES   = 6'd30;
    localparam [5:0] ATTACK_RECOVERY_FRAMES = 6'd42;

    localparam [1:0]
        Z_CHASE    = 2'b00,
        Z_DEAD     = 2'b01,
        Z_WINDUP   = 2'b10,
        Z_RECOVERY = 2'b11;
    localparam [1:0] NAV_IDLE=2'd0, NAV_DIRECT=2'd1, NAV_NODE=2'd2;
    localparam [2:0] ZM_IDLE=3'd0, ZM_VECTOR=3'd1, ZM_PROPOSE=3'd2, ZM_CHECK=3'd3, ZM_APPLY=3'd4;

    // V25C: one local soft-reset replica per zombie agent.
    // This splits the former device-wide ~2900-sink async reset tree.
    (* max_fanout = 64 *) reg local_soft_reset;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset)
            local_soft_reset <= 1'b1;
        else
            local_soft_reset <= soft_reset;
    end

    wire agent_reset = reset | local_soft_reset;

    reg [1:0] zombie_state;
    reg [5:0] attack_counter;

    // V25B state encoding makes the warning output free:
    // state[1] is 1 only for WINDUP and RECOVERY.
    assign attack_active = zombie_state[1];

    // Zombie-only map includes the blue spawn rooms and a short connector
    // through their room-facing opening. Player collision remains unchanged.
    function inside_zombie_map;
        input signed [15:0] px;
        input signed [15:0] pz;
        begin
            inside_zombie_map = 1'b0;
            if ((px >= -16'sd620) && (px <= 16'sd620) &&
                (pz >= -16'sd620) && (pz <= 16'sd620))
                inside_zombie_map = 1'b1;
            else if (door_ul_open && (px >= -16'sd1196) && (px <= -16'sd340) &&
                     (pz >= 16'sd340) && (pz <= 16'sd1196))
                inside_zombie_map = 1'b1;
            else if (door_ur_open && (px >= 16'sd340) && (px <= 16'sd1068) &&
                     (pz >= 16'sd340) && (pz <= 16'sd1068))
                inside_zombie_map = 1'b1;
            else if (door_ll_open && (px >= -16'sd940) && (px <= -16'sd340) &&
                     (pz >= -16'sd940) && (pz <= -16'sd340))
                inside_zombie_map = 1'b1;
            else if (door_lr_open && (px >= 16'sd340) && (px <= 16'sd940) &&
                     (pz >= -16'sd940) && (pz <= -16'sd340))
                inside_zombie_map = 1'b1;

            // Main-room spawn rooms + connectors.
            else if ((px >= -16'sd832) && (px <= -16'sd600) &&
                     (pz >= -16'sd96) && (pz <= 16'sd96))
                inside_zombie_map = 1'b1;
            else if ((px >= 16'sd600) && (px <= 16'sd832) &&
                     (pz >= -16'sd96) && (pz <= 16'sd96))
                inside_zombie_map = 1'b1;
            else if ((px >= -16'sd96) && (px <= 16'sd96) &&
                     (pz >= -16'sd832) && (pz <= -16'sd600))
                inside_zombie_map = 1'b1;

            // Side-room spawn rooms + connectors, only after room purchase.
            else if (door_ul_open && (px >= -16'sd1408) && (px <= -16'sd1180) &&
                     (pz >= 16'sd672) && (pz <= 16'sd864))
                inside_zombie_map = 1'b1;
            else if (door_ur_open && (px >= 16'sd1050) && (px <= 16'sd1280) &&
                     (pz >= 16'sd608) && (pz <= 16'sd800))
                inside_zombie_map = 1'b1;
            else if (door_ll_open && (px >= -16'sd736) && (px <= -16'sd544) &&
                     (pz >= -16'sd1152) && (pz <= -16'sd920))
                inside_zombie_map = 1'b1;
            else if (door_lr_open && (px >= 16'sd544) && (px <= 16'sd736) &&
                     (pz >= -16'sd1152) && (pz <= -16'sd920))
                inside_zombie_map = 1'b1;
        end
    endfunction

    wire signed [16:0] pdx = $signed(player_x) - $signed(zombie_x);
    wire signed [16:0] pdz = $signed(player_z) - $signed(zombie_z);
    wire [16:0] adx = pdx[16] ? -pdx : pdx;
    wire [16:0] adz = pdz[16] ? -pdz : pdz;
    wire [16:0] player_distance = (adx >= adz) ? adx : adz;

    // V24F spawn-room escape phase.
    //
    // LUT optimization:
    // The safe exit target is stored directly in the EXISTING nav_goal_x/z
    // registers. No extra 32-bit exit-coordinate register pair and no separate
    // 32-bit equality comparator are needed.
    reg spawn_exit_active;

    // Navigation engine.
    reg [1:0] nav_state;
    reg [2:0] nav_frame_div;
    reg signed [15:0] nav_goal_x, nav_goal_z;
    reg signed [15:0] snap_player_x, snap_player_z, snap_zombie_x, snap_zombie_z;
    reg signed [15:0] player_node_x, player_node_z, zombie_node_x, zombie_node_z;
    reg signed [15:0] los_x, los_z, los_step_x, los_step_z;
    reg [2:0] los_sample_count;
    reg los_blocked;

    wire signed [15:0] los_next_x = $signed(los_x) + $signed(los_step_x);
    wire signed [15:0] los_next_z = $signed(los_z) + $signed(los_step_z);
    wire los_next_inside = inside_zombie_map(los_next_x, los_next_z);

    always @(posedge clk_100mhz or posedge agent_reset) begin
        if (agent_reset) begin
            nav_state <= NAV_IDLE; nav_frame_div <= 3'd5;
            nav_goal_x <= 16'sd0; nav_goal_z <= 16'sd0;
            snap_player_x <= 0; snap_player_z <= 0; snap_zombie_x <= 0; snap_zombie_z <= 0;
            player_node_x <= NODE_POS; player_node_z <= NODE_POS;
            zombie_node_x <= NODE_POS; zombie_node_z <= NODE_POS;
            los_x <= 0; los_z <= 0; los_step_x <= 0; los_step_z <= 0;
            los_sample_count <= 0; los_blocked <= 0;
        end
        else if (spawn_pulse) begin
            nav_state <= NAV_IDLE;
            nav_frame_div <= 3'd5;

            // First navigation target is the selected spawn-room exit node.
            nav_goal_x <= spawn_exit_x;
            nav_goal_z <= spawn_exit_z;
        end
        else if (!zombie_alive) begin
            nav_state <= NAV_IDLE; nav_frame_div <= 3'd5;
            nav_goal_x <= player_x; nav_goal_z <= player_z;
        end
        else if (spawn_exit_active) begin
            // Hold the already-loaded spawn exit target. Do not run the normal
            // LOS/corner-node navigator until the doorway has been cleared.
            nav_state <= NAV_IDLE;
            nav_frame_div <= 3'd5;
        end
        else begin
            if (frame_tick && (nav_state == NAV_IDLE)) begin
                if (nav_frame_div >= 3'd5) begin
                    nav_frame_div <= 0;
                    snap_player_x <= player_x; snap_player_z <= player_z;
                    snap_zombie_x <= zombie_x; snap_zombie_z <= zombie_z;
                    player_node_x <= player_x[15] ? NODE_NEG : NODE_POS;
                    player_node_z <= player_z[15] ? NODE_NEG : NODE_POS;
                    zombie_node_x <= zombie_x[15] ? NODE_NEG : NODE_POS;
                    zombie_node_z <= zombie_z[15] ? NODE_NEG : NODE_POS;
                    los_x <= zombie_x;
                    los_z <= zombie_z;
                    los_step_x <= ($signed(player_x) - $signed(zombie_x)) >>> 3;
                    los_step_z <= ($signed(player_z) - $signed(zombie_z)) >>> 3;
                    los_sample_count <= 0; los_blocked <= 0; nav_state <= NAV_DIRECT;
                end else nav_frame_div <= nav_frame_div + 1'b1;
            end

            if (nav_state == NAV_DIRECT) begin
                los_x <= los_next_x; los_z <= los_next_z;
                if (!los_next_inside) los_blocked <= 1'b1;
                if (los_sample_count == 3'd6) begin
                    if (!los_blocked && los_next_inside) begin
                        nav_goal_x <= snap_player_x; nav_goal_z <= snap_player_z; nav_state <= NAV_IDLE;
                    end else begin
                        los_x <= snap_zombie_x;
                        los_z <= snap_zombie_z;
                        los_step_x <= ($signed(player_node_x) - $signed(snap_zombie_x)) >>> 3;
                        los_step_z <= ($signed(player_node_z) - $signed(snap_zombie_z)) >>> 3;
                        los_sample_count <= 0; los_blocked <= 0; nav_state <= NAV_NODE;
                    end
                end else los_sample_count <= los_sample_count + 1'b1;
            end
            else if (nav_state == NAV_NODE) begin
                los_x <= los_next_x; los_z <= los_next_z;
                if (!los_next_inside) los_blocked <= 1'b1;
                if (los_sample_count == 3'd6) begin
                    if (!los_blocked && los_next_inside) begin
                        nav_goal_x <= player_node_x; nav_goal_z <= player_node_z;
                    end else begin
                        nav_goal_x <= zombie_node_x; nav_goal_z <= zombie_node_z;
                    end
                    nav_state <= NAV_IDLE;
                end else los_sample_count <= los_sample_count + 1'b1;
            end
        end
    end

    // Registered movement pipeline.
    reg [2:0] zmove_state;
    reg signed [16:0] goal_dx_reg, goal_dz_reg;

    // V24F: ONE pair of subtractors for both spawn-exit movement and normal AI.
    wire signed [16:0] nav_goal_dx_calc =
        $signed({nav_goal_x[15],nav_goal_x}) -
        $signed({zombie_x[15],zombie_x});

    wire signed [16:0] nav_goal_dz_calc =
        $signed({nav_goal_z[15],nav_goal_z}) -
        $signed({zombie_z[15],zombie_z});
    wire [16:0] goal_abs_dx = goal_dx_reg[16] ? -goal_dx_reg : goal_dx_reg;
    wire [16:0] goal_abs_dz = goal_dz_reg[16] ? -goal_dz_reg : goal_dz_reg;
    reg signed [15:0] step_x_calc, step_z_calc;
    always @(*) begin
        step_x_calc=0; step_z_calc=0;
        if (goal_abs_dx > (goal_abs_dz << 1)) begin
            if (goal_dx_reg>0) step_x_calc=ZOMBIE_CARDINAL_STEP;
            else if (goal_dx_reg<0) step_x_calc=-ZOMBIE_CARDINAL_STEP;
        end else if (goal_abs_dz > (goal_abs_dx << 1)) begin
            if (goal_dz_reg>0) step_z_calc=ZOMBIE_CARDINAL_STEP;
            else if (goal_dz_reg<0) step_z_calc=-ZOMBIE_CARDINAL_STEP;
        end else begin
            if (goal_dx_reg>0) step_x_calc=ZOMBIE_DIAGONAL_STEP;
            else if (goal_dx_reg<0) step_x_calc=-ZOMBIE_DIAGONAL_STEP;
            if (goal_dz_reg>0) step_z_calc=ZOMBIE_DIAGONAL_STEP;
            else if (goal_dz_reg<0) step_z_calc=-ZOMBIE_DIAGONAL_STEP;
        end
    end
    reg signed [15:0] step_x_reg, step_z_reg;
    reg signed [15:0] prop_x_reg, prop_z_reg;
    wire full_valid_calc = inside_zombie_map(prop_x_reg,prop_z_reg);
    wire x_valid_calc = inside_zombie_map(prop_x_reg,zombie_z);
    wire z_valid_calc = inside_zombie_map(zombie_x,prop_z_reg);
    reg full_valid_reg,x_valid_reg,z_valid_reg;

    always @(posedge clk_100mhz or posedge agent_reset) begin
        if (agent_reset) begin
            zombie_x<=0; zombie_z<=0; zombie_alive<=0; zombie_hp<=7'd10;
            zombie_state<=Z_DEAD; attack_counter<=0; zmove_state<=ZM_IDLE;
            goal_dx_reg<=0; goal_dz_reg<=0; step_x_reg<=0; step_z_reg<=0;
            prop_x_reg<=0; prop_z_reg<=0; full_valid_reg<=0; x_valid_reg<=0; z_valid_reg<=0;

            spawn_exit_active<=1'b0;

            melee_attempt_pulse<=0; damage_pulse<=0; death_pulse<=0;
        end else begin
            melee_attempt_pulse<=0; damage_pulse<=0; death_pulse<=0;

            if (spawn_pulse) begin
                zombie_x<=spawn_x;
                zombie_z<=spawn_z;
                zombie_alive<=1'b1;
                zombie_hp<=spawn_hp;

                spawn_exit_active<=1'b1;

                zombie_state<=Z_CHASE;
                attack_counter<=0;
                zmove_state<=ZM_IDLE;
            end else begin
                case(zmove_state)
                    ZM_VECTOR: begin
                        if (spawn_exit_active &&
                            (step_x_calc[2:0] == 3'b000) &&
                            (step_z_calc[2:0] == 3'b000)) begin

                            // Exit node reached. Normal AI resumes next frame.
                            spawn_exit_active <= 1'b0;
                            zmove_state <= ZM_IDLE;
                        end
                        else begin
                            step_x_reg <= step_x_calc;
                            step_z_reg <= step_z_calc;
                            zmove_state <= ZM_PROPOSE;
                        end
                    end
                    ZM_PROPOSE: begin
                        prop_x_reg <= $signed(zombie_x) + $signed(step_x_reg);
                        prop_z_reg <= $signed(zombie_z) + $signed(step_z_reg);
                        zmove_state<=ZM_CHECK;
                    end
                    ZM_CHECK: begin full_valid_reg<=full_valid_calc; x_valid_reg<=x_valid_calc; z_valid_reg<=z_valid_calc; zmove_state<=ZM_APPLY; end
                    ZM_APPLY: begin
                        if(full_valid_reg) begin zombie_x<=prop_x_reg[15:0]; zombie_z<=prop_z_reg[15:0]; end
                        else if(x_valid_reg) zombie_x<=prop_x_reg[15:0];
                        else if(z_valid_reg) zombie_z<=prop_z_reg[15:0];
                        zmove_state<=ZM_IDLE;
                    end
                    default: ;
                endcase

                if (debug_shot_pulse && zombie_alive) begin
                    // V23 variable weapon damage:
                    // pistol=3, shotgun=20, rifle=5.
                    damage_pulse <= 1'b1;

                    if (zombie_hp <= shot_damage) begin
                        zombie_hp    <= 7'd0;
                        zombie_alive <= 1'b0;
                        zombie_state <= Z_DEAD;
                        zmove_state  <= ZM_IDLE;
                        spawn_exit_active <= 1'b0;
                        death_pulse  <= 1'b1;
                    end
                    else begin
                        zombie_hp <= zombie_hp - shot_damage;
                    end
                end
                else if(frame_tick && zombie_alive) begin
                    case(zombie_state)
                        Z_CHASE: begin
                            if (spawn_exit_active) begin
                                // Use the same existing nav_goal movement path.
                                // nav_goal currently contains the safe exit node.
                                if (zmove_state == ZM_IDLE) begin
                                    goal_dx_reg <= nav_goal_dx_calc;
                                    goal_dz_reg <= nav_goal_dz_calc;
                                    zmove_state <= ZM_VECTOR;
                                end
                            end
                            else if(player_alive) begin
                                if(player_distance<=ATTACK_TRIGGER_RANGE) begin
                                    attack_counter<=ATTACK_WINDUP_FRAMES;
                                    zombie_state<=Z_WINDUP;
                                    zmove_state<=ZM_IDLE;
                                end
                                else if((zmove_state==ZM_IDLE) &&
                                             movement_enable) begin
                                    goal_dx_reg <= nav_goal_dx_calc;
                                    goal_dz_reg <= nav_goal_dz_calc;
                                    zmove_state<=ZM_VECTOR;
                                end
                            end
                        end
                        Z_WINDUP: begin
                            if(attack_counter>1) attack_counter<=attack_counter-1'b1;
                            else begin
                                if(player_alive && player_distance<=ATTACK_HIT_RANGE) melee_attempt_pulse<=1'b1;
                                attack_counter<=ATTACK_RECOVERY_FRAMES; zombie_state<=Z_RECOVERY;
                            end
                        end
                        Z_RECOVERY: begin
                            if(attack_counter>1) attack_counter<=attack_counter-1'b1;
                            else zombie_state<=Z_CHASE;
                        end
                        default: ;
                    endcase
                end
            end
        end
    end
endmodule
