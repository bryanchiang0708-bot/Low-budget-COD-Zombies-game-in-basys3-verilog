`timescale 1ns / 1ps

// ============================================================================
// BASYS 3 FPGA FPS - V26B AMMO HUD / PERK ICONS / REFILL FIX
// ============================================================================
// Host packets (3 bytes each):
//   C1 dx dy          mouse relative motion, signed int8
//   D0 state 00       left mouse, 1=down / 0=up
//   D1 state 00       right mouse, 1=down / 0=up
//   D2 delta 00       mouse wheel, signed int8 (+up / -down)
//   E0 key state      keyboard ASCII, 1=down / 0=up
//   F0 00 00          heartbeat
//
// V22 gameplay:
//   - Round 1 starts with 6 zombies.
//   - +1 zombie/round through R20, +2/round through R30, then cap at 45.
//   - Up to 8 zombies active simultaneously; dead slots are reused.
//   - Every new round has a 5-second grace period before spawning.
//   - Poisson-process-style random inter-arrival timing via inverse-exponential LUT.
//   - 3 main spawn rooms always active; 4 side spawns follow purchased doors.
//   - Eight independent pipelined zombie AI agents with LOS/node navigation.
//   - Melee: 0.5 s wind-up, 1 damage, 0.7 s recovery.
//   - V22E pistol: 3 base damage; zombies spawn with 10 HP.
//   - Every successful pistol hit awards +10 money.
//   - V22F: zombie sprites use per-column wall-depth occlusion.
//   - V22G: Y starts the game; death freezes the run; Y fully restarts.
//   - V22H: pistol damage requires the center crosshair to overlap a visible
//            non-occluded zombie; nearest overlapping target is selected.
//   - V23: zombie HP = 9 + current round (R1=10, +1 HP every round).
//   - V23B pistol: 20-round magazine, 3 damage, 1.2 s reload.
//   - V23B shotgun: 10-round magazine, 20 damage, 0.3 s fire cooldown,
//                    2.0 s reload, wall price 500.
//   - V23B rifle: 30-round magazine, 5 damage, full-auto ~10 shots/s,
//                  1.8 s reload, wall price 1000.
//   - R manually reloads any non-full magazine; empty mags still auto-reload.
//   - V26B ammo HUD shows magazine / reserve:
 //       pistol unlimited; shotgun 80; rifle 300.
//   - E at an owned shotgun/rifle wall refills that weapon's reserve ammo.
//   - POWER costs 1000 and gates POWER UP + ULTIMATE.
//   - POWER UP: choose max 2 perks with number keys 1..4; each costs 1000.
//       1 = +30% move speed (6 -> 8 world units/frame after ceiling)
//       2 = zombies move 30% slower
//       3 = +1 max HP
//       4 = reload time -30%
//   - ULTIMATE costs 1500 per gun:
//       magazine +30%, reserve ammo +30%, reload time -30%;
//       rifle fire rate = exactly +30% averaged over a 60-frame schedule.
//   - Ultimate-upgraded equipped weapon icon is purple.
//   - Pink wall signs show SHOTGUN 500 and RIFLE 1000.
//   - V23D shotgun successful hit reward = +30; pistol/rifle = +10.
//   - V23D mouse wheel cycles only through weapons the player owns.
//   - Player: 3 HP, 0.5 s invulnerability, regen after 5 s at 5 HP/s.
//   - Zombie projection remains DISPLAY ONLY and never feeds game state.
//   - T17 toggles PAUSE. Gameplay simulation freezes while VGA keeps drawing.
// ============================================================================

module top_aimlab (
    input  wire        clk_100mhz,
    input  wire        reset,
    input  wire        RsRx,
    input  wire        sens_button,   // Basys 3 T18: sensitivity cycle button
    input  wire        pause_button,  // Basys 3 T17: pause toggle button
    output wire        RsTx,          // Basys 3 USB-UART transmit back to Python
    output wire        hsync,
    output wire        vsync,
    output wire [11:0] vga_rgb,

    // Basys 3 four-digit seven-segment display (active low)
    output wire [6:0]  seg,
    output wire [3:0]  an,
    output wire        dp
);

    reg [1:0] pixel_div;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset)
            pixel_div <= 2'd0;
        else
            pixel_div <= pixel_div + 2'd1;
    end

    wire pixel_tick = (pixel_div == 2'd3);

    wire [9:0] pixel_x;
    wire [9:0] pixel_y;
    wire active_video;
    wire frame_tick;

    vga_controller_640x480 vga_inst (
        .clk_100mhz(clk_100mhz),
        .reset(reset),
        .pixel_tick(pixel_tick),
        .hsync(hsync),
        .vsync(vsync),
        .active_video(active_video),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .frame_tick(frame_tick)
    );

    wire [7:0] rx_byte;
    wire rx_valid;
    wire framing_error;

    uart_rx_115200 uart_inst (
        .clk_100mhz(clk_100mhz),
        .reset(reset),
        .RsRx(RsRx),
        .rx_byte(rx_byte),
        .rx_valid(rx_valid),
        .framing_error(framing_error)
    );

    wire signed [7:0] mouse_dx;
    wire signed [7:0] mouse_dy;
    wire mouse_move_valid;

    wire key_w;
    wire key_a;
    wire key_s;
    wire key_d;
    wire key_e;
    wire key_p;
    wire key_r;
    wire key_y;
    wire key_1;
    wire key_2;
    wire key_3;
    wire key_4;
    wire key_space;

    wire left_mouse;
    wire right_mouse;
    wire left_click_pulse;

    wire wheel_up_pulse;
    wire wheel_down_pulse;

    wire host_alive;

    input_packet_parser input_inst (
        .clk_100mhz(clk_100mhz),
        .reset(reset),
        .rx_byte(rx_byte),
        .rx_valid(rx_valid),

        .mouse_dx(mouse_dx),
        .mouse_dy(mouse_dy),
        .mouse_move_valid(mouse_move_valid),

        .key_w(key_w),
        .key_a(key_a),
        .key_s(key_s),
        .key_d(key_d),
        .key_e(key_e),
        .key_p(key_p),
        .key_r(key_r),
        .key_y(key_y),
        .key_1(key_1),
        .key_2(key_2),
        .key_3(key_3),
        .key_4(key_4),
        .key_space(key_space),

        .left_mouse(left_mouse),
        .right_mouse(right_mouse),
        .left_click_pulse(left_click_pulse),
        .wheel_up_pulse(wheel_up_pulse),
        .wheel_down_pulse(wheel_down_pulse),
        .host_alive(host_alive)
    );

    wire [7:0] camera_yaw;
    wire signed [8:0] camera_pitch;
    wire signed [15:0] camera_x;
    wire signed [15:0] camera_y;
    wire signed [15:0] camera_z;

    // Shared player HP is also used by the top-level game-state controller.
    wire [2:0] player_hp;

    // ------------------------------------------------------------------------
    // V20 economy / room-door state
    // ------------------------------------------------------------------------
    wire [13:0] money_value;
    wire [3:0]  money_thousands;
    wire [3:0]  money_hundreds;
    wire [3:0]  money_tens;
    wire [3:0]  money_ones;

    // V23D successful-hit reward pulse + amount.
    wire zombie_hit_reward_pulse;
    wire [5:0] zombie_hit_reward_amount;

    wire door_ul_open;
    wire door_ur_open;
    wire door_ll_open;
    wire door_lr_open;

    // V23 wall weapons.
    // 0=pistol, 1=shotgun, 2=rifle.
    wire [1:0] equipped_weapon;
    wire       shotgun_owned;
    wire       rifle_owned;
    wire       near_shotgun_buy;
    wire       near_rifle_buy;

    // V26 powered machines / perks.
    wire power_on;
    wire perk_move_speed;
    wire perk_zombie_slow;
    wire perk_extra_hp;
    wire perk_fast_reload;

    wire pistol_ultimate;
    wire shotgun_ultimate;
    wire rifle_ultimate;

    wire ammo_refill_pulse;
    wire [1:0] ammo_refill_weapon;
    wire ultimate_upgrade_pulse;
    wire [1:0] ultimate_upgrade_weapon;

    wire equipped_weapon_ultimate =
        ((equipped_weapon == 2'd0) && pistol_ultimate) ||
        ((equipped_weapon == 2'd1) && shotgun_ultimate) ||
        ((equipped_weapon == 2'd2) && rifle_ultimate);

    // Shotgun hit = +30; pistol/rifle hit = +10.
    assign zombie_hit_reward_amount =
        (equipped_weapon == 2'd1) ? 6'd30 : 6'd10;

    // ------------------------------------------------------------------------
    // V21B spawn-room geometry.
    //
    // V21G keeps the 3x3 spawn-platform geometry you liked, and treats that
    // visible platform as the FLOOR of a raised blue room.
    //
    // V21H ROOM REMAINS EXACTLY AS BEFORE:
    //   floor plane at Y = 64
    //   existing blue side walls from Y = 64 to Y = 256
    //   roof plane at Y = 256
    //
    // V21K ADDS the missing visible platform face on the previously open side:
    //   from Y = 0 to Y = 64  -> exactly 64 world units tall.
    //
    // This is the raised room's support/front face UNDER the floor, not an
    // extra upper wall above the floor.
    //
    // The 3-grid-wide opening in the attached red room wall remains.
    //
    // One map grid = 64 world units.
    // Each blue spawn block is 3x3 grids = 192x192, height = 64.
    // The centers correspond to the seven blue areas in the supplied sketch.
    //
    // All seven blocks sit outside the walkable room polygon. Therefore the
    // existing player/zombie collision prevents normal entry with ZERO added
    // collision logic on the already timing-sensitive movement path.
    //
    // V22 uses these seven room centers for actual round-based spawning.
    // ------------------------------------------------------------------------
    localparam signed [15:0] SPAWN_MAIN_LEFT_X   = -16'sd736;
    localparam signed [15:0] SPAWN_MAIN_LEFT_Z   =  16'sd0;
    localparam signed [15:0] SPAWN_MAIN_RIGHT_X  =  16'sd736;
    localparam signed [15:0] SPAWN_MAIN_RIGHT_Z  =  16'sd0;
    localparam signed [15:0] SPAWN_MAIN_BOTTOM_X =  16'sd0;
    localparam signed [15:0] SPAWN_MAIN_BOTTOM_Z = -16'sd736;

    localparam signed [15:0] SPAWN_UL_X = -16'sd1312;
    localparam signed [15:0] SPAWN_UL_Z =  16'sd768;
    localparam signed [15:0] SPAWN_UR_X =  16'sd1184;
    localparam signed [15:0] SPAWN_UR_Z =  16'sd704;
    localparam signed [15:0] SPAWN_LL_X = -16'sd640;
    localparam signed [15:0] SPAWN_LL_Z = -16'sd1056;
    localparam signed [15:0] SPAWN_LR_X =  16'sd640;
    localparam signed [15:0] SPAWN_LR_Z = -16'sd1056;

    localparam [15:0] SPAWN_BLOCK_SIZE   = 16'd192;
    localparam [15:0] SPAWN_BLOCK_HEIGHT = 16'd64;

    // Spawn-enable policy reserved for the next spawning step:
    // the three main-room blue spawns are always active; each side-room blue
    // spawn becomes eligible only after its corresponding 1000-point door is
    // purchased.
    wire spawn_main_left_enabled   = 1'b1;
    wire spawn_main_right_enabled  = 1'b1;
    wire spawn_main_bottom_enabled = 1'b1;
    wire spawn_ul_enabled = door_ul_open;
    wire spawn_ur_enabled = door_ur_open;
    wire spawn_ll_enabled = door_ll_open;
    wire spawn_lr_enabled = door_lr_open;

    // ------------------------------------------------------------------------
    // Mouse sensitivity selector
    // Base sensitivity = 1/4 of the previous V7 sensitivity.
    // T18 cycles: 1x -> 2x -> 3x -> 4x -> 1x
    // ------------------------------------------------------------------------
    wire [2:0] sensitivity_level;

    sensitivity_button_controller sens_ctrl_inst (
        .clk_100mhz       (clk_100mhz),
        .reset            (reset),
        .button_in        (sens_button),
        .sensitivity_level(sensitivity_level)
    );

    // ------------------------------------------------------------------------
    // V22G GAME FLOW
    //
    // WAIT_START -> Y -> PLAYING
    // PLAYING    -> HP=0 -> DEAD
    // DEAD       -> Y -> PLAYING with complete gameplay reset
    //
    // VGA/UART never reset on a restart. Only gameplay-state modules receive
    // gameplay_reset, so the monitor/input link stays stable.
    // ------------------------------------------------------------------------
    localparam [1:0]
        GAME_WAIT_START = 2'd0,
        GAME_PLAYING    = 2'd1,
        GAME_DEAD       = 2'd2;

    reg [1:0] game_state;
    reg       key_y_d;
    reg       game_reset_pulse;

    wire key_y_press = key_y && !key_y_d;
    wire game_is_playing = (game_state == GAME_PLAYING);
    wire game_is_waiting = (game_state == GAME_WAIT_START);
    wire game_is_dead    = (game_state == GAME_DEAD);

    // Soft reset for a new run/restart.
    wire gameplay_reset = reset || game_reset_pulse;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            game_state       <= GAME_WAIT_START;
            key_y_d          <= 1'b0;
            game_reset_pulse <= 1'b0;
        end
        else begin
            key_y_d          <= key_y;
            game_reset_pulse <= 1'b0;

            case (game_state)
                GAME_WAIT_START: begin
                    if (key_y_press) begin
                        game_reset_pulse <= 1'b1;
                        game_state <= GAME_PLAYING;
                    end
                end

                GAME_PLAYING: begin
                    if (player_hp == 3'd0)
                        game_state <= GAME_DEAD;
                end

                GAME_DEAD: begin
                    if (key_y_press) begin
                        game_reset_pulse <= 1'b1;
                        game_state <= GAME_PLAYING;
                    end
                end

                default: game_state <= GAME_WAIT_START;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // PAUSE CONTROL
    // T17 only matters during active gameplay.
    // ------------------------------------------------------------------------
    wire pause_active;

    pause_button_controller pause_ctrl_inst (
        .clk_100mhz (clk_100mhz),
        .reset      (gameplay_reset),
        .frame_tick (frame_tick),
        .button_in  (pause_button),
        .pause_active(pause_active)
    );

    // ------------------------------------------------------------------------
    // V24C GAME-SYNCED BACKGROUND MUSIC COMMANDS
    //
    // Compact command bus keeps LUT cost low:
    //   3'd1 = start/restart from beginning
    //   3'd2 = pause at current position
    //   3'd3 = resume from paused position
    //   3'd4 = stop/reset position (death)
    //
    // Initial Y start and Y-after-death restart both use START_RESET.
    // ------------------------------------------------------------------------
    localparam [2:0]
        MUSIC_CMD_NONE        = 3'd0,
        MUSIC_CMD_START_RESET = 3'd1,
        MUSIC_CMD_PAUSE       = 3'd2,
        MUSIC_CMD_RESUME      = 3'd3,
        MUSIC_CMD_STOP_RESET  = 3'd4;

    reg       music_cmd_valid;
    reg [2:0] music_cmd_code;

    reg       music_pause_previous;
    reg       music_dead_previous;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            music_cmd_valid      <= 1'b0;
            music_cmd_code       <= MUSIC_CMD_NONE;
            music_pause_previous <= 1'b0;
            music_dead_previous  <= 1'b0;
        end
        else begin
            music_cmd_valid <= 1'b0;
            music_cmd_code  <= MUSIC_CMD_NONE;

            // A new run begins after either Y on the start screen or
            // Y on the YOU DIED screen. Start the track from 0:00.
            if (game_reset_pulse) begin
                music_cmd_valid <= 1'b1;
                music_cmd_code  <= MUSIC_CMD_START_RESET;

                // gameplay_reset clears the pause controller too.
                music_pause_previous <= 1'b0;
                music_dead_previous  <= 1'b0;
            end
            else begin
                // Death has priority over pause/resume.
                if (game_is_dead && !music_dead_previous) begin
                    music_cmd_valid <= 1'b1;
                    music_cmd_code  <= MUSIC_CMD_STOP_RESET;
                end
                else if (game_is_playing &&
                         (pause_active != music_pause_previous)) begin
                    music_cmd_valid <= 1'b1;

                    if (pause_active)
                        music_cmd_code <= MUSIC_CMD_PAUSE;
                    else
                        music_cmd_code <= MUSIC_CMD_RESUME;
                end

                music_pause_previous <= pause_active;
                music_dead_previous  <= game_is_dead;
            end
        end
    end

    wire game_frame_tick =
        frame_tick && game_is_playing && !pause_active;

    wire game_left_click_pulse =
        left_click_pulse && game_is_playing && !pause_active;

    camera_movement_controller camera_inst (
        .clk_100mhz(clk_100mhz),
        .reset(gameplay_reset),
        .frame_tick(game_frame_tick),

        .mouse_dx(mouse_dx),
        .mouse_dy(mouse_dy),
        .mouse_move_valid(mouse_move_valid && game_is_playing && !pause_active),

        .key_w(key_w && game_is_playing && !pause_active),
        .key_a(key_a && game_is_playing && !pause_active),
        .key_s(key_s && game_is_playing && !pause_active),
        .key_d(key_d && game_is_playing && !pause_active),
        .key_space(key_space && game_is_playing && !pause_active),

        .door_ul_open(door_ul_open),
        .door_ur_open(door_ur_open),
        .door_ll_open(door_ll_open),
        .door_lr_open(door_lr_open),

        .move_speed_boost(perk_move_speed),
        .sensitivity_level(sensitivity_level),

        .camera_yaw(camera_yaw),
        .camera_pitch(camera_pitch),
        .camera_x(camera_x),
        .camera_y(camera_y),
        .camera_z(camera_z)
    );

    // ------------------------------------------------------------------------
    // Money + locked-room purchasing.
    // P (held): +10 every frame, capped at 9999.
    // E (press): buy a nearby locked room for 1000.
    // ------------------------------------------------------------------------
    zombies_economy_doors economy_inst (
        .clk_100mhz(clk_100mhz),
        .reset(gameplay_reset),
        .frame_tick(game_frame_tick),

        .key_p(key_p && game_is_playing && !pause_active),
        .key_e(key_e && game_is_playing && !pause_active),

        .key_1(key_1 && game_is_playing && !pause_active),
        .key_2(key_2 && game_is_playing && !pause_active),
        .key_3(key_3 && game_is_playing && !pause_active),
        .key_4(key_4 && game_is_playing && !pause_active),

        .wheel_up_pulse(wheel_up_pulse && game_is_playing && !pause_active),
        .wheel_down_pulse(wheel_down_pulse && game_is_playing && !pause_active),

        .hit_reward_pulse(zombie_hit_reward_pulse && game_is_playing && !pause_active),
        .hit_reward_amount(zombie_hit_reward_amount),

        .player_x(camera_x),
        .player_z(camera_z),

        .money_value(money_value),
        .money_thousands(money_thousands),
        .money_hundreds(money_hundreds),
        .money_tens(money_tens),
        .money_ones(money_ones),

        .door_ul_open(door_ul_open),
        .door_ur_open(door_ur_open),
        .door_ll_open(door_ll_open),
        .door_lr_open(door_lr_open),

        .equipped_weapon(equipped_weapon),
        .shotgun_owned(shotgun_owned),
        .rifle_owned(rifle_owned),
        .near_shotgun_buy(near_shotgun_buy),
        .near_rifle_buy(near_rifle_buy),

        .power_on(power_on),
        .perk_move_speed(perk_move_speed),
        .perk_zombie_slow(perk_zombie_slow),
        .perk_extra_hp(perk_extra_hp),
        .perk_fast_reload(perk_fast_reload),

        .pistol_ultimate(pistol_ultimate),
        .shotgun_ultimate(shotgun_ultimate),
        .rifle_ultimate(rifle_ultimate),

        .ammo_refill_pulse(ammo_refill_pulse),
        .ammo_refill_weapon(ammo_refill_weapon),
        .ultimate_upgrade_pulse(ultimate_upgrade_pulse),
        .ultimate_upgrade_weapon(ultimate_upgrade_weapon)
    );

    // ------------------------------------------------------------------------
    // V23 WEAPON / MAGAZINE / RELOAD CONTROLLER
    //
    // "Round" in the weapon description is treated as a magazine:
    //   pistol  = 20
    //   shotgun = 10
    //   rifle   = 30
    //
    // V26 reserve ammo:
    //   pistol = unlimited
    //   shotgun = 80 base / 104 Ultimate
    //   rifle = 300 base / 390 Ultimate
    // HUD remains magazine-only to preserve LUT/timing headroom.
    // ------------------------------------------------------------------------
    wire       weapon_fire_pulse;
    wire       pistol_fire_pulse;
    wire       shotgun_fire_pulse;
    wire       rifle_fire_pulse;
    wire [6:0] weapon_damage;
    wire [5:0] weapon_ammo;

    // V26B current reserve for the equipped gun.
    // Pistol sets weapon_reserve_unlimited instead of using a finite value.
    wire [8:0] weapon_reserve;
    wire       weapon_reserve_unlimited;

    wire       weapon_reloading;
    wire [4:0] reload_tenths_remaining;

    weapon_system_controller weapon_system_inst (
        .clk_100mhz(clk_100mhz),
        .reset(gameplay_reset),
        .frame_tick(game_frame_tick),

        .left_click_pulse(game_left_click_pulse),
        .left_mouse_held(left_mouse && game_is_playing && !pause_active),
        .reload_key(key_r && game_is_playing && !pause_active),

        .equipped_weapon(equipped_weapon),

        .fast_reload_perk(perk_fast_reload),
        .pistol_ultimate(pistol_ultimate),
        .shotgun_ultimate(shotgun_ultimate),
        .rifle_ultimate(rifle_ultimate),

        .ammo_refill_pulse(ammo_refill_pulse),
        .ammo_refill_weapon(ammo_refill_weapon),
        .ultimate_upgrade_pulse(ultimate_upgrade_pulse),
        .ultimate_upgrade_weapon(ultimate_upgrade_weapon),

        .fire_pulse(weapon_fire_pulse),
        .pistol_fire_pulse(pistol_fire_pulse),
        .shotgun_fire_pulse(shotgun_fire_pulse),
        .rifle_fire_pulse(rifle_fire_pulse),

        .shot_damage(weapon_damage),
        .ammo_count(weapon_ammo),
        .reserve_count(weapon_reserve),
        .reserve_unlimited(weapon_reserve_unlimited),
        .reload_active(weapon_reloading),
        .reload_tenths_remaining(reload_tenths_remaining)
    );


    // ------------------------------------------------------------------------
    // Five-room wall raycaster.
    //
    // Wall intersections are calculated sequentially once per screen column
    // and cached. This keeps the large non-rectangular map from duplicating
    // dozens of divider/multiplier paths inside the pixel renderer.
    // ------------------------------------------------------------------------
    wire [15:0]        map_wall_depth;
    wire               map_wall_valid;
    wire               map_wall_is_door;
    wire               map_wall_is_shotgun_buy;
    wire               map_wall_is_rifle_buy;

    // V24 visual-only pink stations from IMG_0407.
    wire               map_wall_is_power_station;
    wire               map_wall_is_ultimate_station;
    wire               map_wall_is_powerup_station;
    wire               map_wall_is_luckybox_station;

    // V21 keeps low spawn-block depth separate from the full-height wall
    // depth. This lets the blue block occupy only Y=0..64 while the normal
    // wall/room background can still render above it.
    wire [15:0]        spawn_block_depth;
    wire               spawn_block_valid;

    // V21C also keeps the FAR side of the same spawn box.
    // Near + far depth define the visible roof span for each screen column.
    wire [15:0]        spawn_block_far_depth;
    wire               spawn_block_far_valid;

    // V21J: independent depth for ONLY the missing fourth wall that faces
    // the playable room.  V21H's existing room geometry is untouched.
    wire [15:0]        spawn_entry_wall_depth;
    wire               spawn_entry_wall_valid;

    zombies_map_wall_raycaster map_wall_raycast_inst (
        .clk_100mhz (clk_100mhz),
        .reset      (reset),
        .frame_tick (frame_tick),
        .pixel_tick (pixel_tick),

        .camera_x   (camera_x),
        .camera_z   (camera_z),
        .camera_yaw (camera_yaw),

        .door_ul_open(door_ul_open),
        .door_ur_open(door_ur_open),
        .door_ll_open(door_ll_open),
        .door_lr_open(door_lr_open),

        .pixel_x    (pixel_x),

        .wall_depth   (map_wall_depth),
        .wall_valid   (map_wall_valid),
        .wall_is_door (map_wall_is_door),
        .wall_is_shotgun_buy(map_wall_is_shotgun_buy),
        .wall_is_rifle_buy(map_wall_is_rifle_buy),

        .wall_is_power_station(map_wall_is_power_station),
        .wall_is_ultimate_station(map_wall_is_ultimate_station),
        .wall_is_powerup_station(map_wall_is_powerup_station),
        .wall_is_luckybox_station(map_wall_is_luckybox_station),

        .spawn_depth      (spawn_block_depth),
        .spawn_valid      (spawn_block_valid),
        .spawn_far_depth  (spawn_block_far_depth),
        .spawn_far_valid  (spawn_block_far_valid),

        .entry_wall_depth (spawn_entry_wall_depth),
        .entry_wall_valid (spawn_entry_wall_valid)
    );

    // ------------------------------------------------------------------------
    // V22 ROUND / SPAWN / MULTI-ZOMBIE SYSTEM
    //
    // Round population pattern:
    //   Round 1 starts at 6 zombies.
    //   +1 zombie / round through round 20.
    //   +2 zombies / round through round 30.
    //   Round 30 population is then capped for later rounds.
    //
    // Active FPGA zombie cap = 8. The round quota can be much larger; dead
    // slots are reused until the total spawned count reaches the round quota.
    //
    // Spawn eligibility:
    //   main-left / main-right / main-bottom = always enabled
    //   UL / UR / LL / LR = enabled only after that room door is purchased
    //
    // A new round has a fixed 5 second grace period. After grace, spawn gaps
    // use a discrete inverse-exponential table driven by an LFSR. That gives
    // the inter-arrival behavior of a Poisson process without a divider/log.
    // ------------------------------------------------------------------------
    wire [6:0] current_round;
    wire [6:0] round_quota;
    wire [6:0] round_spawned_count;
    wire       round_grace_active;

    // V25B SAFE OPT:
    // Round-scaled zombie HP is identical for every zombie spawned in a round,
    // so calculate it once rather than inside all 8 zombie agents.
    // R1=10, R2=11, ... R99=108.
    wire [6:0] shared_zombie_spawn_hp = current_round + 7'd9;

    // V24: one-clock pulse whenever the round number increments.
    reg [6:0] round_sound_previous;
    reg       round_change_sound_pulse;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            round_sound_previous <= 7'd1;
            round_change_sound_pulse <= 1'b0;
        end
        else begin
            round_change_sound_pulse <= 1'b0;

            if (game_reset_pulse) begin
                round_sound_previous <= 7'd1;
            end
            else if (game_is_playing &&
                     (current_round != round_sound_previous)) begin
                round_sound_previous <= current_round;
                round_change_sound_pulse <= 1'b1;
            end
        end
    end

    wire       round_spawn_pulse;
    wire [2:0] round_spawn_slot;
    wire signed [15:0] round_spawn_x;
    wire signed [15:0] round_spawn_z;

    // V24F safe node just beyond the opening of the selected spawn room.
    wire signed [15:0] round_spawn_exit_x;
    wire signed [15:0] round_spawn_exit_z;

    wire [7:0] zombie_alive_mask;
    wire [7:0] zombie_death_pulses;

    zombies_round_spawn_controller round_spawn_inst (
        .clk_100mhz(clk_100mhz),
        .reset(gameplay_reset),
        .frame_tick(game_frame_tick),

        .door_ul_open(door_ul_open),
        .door_ur_open(door_ur_open),
        .door_ll_open(door_ll_open),
        .door_lr_open(door_lr_open),

        .zombie_alive_mask(zombie_alive_mask),
        .zombie_death_pulses(zombie_death_pulses),

        .current_round(current_round),
        .round_quota(round_quota),
        .round_spawned_count(round_spawned_count),
        .round_grace_active(round_grace_active),

        .spawn_pulse(round_spawn_pulse),
        .spawn_slot(round_spawn_slot),
        .spawn_x(round_spawn_x),
        .spawn_z(round_spawn_z),
        .spawn_exit_x(round_spawn_exit_x),
        .spawn_exit_z(round_spawn_exit_z)
    );

    // Player HP is shared by all zombies. Multiple simultaneous attack
    // attempts still cause only one point of damage because invulnerability
    // is applied centrally.
    wire [7:0] zombie_melee_attempts;

    zombie_player_health player_health_inst (
        .clk_100mhz(clk_100mhz),
        .reset(gameplay_reset),
        .frame_tick(game_frame_tick),
        .extra_hp_perk(perk_extra_hp),
        .melee_attempts(zombie_melee_attempts),
        .player_hp(player_hp)
    );

    // ------------------------------------------------------------------------
    // V26 shared zombie-slow cadence.
    //
    // Normal chase movement is allowed on 7 of every 10 gameplay frames when
    // the slow-zombie perk is active = exactly 30% slower average movement.
    // Spawn-room exit movement deliberately ignores this gate.
    // ------------------------------------------------------------------------
    reg [3:0] zombie_slow_phase;

    always @(posedge clk_100mhz or posedge gameplay_reset) begin
        if (gameplay_reset)
            zombie_slow_phase <= 4'd0;
        else if (game_frame_tick) begin
            if (zombie_slow_phase == 4'd9)
                zombie_slow_phase <= 4'd0;
            else
                zombie_slow_phase <= zombie_slow_phase + 4'd1;
        end
    end

    wire zombie_normal_move_enable =
        !perk_zombie_slow || (zombie_slow_phase < 4'd7);

    // ------------------------------------------------------------------------
    // Eight active zombie slots.
    // ------------------------------------------------------------------------
    wire signed [15:0] z0_x, z0_z, z1_x, z1_z, z2_x, z2_z, z3_x, z3_z;
    wire signed [15:0] z4_x, z4_z, z5_x, z5_z, z6_x, z6_z, z7_x, z7_z;
    wire z0_alive, z1_alive, z2_alive, z3_alive;
    wire z4_alive, z5_alive, z6_alive, z7_alive;
    wire [6:0] z0_hp, z1_hp, z2_hp, z3_hp, z4_hp, z5_hp, z6_hp, z7_hp;
    wire z0_melee, z1_melee, z2_melee, z3_melee, z4_melee, z5_melee, z6_melee, z7_melee;

    // V24D: asserted through the full melee cycle:
    // WINDUP -> strike -> RECOVERY.
    wire z0_attacking, z1_attacking, z2_attacking, z3_attacking;
    wire z4_attacking, z5_attacking, z6_attacking, z7_attacking;

    wire z0_hit, z1_hit, z2_hit, z3_hit, z4_hit, z5_hit, z6_hit, z7_hit;
    wire z0_dead, z1_dead, z2_dead, z3_dead, z4_dead, z5_dead, z6_dead, z7_dead;

    assign zombie_alive_mask = {
        z7_alive, z6_alive, z5_alive, z4_alive,
        z3_alive, z2_alive, z1_alive, z0_alive
    };

    assign zombie_death_pulses = {
        z7_dead, z6_dead, z5_dead, z4_dead,
        z3_dead, z2_dead, z1_dead, z0_dead
    };

    assign zombie_melee_attempts = {
        z7_melee, z6_melee, z5_melee, z4_melee,
        z3_melee, z2_melee, z1_melee, z0_melee
    };

    // V22H aimed shooting.
    //
    // A click no longer automatically damages a live zombie. A separate
    // sequential hit-test engine checks the center crosshair against the
    // REGISTERED zombie projections one slot at a time and returns at most
    // one one-clock damage pulse for the nearest valid target.
    wire [7:0] aimed_shot_onehot;

    wire sp0 = round_spawn_pulse && (round_spawn_slot == 3'd0);
    wire sp1 = round_spawn_pulse && (round_spawn_slot == 3'd1);
    wire sp2 = round_spawn_pulse && (round_spawn_slot == 3'd2);
    wire sp3 = round_spawn_pulse && (round_spawn_slot == 3'd3);
    wire sp4 = round_spawn_pulse && (round_spawn_slot == 3'd4);
    wire sp5 = round_spawn_pulse && (round_spawn_slot == 3'd5);
    wire sp6 = round_spawn_pulse && (round_spawn_slot == 3'd6);
    wire sp7 = round_spawn_pulse && (round_spawn_slot == 3'd7);

    zombie_agent_round zagent0 (
        .clk_100mhz(clk_100mhz),
        .reset(reset),
        .soft_reset(game_reset_pulse),
        .frame_tick(game_frame_tick),
        .spawn_pulse(sp0), .spawn_x(round_spawn_x), .spawn_z(round_spawn_z),
        .spawn_exit_x(round_spawn_exit_x), .spawn_exit_z(round_spawn_exit_z),
        .player_x(camera_x), .player_z(camera_z), .player_alive(player_hp != 0),
        .door_ul_open(door_ul_open), .door_ur_open(door_ur_open),
        .door_ll_open(door_ll_open), .door_lr_open(door_lr_open),
        .spawn_hp(shared_zombie_spawn_hp),
        .movement_enable(zombie_normal_move_enable),
        .shot_damage(weapon_damage),
        .debug_shot_pulse(aimed_shot_onehot[0]),
        .zombie_x(z0_x), .zombie_z(z0_z), .zombie_alive(z0_alive), .zombie_hp(z0_hp),
        .attack_active(z0_attacking),
        .melee_attempt_pulse(z0_melee), .damage_pulse(z0_hit), .death_pulse(z0_dead));

    zombie_agent_round zagent1 (
        .clk_100mhz(clk_100mhz),
        .reset(reset),
        .soft_reset(game_reset_pulse),
        .frame_tick(game_frame_tick),
        .spawn_pulse(sp1), .spawn_x(round_spawn_x), .spawn_z(round_spawn_z),
        .spawn_exit_x(round_spawn_exit_x), .spawn_exit_z(round_spawn_exit_z),
        .player_x(camera_x), .player_z(camera_z), .player_alive(player_hp != 0),
        .door_ul_open(door_ul_open), .door_ur_open(door_ur_open),
        .door_ll_open(door_ll_open), .door_lr_open(door_lr_open),
        .spawn_hp(shared_zombie_spawn_hp),
        .movement_enable(zombie_normal_move_enable),
        .shot_damage(weapon_damage),
        .debug_shot_pulse(aimed_shot_onehot[1]),
        .zombie_x(z1_x), .zombie_z(z1_z), .zombie_alive(z1_alive), .zombie_hp(z1_hp),
        .attack_active(z1_attacking),
        .melee_attempt_pulse(z1_melee), .damage_pulse(z1_hit), .death_pulse(z1_dead));

    zombie_agent_round zagent2 (
        .clk_100mhz(clk_100mhz),
        .reset(reset),
        .soft_reset(game_reset_pulse),
        .frame_tick(game_frame_tick),
        .spawn_pulse(sp2), .spawn_x(round_spawn_x), .spawn_z(round_spawn_z),
        .spawn_exit_x(round_spawn_exit_x), .spawn_exit_z(round_spawn_exit_z),
        .player_x(camera_x), .player_z(camera_z), .player_alive(player_hp != 0),
        .door_ul_open(door_ul_open), .door_ur_open(door_ur_open),
        .door_ll_open(door_ll_open), .door_lr_open(door_lr_open),
        .spawn_hp(shared_zombie_spawn_hp),
        .movement_enable(zombie_normal_move_enable),
        .shot_damage(weapon_damage),
        .debug_shot_pulse(aimed_shot_onehot[2]),
        .zombie_x(z2_x), .zombie_z(z2_z), .zombie_alive(z2_alive), .zombie_hp(z2_hp),
        .attack_active(z2_attacking),
        .melee_attempt_pulse(z2_melee), .damage_pulse(z2_hit), .death_pulse(z2_dead));

    zombie_agent_round zagent3 (
        .clk_100mhz(clk_100mhz),
        .reset(reset),
        .soft_reset(game_reset_pulse),
        .frame_tick(game_frame_tick),
        .spawn_pulse(sp3), .spawn_x(round_spawn_x), .spawn_z(round_spawn_z),
        .spawn_exit_x(round_spawn_exit_x), .spawn_exit_z(round_spawn_exit_z),
        .player_x(camera_x), .player_z(camera_z), .player_alive(player_hp != 0),
        .door_ul_open(door_ul_open), .door_ur_open(door_ur_open),
        .door_ll_open(door_ll_open), .door_lr_open(door_lr_open),
        .spawn_hp(shared_zombie_spawn_hp),
        .movement_enable(zombie_normal_move_enable),
        .shot_damage(weapon_damage),
        .debug_shot_pulse(aimed_shot_onehot[3]),
        .zombie_x(z3_x), .zombie_z(z3_z), .zombie_alive(z3_alive), .zombie_hp(z3_hp),
        .attack_active(z3_attacking),
        .melee_attempt_pulse(z3_melee), .damage_pulse(z3_hit), .death_pulse(z3_dead));

    zombie_agent_round zagent4 (
        .clk_100mhz(clk_100mhz),
        .reset(reset),
        .soft_reset(game_reset_pulse),
        .frame_tick(game_frame_tick),
        .spawn_pulse(sp4), .spawn_x(round_spawn_x), .spawn_z(round_spawn_z),
        .spawn_exit_x(round_spawn_exit_x), .spawn_exit_z(round_spawn_exit_z),
        .player_x(camera_x), .player_z(camera_z), .player_alive(player_hp != 0),
        .door_ul_open(door_ul_open), .door_ur_open(door_ur_open),
        .door_ll_open(door_ll_open), .door_lr_open(door_lr_open),
        .spawn_hp(shared_zombie_spawn_hp),
        .movement_enable(zombie_normal_move_enable),
        .shot_damage(weapon_damage),
        .debug_shot_pulse(aimed_shot_onehot[4]),
        .zombie_x(z4_x), .zombie_z(z4_z), .zombie_alive(z4_alive), .zombie_hp(z4_hp),
        .attack_active(z4_attacking),
        .melee_attempt_pulse(z4_melee), .damage_pulse(z4_hit), .death_pulse(z4_dead));

    zombie_agent_round zagent5 (
        .clk_100mhz(clk_100mhz),
        .reset(reset),
        .soft_reset(game_reset_pulse),
        .frame_tick(game_frame_tick),
        .spawn_pulse(sp5), .spawn_x(round_spawn_x), .spawn_z(round_spawn_z),
        .spawn_exit_x(round_spawn_exit_x), .spawn_exit_z(round_spawn_exit_z),
        .player_x(camera_x), .player_z(camera_z), .player_alive(player_hp != 0),
        .door_ul_open(door_ul_open), .door_ur_open(door_ur_open),
        .door_ll_open(door_ll_open), .door_lr_open(door_lr_open),
        .spawn_hp(shared_zombie_spawn_hp),
        .movement_enable(zombie_normal_move_enable),
        .shot_damage(weapon_damage),
        .debug_shot_pulse(aimed_shot_onehot[5]),
        .zombie_x(z5_x), .zombie_z(z5_z), .zombie_alive(z5_alive), .zombie_hp(z5_hp),
        .attack_active(z5_attacking),
        .melee_attempt_pulse(z5_melee), .damage_pulse(z5_hit), .death_pulse(z5_dead));

    zombie_agent_round zagent6 (
        .clk_100mhz(clk_100mhz),
        .reset(reset),
        .soft_reset(game_reset_pulse),
        .frame_tick(game_frame_tick),
        .spawn_pulse(sp6), .spawn_x(round_spawn_x), .spawn_z(round_spawn_z),
        .spawn_exit_x(round_spawn_exit_x), .spawn_exit_z(round_spawn_exit_z),
        .player_x(camera_x), .player_z(camera_z), .player_alive(player_hp != 0),
        .door_ul_open(door_ul_open), .door_ur_open(door_ur_open),
        .door_ll_open(door_ll_open), .door_lr_open(door_lr_open),
        .spawn_hp(shared_zombie_spawn_hp),
        .movement_enable(zombie_normal_move_enable),
        .shot_damage(weapon_damage),
        .debug_shot_pulse(aimed_shot_onehot[6]),
        .zombie_x(z6_x), .zombie_z(z6_z), .zombie_alive(z6_alive), .zombie_hp(z6_hp),
        .attack_active(z6_attacking),
        .melee_attempt_pulse(z6_melee), .damage_pulse(z6_hit), .death_pulse(z6_dead));

    zombie_agent_round zagent7 (
        .clk_100mhz(clk_100mhz),
        .reset(reset),
        .soft_reset(game_reset_pulse),
        .frame_tick(game_frame_tick),
        .spawn_pulse(sp7), .spawn_x(round_spawn_x), .spawn_z(round_spawn_z),
        .spawn_exit_x(round_spawn_exit_x), .spawn_exit_z(round_spawn_exit_z),
        .player_x(camera_x), .player_z(camera_z), .player_alive(player_hp != 0),
        .door_ul_open(door_ul_open), .door_ur_open(door_ur_open),
        .door_ll_open(door_ll_open), .door_lr_open(door_lr_open),
        .spawn_hp(shared_zombie_spawn_hp),
        .movement_enable(zombie_normal_move_enable),
        .shot_damage(weapon_damage),
        .debug_shot_pulse(aimed_shot_onehot[7]),
        .zombie_x(z7_x), .zombie_z(z7_z), .zombie_alive(z7_alive), .zombie_hp(z7_hp),
        .attack_active(z7_attacking),
        .melee_attempt_pulse(z7_melee), .damage_pulse(z7_hit), .death_pulse(z7_dead));

    wire any_zombie_hit = z0_hit || z1_hit || z2_hit || z3_hit ||
                          z4_hit || z5_hit || z6_hit || z7_hit;

    assign zombie_hit_reward_pulse = any_zombie_hit;

    // ------------------------------------------------------------------------
    // FPGA -> Python sound event channel.
    // ------------------------------------------------------------------------
    sound_event_sender sound_event_inst (
        .clk_100mhz   (clk_100mhz),
        .reset        (reset),
        .pistol_shot_pulse (pistol_fire_pulse),
        .shotgun_shot_pulse(shotgun_fire_pulse),
        .rifle_shot_pulse  (rifle_fire_pulse),
        .hit_pulse         (any_zombie_hit),
        .appear_pulse      (round_spawn_pulse),
        .round_change_pulse(round_change_sound_pulse),

        .music_cmd_valid   (music_cmd_valid),
        .music_cmd_code    (music_cmd_code),

        .RsTx              (RsTx)
    );

    // ------------------------------------------------------------------------
    // Room renderer.
    // ------------------------------------------------------------------------
    wire [11:0] raw_rgb;

    aimlab_renderer renderer_inst (
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .camera_x(camera_x), .camera_y(camera_y), .camera_z(camera_z),
        .camera_yaw(camera_yaw), .camera_pitch(camera_pitch),
        .map_wall_depth(map_wall_depth), .map_wall_valid(map_wall_valid),
        .host_alive(host_alive), .raw_rgb(raw_rgb)
    );

    // Seven-segment debug keeps player HP on the right. Left shows HP of the
    // first live zombie slot (0 when no zombies are active).
    wire [6:0] debug_live_zombie_hp_full =
        z0_alive ? z0_hp : z1_alive ? z1_hp : z2_alive ? z2_hp : z3_alive ? z3_hp :
        z4_alive ? z4_hp : z5_alive ? z5_hp : z6_alive ? z6_hp : z7_alive ? z7_hp : 7'd0;

    wire [3:0] debug_live_zombie_hp =
        (debug_live_zombie_hp_full > 7'd9)
        ? 4'd9
        : debug_live_zombie_hp_full[3:0];

    hp_debug_display hp_display_inst (
        .clk_100mhz(clk_100mhz), .reset(reset),
        .zombie_hp(debug_live_zombie_hp), .player_hp(player_hp),
        .seg(seg), .an(an), .dp(dp)
    );

    // ------------------------------------------------------------------------
    // REGISTERED multi-zombie projection.
    //
    // V22D uses a single shared sequential projector with smooth perspective
    // scaling. V22H permits these REGISTERED outputs to feed only the separate
    // staged aim-hit selector below. There is still no direct combinational
    // projection -> zombie HP/AI feedback path.
    // ------------------------------------------------------------------------
    wire signed [11:0] zsx0,zsy0,zsx1,zsy1,zsx2,zsy2,zsx3,zsy3;
    wire signed [11:0] zsx4,zsy4,zsx5,zsy5,zsx6,zsy6,zsx7,zsy7;
    wire [7:0] zsr0,zsr1,zsr2,zsr3,zsr4,zsr5,zsr6,zsr7;
    wire zsv0,zsv1,zsv2,zsv3,zsv4,zsv5,zsv6,zsv7;

    // V22F display-only camera-space forward depth.
    // Used ONLY to hide zombie pixels behind nearer map walls.
    wire [15:0] zdepth0,zdepth1,zdepth2,zdepth3;
    wire [15:0] zdepth4,zdepth5,zdepth6,zdepth7;

    // V22D: one shared sequential smooth projector for all 8 zombies.
    //
    // V22/V22C used eight power-of-two bucket projectors. World movement was
    // already ~60 Hz, but those large perspective buckets made an approaching
    // zombie LOOK like it teleported every time depth crossed a bucket.
    //
    // This bank keeps display completely isolated from gameplay state, but
    // computes a smooth piecewise-linear perspective scale and time-multiplexes
    // one DSP datapath across all 8 zombies. All 8 projections complete in
    // far less than one VGA frame.
    zombie_projection_bank_smooth zombie_projection_bank_inst (
        .clk_100mhz(clk_100mhz),
        .reset(reset),
        .frame_tick(frame_tick),

        .camera_x(camera_x),
        .camera_y(camera_y),
        .camera_z(camera_z),
        .camera_yaw(camera_yaw),
        .camera_pitch(camera_pitch),

        .z0_x(z0_x), .z0_z(z0_z),
        .z1_x(z1_x), .z1_z(z1_z),
        .z2_x(z2_x), .z2_z(z2_z),
        .z3_x(z3_x), .z3_z(z3_z),
        .z4_x(z4_x), .z4_z(z4_z),
        .z5_x(z5_x), .z5_z(z5_z),
        .z6_x(z6_x), .z6_z(z6_z),
        .z7_x(z7_x), .z7_z(z7_z),

        .z0_screen_x(zsx0), .z0_screen_y(zsy0), .z0_radius(zsr0), .z0_visible(zsv0), .z0_depth(zdepth0),
        .z1_screen_x(zsx1), .z1_screen_y(zsy1), .z1_radius(zsr1), .z1_visible(zsv1), .z1_depth(zdepth1),
        .z2_screen_x(zsx2), .z2_screen_y(zsy2), .z2_radius(zsr2), .z2_visible(zsv2), .z2_depth(zdepth2),
        .z3_screen_x(zsx3), .z3_screen_y(zsy3), .z3_radius(zsr3), .z3_visible(zsv3), .z3_depth(zdepth3),
        .z4_screen_x(zsx4), .z4_screen_y(zsy4), .z4_radius(zsr4), .z4_visible(zsv4), .z4_depth(zdepth4),
        .z5_screen_x(zsx5), .z5_screen_y(zsy5), .z5_radius(zsr5), .z5_visible(zsv5), .z5_depth(zdepth5),
        .z6_screen_x(zsx6), .z6_screen_y(zsy6), .z6_radius(zsr6), .z6_visible(zsv6), .z6_depth(zdepth6),
        .z7_screen_x(zsx7), .z7_screen_y(zsy7), .z7_radius(zsr7), .z7_visible(zsv7), .z7_depth(zdepth7)
    );

    // ------------------------------------------------------------------------
    // V22H CROSSHAIR WALL DEPTH SNAPSHOT
    //
    // map_wall_depth follows the current VGA column. Remember the depth for
    // center column X=320 so the weapon hit-test can reject a zombie behind
    // a nearer wall even though a mouse click can arrive at any raster time.
    // ------------------------------------------------------------------------
    reg [15:0] crosshair_wall_depth;
    reg        crosshair_wall_valid;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            crosshair_wall_depth <= 16'hFFFF;
            crosshair_wall_valid <= 1'b0;
        end
        else if (active_video && (pixel_x == 10'd320)) begin
            crosshair_wall_depth <= map_wall_depth;
            crosshair_wall_valid <= map_wall_valid;
        end
    end

    // ------------------------------------------------------------------------
    // SEQUENTIAL AIMED PISTOL HIT TEST
    //
    // - crosshair point = (320,240)
    // - tests the same pill silhouette used by zombie_pill_pixel
    // - checks only alive + projected-visible zombies
    // - rejects zombies behind the center-column wall depth
    // - if targets overlap, nearest depth wins
    // - output is a one-clock one-hot pulse AFTER the staged scan
    //
    // This takes only ~18 clocks at 100 MHz and avoids the old huge
    // projection->game-state combinational timing path.
    // ------------------------------------------------------------------------
    zombie_aim_hit_selector_seq aimed_hit_selector_inst (
        .clk_100mhz(clk_100mhz),
        .reset(gameplay_reset),
        .shot_pulse(weapon_fire_pulse),

        .wall_valid(crosshair_wall_valid),
        .wall_depth(crosshair_wall_depth),

        .alive_mask(zombie_alive_mask),

        .z0_x(zsx0), .z0_y(zsy0), .z0_radius(zsr0), .z0_visible(zsv0), .z0_depth(zdepth0),
        .z1_x(zsx1), .z1_y(zsy1), .z1_radius(zsr1), .z1_visible(zsv1), .z1_depth(zdepth1),
        .z2_x(zsx2), .z2_y(zsy2), .z2_radius(zsr2), .z2_visible(zsv2), .z2_depth(zdepth2),
        .z3_x(zsx3), .z3_y(zsy3), .z3_radius(zsr3), .z3_visible(zsv3), .z3_depth(zdepth3),
        .z4_x(zsx4), .z4_y(zsy4), .z4_radius(zsr4), .z4_visible(zsv4), .z4_depth(zdepth4),
        .z5_x(zsx5), .z5_y(zsy5), .z5_radius(zsr5), .z5_visible(zsv5), .z5_depth(zdepth5),
        .z6_x(zsx6), .z6_y(zsy6), .z6_radius(zsr6), .z6_visible(zsv6), .z6_depth(zdepth6),
        .z7_x(zsx7), .z7_y(zsy7), .z7_radius(zsr7), .z7_visible(zsv7), .z7_depth(zdepth7),

        .hit_onehot(aimed_shot_onehot)
    );

    wire zpix0,zpix1,zpix2,zpix3,zpix4,zpix5,zpix6,zpix7;
    zombie_pill_pixel zpp0(.pixel_x(pixel_x),.pixel_y(pixel_y),.screen_x(zsx0),.screen_y(zsy0),.radius(zsr0),.visible(zsv0 && z0_alive),.pixel_on(zpix0));
    zombie_pill_pixel zpp1(.pixel_x(pixel_x),.pixel_y(pixel_y),.screen_x(zsx1),.screen_y(zsy1),.radius(zsr1),.visible(zsv1 && z1_alive),.pixel_on(zpix1));
    zombie_pill_pixel zpp2(.pixel_x(pixel_x),.pixel_y(pixel_y),.screen_x(zsx2),.screen_y(zsy2),.radius(zsr2),.visible(zsv2 && z2_alive),.pixel_on(zpix2));
    zombie_pill_pixel zpp3(.pixel_x(pixel_x),.pixel_y(pixel_y),.screen_x(zsx3),.screen_y(zsy3),.radius(zsr3),.visible(zsv3 && z3_alive),.pixel_on(zpix3));
    zombie_pill_pixel zpp4(.pixel_x(pixel_x),.pixel_y(pixel_y),.screen_x(zsx4),.screen_y(zsy4),.radius(zsr4),.visible(zsv4 && z4_alive),.pixel_on(zpix4));
    zombie_pill_pixel zpp5(.pixel_x(pixel_x),.pixel_y(pixel_y),.screen_x(zsx5),.screen_y(zsy5),.radius(zsr5),.visible(zsv5 && z5_alive),.pixel_on(zpix5));
    zombie_pill_pixel zpp6(.pixel_x(pixel_x),.pixel_y(pixel_y),.screen_x(zsx6),.screen_y(zsy6),.radius(zsr6),.visible(zsv6 && z6_alive),.pixel_on(zpix6));
    zombie_pill_pixel zpp7(.pixel_x(pixel_x),.pixel_y(pixel_y),.screen_x(zsx7),.screen_y(zsy7),.radius(zsr7),.visible(zsv7 && z7_alive),.pixel_on(zpix7));

    // ------------------------------------------------------------------------
    // V22F WALL OCCLUSION
    //
    // map_wall_depth is the nearest corrected red-wall/door depth for the
    // CURRENT VGA COLUMN. Each zombie now also carries its corrected
    // camera-space depth from the smooth projector.
    //
    // If the wall is closer than the zombie, that zombie pixel is suppressed.
    // Because the comparison happens per VGA column, a zombie can naturally
    // become partially visible around a doorway/corner rather than popping
    // all at once.
    //
    // Small tolerance prevents edge flicker when a zombie is essentially on
    // the same plane as a wall opening.
    // ------------------------------------------------------------------------
    wire [16:0] wall_depth_with_zombie_tolerance =
        {1'b0, map_wall_depth} + 17'd4;

    wire z0_not_behind_wall =
        !map_wall_valid ||
        ({1'b0,zdepth0} <= wall_depth_with_zombie_tolerance);
    wire z1_not_behind_wall =
        !map_wall_valid ||
        ({1'b0,zdepth1} <= wall_depth_with_zombie_tolerance);
    wire z2_not_behind_wall =
        !map_wall_valid ||
        ({1'b0,zdepth2} <= wall_depth_with_zombie_tolerance);
    wire z3_not_behind_wall =
        !map_wall_valid ||
        ({1'b0,zdepth3} <= wall_depth_with_zombie_tolerance);
    wire z4_not_behind_wall =
        !map_wall_valid ||
        ({1'b0,zdepth4} <= wall_depth_with_zombie_tolerance);
    wire z5_not_behind_wall =
        !map_wall_valid ||
        ({1'b0,zdepth5} <= wall_depth_with_zombie_tolerance);
    wire z6_not_behind_wall =
        !map_wall_valid ||
        ({1'b0,zdepth6} <= wall_depth_with_zombie_tolerance);
    wire z7_not_behind_wall =
        !map_wall_valid ||
        ({1'b0,zdepth7} <= wall_depth_with_zombie_tolerance);

    wire zombie_overlay_pixel =
        (zpix0 && z0_not_behind_wall) ||
        (zpix1 && z1_not_behind_wall) ||
        (zpix2 && z2_not_behind_wall) ||
        (zpix3 && z3_not_behind_wall) ||
        (zpix4 && z4_not_behind_wall) ||
        (zpix5 && z5_not_behind_wall) ||
        (zpix6 && z6_not_behind_wall) ||
        (zpix7 && z7_not_behind_wall);

    // V24D: yellow has priority only for an attacking zombie's visible pixels.
    // Wall occlusion is preserved exactly like the normal aqua overlay.
    wire zombie_attack_overlay_pixel =
        (zpix0 && z0_not_behind_wall && z0_attacking) ||
        (zpix1 && z1_not_behind_wall && z1_attacking) ||
        (zpix2 && z2_not_behind_wall && z2_attacking) ||
        (zpix3 && z3_not_behind_wall && z3_attacking) ||
        (zpix4 && z4_not_behind_wall && z4_attacking) ||
        (zpix5 && z5_not_behind_wall && z5_attacking) ||
        (zpix6 && z6_not_behind_wall && z6_attacking) ||
        (zpix7 && z7_not_behind_wall && z7_attacking);

    // Keep the crosshair above zombies.
    wire final_crosshair_pixel =
        (pixel_x >= 10'd319) && (pixel_x <= 10'd320) &&
        (pixel_y >= 10'd239) && (pixel_y <= 10'd240);

    // Money HUD upper-left.
    wire money_hud_pixel;
    money_hud_overlay money_hud_inst (
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .digit_thousands(money_thousands), .digit_hundreds(money_hundreds),
        .digit_tens(money_tens), .digit_ones(money_ones),
        .money_pixel(money_hud_pixel)
    );

    // V22E player HP HUD directly beside the money counter.
    wire player_hp_hud_pixel;
    player_hp_hud_overlay player_hp_hud_inst (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .player_hp(player_hp),
        .hp_pixel(player_hp_hud_pixel)
    );

    // V26B selected POWER UP icons packed directly beside HP.
    //
    // Icon shapes:
    //   move speed  = shoes
    //   zombie slow = downward arrow
    //   +1 HP       = heart
    //   fast reload = magazine
    wire       perk_icon_pixel;
    wire [1:0] perk_icon_kind;

    powerup_perk_icon_overlay perk_icon_inst (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .perk_move_speed(perk_move_speed),
        .perk_zombie_slow(perk_zombie_slow),
        .perk_extra_hp(perk_extra_hp),
        .perk_fast_reload(perk_fast_reload),
        .icon_pixel(perk_icon_pixel),
        .icon_kind(perk_icon_kind)
    );

    // V23 equipped-weapon icon. Pistol / shotgun / rifle on lower-right.
    wire weapon_icon_pixel;
    weapon_icon_overlay weapon_icon_inst (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .equipped_weapon(equipped_weapon),
        .weapon_pixel(weapon_icon_pixel)
    );

    // V26B reserve-ammo BCD conversion.
    //
    // This is intentionally sequential rather than a large combinational
    // binary-to-decimal network. It completes in only a few 100 MHz clocks
    // whenever reserve ammo changes.
    wire [3:0] reserve_hundreds;
    wire [3:0] reserve_tens;
    wire [3:0] reserve_ones;

    ammo_reserve_bcd_converter reserve_bcd_inst (
        .clk_100mhz(clk_100mhz),
        .reset(gameplay_reset),
        .value_in(weapon_reserve),
        .hundreds(reserve_hundreds),
        .tens(reserve_tens),
        .ones(reserve_ones)
    );

    // Magazine / reserve ammo HUD above the weapon icon.
    // Examples:
    //   pistol  20 / infinity
    //   shotgun 10 / 080
    //   rifle   30 / 300
    wire ammo_hud_pixel;
    weapon_ammo_hud_overlay ammo_hud_inst (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .ammo_count(weapon_ammo),
        .reserve_unlimited(weapon_reserve_unlimited),
        .reserve_hundreds(reserve_hundreds),
        .reserve_tens(reserve_tens),
        .reserve_ones(reserve_ones),
        .ammo_pixel(ammo_hud_pixel)
    );

    // Numeric reload countdown directly under the crosshair.
    // Examples: 1.2, 2.0, 1.8 ... 0.1
    wire reload_hud_pixel;
    reload_timer_overlay reload_hud_inst (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .reload_active(weapon_reloading),
        .tenths_remaining(reload_tenths_remaining),
        .reload_pixel(reload_hud_pixel)
    );

    // Round HUD upper-right: R01 .. R99.
    wire round_hud_pixel;
    round_hud_overlay round_hud_inst (
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .round_value(current_round),
        .round_pixel(round_hud_pixel)
    );

    // ------------------------------------------------------------------------
    // V21 low blue spawn-block overlay.
    //
    // Each spawn room is a 3x3-grid (192x192) block, 64 world units high.
    // The raycaster supplies only the nearest spawn-block SIDE depth.
    // This display-only overlay converts that depth into Y=0..64 coverage.
    // It never feeds game state.
    // ------------------------------------------------------------------------
    wire spawn_room_floor_pixel;
    wire spawn_room_wall_pixel;
    wire spawn_room_roof_pixel;
    wire spawn_room_entry_wall_pixel;

    spawn_raised_room_overlay spawn_raised_room_overlay_inst (
        .pixel_y(pixel_y),

        .camera_y(camera_y),
        .camera_pitch(camera_pitch),

        .spawn_depth(spawn_block_depth),
        .spawn_valid(spawn_block_valid),

        .spawn_far_depth(spawn_block_far_depth),
        .spawn_far_valid(spawn_block_far_valid),

        // Separate missing fourth-wall surface.
        .entry_wall_depth(spawn_entry_wall_depth),
        .entry_wall_valid(spawn_entry_wall_valid),

        .map_wall_depth(map_wall_depth),
        .map_wall_valid(map_wall_valid),

        .room_floor_pixel(spawn_room_floor_pixel),
        .room_wall_pixel(spawn_room_wall_pixel),
        .room_roof_pixel(spawn_room_roof_pixel),
        .room_entry_wall_pixel(spawn_room_entry_wall_pixel)
    );

    // The raycaster marks the winning cached full-height surface type.
    wire brown_door_pixel =
        map_wall_valid && map_wall_is_door && (raw_rgb == 12'hF00);

    // V25C fast station identity from the registered raycaster subtype.
    // These signals do NOT depend on raw_rgb / renderer arithmetic.
    wire shotgun_buy_column =
        map_wall_valid && map_wall_is_shotgun_buy;
    wire rifle_buy_column =
        map_wall_valid && map_wall_is_rifle_buy;
    wire power_station_column =
        map_wall_valid && map_wall_is_power_station;
    wire ultimate_station_column =
        map_wall_valid && map_wall_is_ultimate_station;
    wire powerup_station_column =
        map_wall_valid && map_wall_is_powerup_station;
    wire luckybox_station_column =
        map_wall_valid && map_wall_is_luckybox_station;

    // Actual visible pink pixels remain renderer-clipped.
    wire shotgun_buy_wall_pixel =
        shotgun_buy_column && (raw_rgb == 12'hF00);

    wire rifle_buy_wall_pixel =
        rifle_buy_column && (raw_rgb == 12'hF00);

    // V24 visual-only station surfaces.
    wire power_station_wall_pixel =
        power_station_column && (raw_rgb == 12'hF00);

    wire ultimate_station_wall_pixel =
        ultimate_station_column && (raw_rgb == 12'hF00);

    wire powerup_station_wall_pixel =
        powerup_station_column && (raw_rgb == 12'hF00);

    wire luckybox_station_wall_pixel =
        luckybox_station_column && (raw_rgb == 12'hF00);

    // V24B: ONE shared renderer for all six pink wall labels.
    // This removes the duplicate V24 font/placement datapath.
    wire station_label_pixel;
    shared_station_label_overlay station_label_inst (
        .clk_100mhz(clk_100mhz),
        .reset(reset),
        .frame_tick(frame_tick),
        .pixel_tick(pixel_tick),
        .active_video(active_video),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .camera_pitch(camera_pitch),

        .shotgun_column(shotgun_buy_column),
        .rifle_column(rifle_buy_column),
        .power_column(power_station_column),
        .ultimate_column(ultimate_station_column),
        .powerup_column(powerup_station_column),
        .luckybox_column(luckybox_station_column),

        .shotgun_surface_pixel(shotgun_buy_wall_pixel),
        .rifle_surface_pixel(rifle_buy_wall_pixel),
        .power_surface_pixel(power_station_wall_pixel),
        .ultimate_surface_pixel(ultimate_station_wall_pixel),
        .powerup_surface_pixel(powerup_station_wall_pixel),
        .luckybox_surface_pixel(luckybox_station_wall_pixel),

        .label_pixel(station_label_pixel)
    );

    // ------------------------------------------------------------------------
    // V22G START / DEATH SCREEN
    //
    // These states deliberately replace the 3D scene with black. The text
    // renderer is display-only and has no feedback path into gameplay.
    // ------------------------------------------------------------------------
    wire game_flow_text_pixel;
    wire game_flow_red_pixel;

    game_flow_overlay game_flow_overlay_inst (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .show_start(game_is_waiting),
        .show_dead(game_is_dead),
        .text_pixel(game_flow_text_pixel),
        .red_pixel(game_flow_red_pixel)
    );

    // Center-screen PAUSE text. Display-only; no path back into game state.
    wire pause_word_pixel;
    pause_word_overlay pause_word_inst (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .pause_active(pause_active && game_is_playing),
        .pause_pixel(pause_word_pixel)
    );

    // ------------------------------------------------------------------------
    // V23C FINAL VGA PRIORITY MUX
    //
    // Replaces the deeply nested ternary expression from V23B. The visual
    // priority is unchanged, but this form is much safer to edit and avoids
    // parenthesis/syntax mistakes.
    // ------------------------------------------------------------------------
    reg [11:0] final_rgb_mux;

    always @(*) begin
        final_rgb_mux = 12'h000;

        if (!game_is_playing) begin
            if (game_flow_text_pixel) begin
                if (game_flow_red_pixel)
                    final_rgb_mux = 12'hF22;
                else
                    final_rgb_mux = 12'hFFF;
            end
            else begin
                final_rgb_mux = 12'h000;
            end
        end
        else if (pause_word_pixel) begin
            final_rgb_mux = 12'hFFF;
        end
        else if (reload_hud_pixel) begin
            final_rgb_mux = 12'hFC0;
        end
        else if (money_hud_pixel) begin
            final_rgb_mux = 12'hFF0;
        end
        else if (player_hp_hud_pixel) begin
            final_rgb_mux = 12'hF44;
        end
        else if (perk_icon_pixel) begin
            // Distinct colors make the two selected perks readable at a glance.
            case (perk_icon_kind)
                2'd1: final_rgb_mux = 12'h4DF; // shoes / move speed
                2'd2: final_rgb_mux = 12'hFD4; // down arrow / zombie slow
                2'd3: final_rgb_mux = 12'hF45; // heart / +1 HP
                default: final_rgb_mux = 12'hDFD; // magazine / fast reload
            endcase
        end
        else if (round_hud_pixel) begin
            final_rgb_mux = 12'hF80;
        end
        else if (ammo_hud_pixel) begin
            final_rgb_mux = 12'hFFF;
        end
        else if (weapon_icon_pixel) begin
            // V26 Ultimate-upgraded equipped weapon.
            if (equipped_weapon_ultimate)
                final_rgb_mux = 12'hA0F;
            else
                final_rgb_mux = 12'hDDD;
        end
        else if (final_crosshair_pixel) begin
            final_rgb_mux = 12'hFFF;
        end
        else if (zombie_attack_overlay_pixel) begin
            // V24D melee warning color.
            final_rgb_mux = 12'hFF0;
        end
        else if (zombie_overlay_pixel) begin
            // Normal zombie color.
            final_rgb_mux = 12'h0FF;
        end
        else if (spawn_room_roof_pixel) begin
            final_rgb_mux = 12'h5CF;
        end
        else if (spawn_room_floor_pixel) begin
            final_rgb_mux = 12'h39F;
        end
        else if (spawn_room_wall_pixel ||
                 spawn_room_entry_wall_pixel) begin
            final_rgb_mux = 12'h06F;
        end
        else if (station_label_pixel) begin
            final_rgb_mux = 12'hFFF;
        end
        else if (shotgun_buy_wall_pixel ||
                 rifle_buy_wall_pixel ||
                 power_station_wall_pixel ||
                 ultimate_station_wall_pixel ||
                 powerup_station_wall_pixel ||
                 luckybox_station_wall_pixel) begin
            final_rgb_mux = 12'hF4A;
        end
        else if (brown_door_pixel) begin
            final_rgb_mux = 12'hA52;
        end
        else begin
            final_rgb_mux = raw_rgb;
        end
    end

    assign vga_rgb = active_video ? final_rgb_mux : 12'h000;

endmodule




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


// ============================================================================
// V20 MONEY + LOCKED-ROOM CONTROLLER
//
// P held: +10 money once per frame (~600/s at 60 Hz), capped at 9999.
// E rising edge: purchase one nearby locked room for 1000.
//
// The four doors correspond to the four corner side rooms.
// ============================================================================
module zombies_economy_doors (
    input  wire               clk_100mhz,
    input  wire               reset,
    input  wire               frame_tick,

    input  wire               key_p,
    input  wire               key_e,
    input  wire               key_1,
    input  wire               key_2,
    input  wire               key_3,
    input  wire               key_4,

    input  wire               wheel_up_pulse,
    input  wire               wheel_down_pulse,

    input  wire               hit_reward_pulse,
    input  wire [5:0]         hit_reward_amount,

    input  wire signed [15:0] player_x,
    input  wire signed [15:0] player_z,

    output reg  [13:0]        money_value,
    output reg  [3:0]         money_thousands,
    output reg  [3:0]         money_hundreds,
    output reg  [3:0]         money_tens,
    output reg  [3:0]         money_ones,

    output reg                door_ul_open,
    output reg                door_ur_open,
    output reg                door_ll_open,
    output reg                door_lr_open,

    output reg  [1:0]         equipped_weapon,
    output reg                shotgun_owned,
    output reg                rifle_owned,
    output wire               near_shotgun_buy,
    output wire               near_rifle_buy,

    output reg                power_on,

    output reg                perk_move_speed,
    output reg                perk_zombie_slow,
    output reg                perk_extra_hp,
    output reg                perk_fast_reload,

    output reg                pistol_ultimate,
    output reg                shotgun_ultimate,
    output reg                rifle_ultimate,

    output reg                ammo_refill_pulse,
    output reg  [1:0]         ammo_refill_weapon,

    output reg                ultimate_upgrade_pulse,
    output reg  [1:0]         ultimate_upgrade_weapon
);

    localparam [13:0] DOOR_PRICE      = 14'd1000;
    localparam [13:0] SHOTGUN_PRICE   = 14'd500;
    localparam [13:0] RIFLE_PRICE     = 14'd1000;
    localparam [13:0] POWER_PRICE     = 14'd1000;
    localparam [13:0] PERK_PRICE      = 14'd1000;
    localparam [13:0] ULTIMATE_PRICE  = 14'd1500;
    localparam [13:0] MONEY_MAX       = 14'd9999;

    localparam [1:0]
        WEAPON_PISTOL  = 2'd0,
        WEAPON_SHOTGUN = 2'd1,
        WEAPON_RIFLE   = 2'd2;

    reg key_e_d;
    reg key_1_d, key_2_d, key_3_d, key_4_d;
    reg [1:0] perk_count;

    wire buy_press = key_e && !key_e_d;
    wire perk1_press = key_1 && !key_1_d;
    wire perk2_press = key_2 && !key_2_d;
    wire perk3_press = key_3 && !key_3_d;
    wire perk4_press = key_4 && !key_4_d;
    wire any_perk_press = perk1_press || perk2_press ||
                          perk3_press || perk4_press;

    // Existing room-door purchase zones.
    wire near_ul =
        (((player_z >= 16'sd540) && (player_z <= 16'sd620)) &&
         (player_x >= -16'sd620) && (player_x <= -16'sd300)) ||
        (((player_x >= -16'sd620) && (player_x <= -16'sd540)) &&
         (player_z >= 16'sd300) && (player_z <= 16'sd620));

    wire near_ur =
        (((player_z >= 16'sd540) && (player_z <= 16'sd620)) &&
         (player_x >= 16'sd300) && (player_x <= 16'sd620)) ||
        (((player_x >= 16'sd540) && (player_x <= 16'sd620)) &&
         (player_z >= 16'sd300) && (player_z <= 16'sd620));

    wire near_ll =
        (((player_z <= -16'sd540) && (player_z >= -16'sd620)) &&
         (player_x >= -16'sd620) && (player_x <= -16'sd300)) ||
        (((player_x >= -16'sd620) && (player_x <= -16'sd540)) &&
         (player_z >= -16'sd620) && (player_z <= -16'sd300));

    wire near_lr =
        (((player_z <= -16'sd540) && (player_z >= -16'sd620)) &&
         (player_x >= 16'sd300) && (player_x <= 16'sd620)) ||
        (((player_x >= 16'sd540) && (player_x <= 16'sd620)) &&
         (player_z >= -16'sd620) && (player_z <= -16'sd300));

    // Weapon walls.
    assign near_shotgun_buy =
        (player_z >= 16'sd540) && (player_z <= 16'sd620) &&
        (player_x >= -16'sd128) && (player_x <= 16'sd128);

    assign near_rifle_buy =
        (player_x >= 16'sd860) && (player_x <= 16'sd940) &&
        (player_z >= -16'sd736) && (player_z <= -16'sd544);

    // V26 machine interaction volumes.
    //
    // POWER: LL outside-left wall x=-960, z=-736..-544.
    wire near_power_machine =
        (player_x >= -16'sd940) && (player_x <= -16'sd850) &&
        (player_z >= -16'sd768) && (player_z <= -16'sd512);

    // ULTIMATE: UL top wall z=1216, x=-864..-672.
    wire near_ultimate_machine =
        (player_z >= 16'sd1090) && (player_z <= 16'sd1196) &&
        (player_x >= -16'sd900) && (player_x <= -16'sd636);

    // POWER UP: UR top wall z=1088, x=608..800.
    wire near_powerup_machine =
        (player_z >= 16'sd970) && (player_z <= 16'sd1068) &&
        (player_x >= 16'sd570) && (player_x <= 16'sd838);

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            key_e_d <= 1'b0;
            key_1_d <= 1'b0;
            key_2_d <= 1'b0;
            key_3_d <= 1'b0;
            key_4_d <= 1'b0;

            money_value     <= 14'd0;
            money_thousands <= 4'd0;
            money_hundreds  <= 4'd0;
            money_tens      <= 4'd0;
            money_ones      <= 4'd0;

            door_ul_open <= 1'b0;
            door_ur_open <= 1'b0;
            door_ll_open <= 1'b0;
            door_lr_open <= 1'b0;

            shotgun_owned <= 1'b0;
            rifle_owned <= 1'b0;
            equipped_weapon <= WEAPON_PISTOL;

            power_on <= 1'b0;

            perk_move_speed <= 1'b0;
            perk_zombie_slow <= 1'b0;
            perk_extra_hp <= 1'b0;
            perk_fast_reload <= 1'b0;
            perk_count <= 2'd0;

            pistol_ultimate <= 1'b0;
            shotgun_ultimate <= 1'b0;
            rifle_ultimate <= 1'b0;

            ammo_refill_pulse <= 1'b0;
            ammo_refill_weapon <= WEAPON_PISTOL;

            ultimate_upgrade_pulse <= 1'b0;
            ultimate_upgrade_weapon <= WEAPON_PISTOL;
        end
        else begin
            key_e_d <= key_e;
            key_1_d <= key_1;
            key_2_d <= key_2;
            key_3_d <= key_3;
            key_4_d <= key_4;

            ammo_refill_pulse <= 1'b0;
            ultimate_upgrade_pulse <= 1'b0;

            // ------------------------------------------------------------
            // Mouse wheel weapon switching through owned weapons.
            // ------------------------------------------------------------
            if (wheel_down_pulse) begin
                case (equipped_weapon)
                    WEAPON_PISTOL: begin
                        if (shotgun_owned)
                            equipped_weapon <= WEAPON_SHOTGUN;
                        else if (rifle_owned)
                            equipped_weapon <= WEAPON_RIFLE;
                    end
                    WEAPON_SHOTGUN: begin
                        if (rifle_owned)
                            equipped_weapon <= WEAPON_RIFLE;
                        else
                            equipped_weapon <= WEAPON_PISTOL;
                    end
                    default:
                        equipped_weapon <= WEAPON_PISTOL;
                endcase
            end
            else if (wheel_up_pulse) begin
                case (equipped_weapon)
                    WEAPON_PISTOL: begin
                        if (rifle_owned)
                            equipped_weapon <= WEAPON_RIFLE;
                        else if (shotgun_owned)
                            equipped_weapon <= WEAPON_SHOTGUN;
                    end
                    WEAPON_SHOTGUN:
                        equipped_weapon <= WEAPON_PISTOL;
                    default: begin
                        if (shotgun_owned)
                            equipped_weapon <= WEAPON_SHOTGUN;
                        else
                            equipped_weapon <= WEAPON_PISTOL;
                    end
                endcase
            end

            // ------------------------------------------------------------
            // E interactions.
            // ------------------------------------------------------------
            if (buy_press) begin
                // Shotgun wall:
                // - first E buys for 500
                // - later E re-equips + refills reserve ammo free
                if (near_shotgun_buy) begin
                    if (shotgun_owned) begin
                        equipped_weapon <= WEAPON_SHOTGUN;
                        ammo_refill_pulse <= 1'b1;
                        ammo_refill_weapon <= WEAPON_SHOTGUN;
                    end
                    else if (money_value >= SHOTGUN_PRICE) begin
                        shotgun_owned <= 1'b1;
                        equipped_weapon <= WEAPON_SHOTGUN;
                        ammo_refill_pulse <= 1'b1;
                        ammo_refill_weapon <= WEAPON_SHOTGUN;

                        money_value <= money_value - SHOTGUN_PRICE;

                        if (money_hundreds >= 4'd5)
                            money_hundreds <= money_hundreds - 4'd5;
                        else begin
                            money_thousands <= money_thousands - 4'd1;
                            money_hundreds <= money_hundreds + 4'd5;
                        end
                    end
                end

                // Rifle wall:
                // - first E buys for 1000
                // - later E re-equips + refills reserve ammo free
                else if (near_rifle_buy) begin
                    if (rifle_owned) begin
                        equipped_weapon <= WEAPON_RIFLE;
                        ammo_refill_pulse <= 1'b1;
                        ammo_refill_weapon <= WEAPON_RIFLE;
                    end
                    else if (money_value >= RIFLE_PRICE) begin
                        rifle_owned <= 1'b1;
                        equipped_weapon <= WEAPON_RIFLE;
                        ammo_refill_pulse <= 1'b1;
                        ammo_refill_weapon <= WEAPON_RIFLE;

                        money_value <= money_value - RIFLE_PRICE;
                        money_thousands <= money_thousands - 4'd1;
                    end
                end

                // POWER machine: one-time 1000 purchase.
                else if (near_power_machine) begin
                    if (!power_on && (money_value >= POWER_PRICE)) begin
                        power_on <= 1'b1;
                        money_value <= money_value - POWER_PRICE;
                        money_thousands <= money_thousands - 4'd1;
                    end
                end

                // ULTIMATE machine: requires power.
                // Upgrades the CURRENTLY EQUIPPED gun for 1500, once per gun.
                else if (near_ultimate_machine && power_on &&
                         (money_value >= ULTIMATE_PRICE)) begin
                    case (equipped_weapon)
                        WEAPON_PISTOL: begin
                            if (!pistol_ultimate) begin
                                pistol_ultimate <= 1'b1;
                                ultimate_upgrade_pulse <= 1'b1;
                                ultimate_upgrade_weapon <= WEAPON_PISTOL;

                                money_value <= money_value - ULTIMATE_PRICE;
                                if (money_hundreds >= 4'd5) begin
                                    money_thousands <= money_thousands - 4'd1;
                                    money_hundreds <= money_hundreds - 4'd5;
                                end
                                else begin
                                    money_thousands <= money_thousands - 4'd2;
                                    money_hundreds <= money_hundreds + 4'd5;
                                end
                            end
                        end

                        WEAPON_SHOTGUN: begin
                            if (!shotgun_ultimate) begin
                                shotgun_ultimate <= 1'b1;
                                ultimate_upgrade_pulse <= 1'b1;
                                ultimate_upgrade_weapon <= WEAPON_SHOTGUN;

                                money_value <= money_value - ULTIMATE_PRICE;
                                if (money_hundreds >= 4'd5) begin
                                    money_thousands <= money_thousands - 4'd1;
                                    money_hundreds <= money_hundreds - 4'd5;
                                end
                                else begin
                                    money_thousands <= money_thousands - 4'd2;
                                    money_hundreds <= money_hundreds + 4'd5;
                                end
                            end
                        end

                        default: begin
                            if (!rifle_ultimate) begin
                                rifle_ultimate <= 1'b1;
                                ultimate_upgrade_pulse <= 1'b1;
                                ultimate_upgrade_weapon <= WEAPON_RIFLE;

                                money_value <= money_value - ULTIMATE_PRICE;
                                if (money_hundreds >= 4'd5) begin
                                    money_thousands <= money_thousands - 4'd1;
                                    money_hundreds <= money_hundreds - 4'd5;
                                end
                                else begin
                                    money_thousands <= money_thousands - 4'd2;
                                    money_hundreds <= money_hundreds + 4'd5;
                                end
                            end
                        end
                    endcase
                end

                // Existing 1000-point room doors.
                else if (money_value >= DOOR_PRICE) begin
                    if (near_ul && !door_ul_open) begin
                        door_ul_open <= 1'b1;
                        money_value <= money_value - DOOR_PRICE;
                        money_thousands <= money_thousands - 4'd1;
                    end
                    else if (near_ur && !door_ur_open) begin
                        door_ur_open <= 1'b1;
                        money_value <= money_value - DOOR_PRICE;
                        money_thousands <= money_thousands - 4'd1;
                    end
                    else if (near_ll && !door_ll_open) begin
                        door_ll_open <= 1'b1;
                        money_value <= money_value - DOOR_PRICE;
                        money_thousands <= money_thousands - 4'd1;
                    end
                    else if (near_lr && !door_lr_open) begin
                        door_lr_open <= 1'b1;
                        money_value <= money_value - DOOR_PRICE;
                        money_thousands <= money_thousands - 4'd1;
                    end
                end
            end

            // ------------------------------------------------------------
            // POWER UP machine.
            //
            // Requires POWER.
            // Stand near the machine and press:
            //   1 = move speed
            //   2 = slow zombies
            //   3 = +1 max HP
            //   4 = faster reload
            //
            // Each costs 1000. Maximum two unique perks.
            // ------------------------------------------------------------
            else if (any_perk_press &&
                     near_powerup_machine &&
                     power_on &&
                     (perk_count < 2'd2) &&
                     (money_value >= PERK_PRICE)) begin

                if (perk1_press && !perk_move_speed) begin
                    perk_move_speed <= 1'b1;
                    perk_count <= perk_count + 2'd1;
                    money_value <= money_value - PERK_PRICE;
                    money_thousands <= money_thousands - 4'd1;
                end
                else if (perk2_press && !perk_zombie_slow) begin
                    perk_zombie_slow <= 1'b1;
                    perk_count <= perk_count + 2'd1;
                    money_value <= money_value - PERK_PRICE;
                    money_thousands <= money_thousands - 4'd1;
                end
                else if (perk3_press && !perk_extra_hp) begin
                    perk_extra_hp <= 1'b1;
                    perk_count <= perk_count + 2'd1;
                    money_value <= money_value - PERK_PRICE;
                    money_thousands <= money_thousands - 4'd1;
                end
                else if (perk4_press && !perk_fast_reload) begin
                    perk_fast_reload <= 1'b1;
                    perk_count <= perk_count + 2'd1;
                    money_value <= money_value - PERK_PRICE;
                    money_thousands <= money_thousands - 4'd1;
                end
            end

            // ------------------------------------------------------------
            // Existing hit rewards / debug P.
            // ------------------------------------------------------------
            else if (hit_reward_pulse && (hit_reward_amount == 6'd30)) begin
                if (money_value >= 14'd9970) begin
                    money_value     <= MONEY_MAX;
                    money_thousands <= 4'd9;
                    money_hundreds  <= 4'd9;
                    money_tens      <= 4'd9;
                    money_ones      <= 4'd9;
                end
                else begin
                    money_value <= money_value + 14'd30;

                    if (money_tens <= 4'd6)
                        money_tens <= money_tens + 4'd3;
                    else begin
                        money_tens <= money_tens - 4'd7;

                        if (money_hundreds < 4'd9)
                            money_hundreds <= money_hundreds + 4'd1;
                        else begin
                            money_hundreds <= 4'd0;
                            if (money_thousands < 4'd9)
                                money_thousands <= money_thousands + 4'd1;
                        end
                    end
                end
            end
            else if (hit_reward_pulse || (frame_tick && key_p)) begin
                if (money_value >= 14'd9990) begin
                    money_value     <= MONEY_MAX;
                    money_thousands <= 4'd9;
                    money_hundreds  <= 4'd9;
                    money_tens      <= 4'd9;
                    money_ones      <= 4'd9;
                end
                else begin
                    money_value <= money_value + 14'd10;

                    if (money_tens < 4'd9)
                        money_tens <= money_tens + 4'd1;
                    else begin
                        money_tens <= 4'd0;

                        if (money_hundreds < 4'd9)
                            money_hundreds <= money_hundreds + 4'd1;
                        else begin
                            money_hundreds <= 4'd0;
                            if (money_thousands < 4'd9)
                                money_thousands <= money_thousands + 4'd1;
                        end
                    end
                end
            end
        end
    end
endmodule



// ============================================================================
// V23 WEAPON SYSTEM CONTROLLER
//
// Weapon ids:
//   0 = pistol
//   1 = shotgun
//   2 = rifle
//
// Magazine / firing rules:
//   pistol : 20 ammo, semi-auto, 3 damage, 1.2 s reload
//   shotgun: 10 ammo, semi-auto, 20 damage, 0.3 s cooldown, 2.0 s reload
//   rifle  : 30 ammo, full-auto ~10 shots/s, 5 damage, 1.8 s reload
//
// All timing uses the ~60 Hz gameplay frame tick:
//   0.1 s = 6 frames
//   0.3 s = 18 frames
//   1.2 s = 72 frames
//   1.8 s = 108 frames
//   2.0 s = 120 frames
//
// Reload display is tracked directly in tenths. Each tenth lasts six frames.
// V26: finite shotgun/rifle reserve ammo; pistol reserve remains unlimited.
// ============================================================================
module weapon_system_controller (
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire       frame_tick,

    input  wire       left_click_pulse,
    input  wire       left_mouse_held,
    input  wire       reload_key,

    input  wire [1:0] equipped_weapon,

    input  wire       fast_reload_perk,
    input  wire       pistol_ultimate,
    input  wire       shotgun_ultimate,
    input  wire       rifle_ultimate,

    input  wire       ammo_refill_pulse,
    input  wire [1:0] ammo_refill_weapon,

    input  wire       ultimate_upgrade_pulse,
    input  wire [1:0] ultimate_upgrade_weapon,

    output wire       fire_pulse,
    output reg        pistol_fire_pulse,
    output reg        shotgun_fire_pulse,
    output reg        rifle_fire_pulse,

    output reg  [6:0] shot_damage,
    output reg  [5:0] ammo_count,
    output reg  [8:0] reserve_count,
    output reg        reserve_unlimited,
    output reg        reload_active,
    output reg  [4:0] reload_tenths_remaining
);

    localparam [1:0]
        WEAPON_PISTOL  = 2'd0,
        WEAPON_SHOTGUN = 2'd1,
        WEAPON_RIFLE   = 2'd2;

    // Base magazine sizes.
    localparam [5:0]
        PISTOL_MAG_BASE  = 6'd20,
        SHOTGUN_MAG_BASE = 6'd10,
        RIFLE_MAG_BASE   = 6'd30;

    // Ultimate +30%, rounded up:
    // 20*1.3=26, 10*1.3=13, 30*1.3=39.
    localparam [5:0]
        PISTOL_MAG_ULT  = 6'd26,
        SHOTGUN_MAG_ULT = 6'd13,
        RIFLE_MAG_ULT   = 6'd39;

    // Reserve ammo.
    // Pistol remains unlimited.
    localparam [6:0]
        SHOTGUN_RESERVE_BASE = 7'd80,
        SHOTGUN_RESERVE_ULT  = 7'd104;   // 80*1.3

    localparam [8:0]
        RIFLE_RESERVE_BASE = 9'd300,
        RIFLE_RESERVE_ULT  = 9'd390;     // 300*1.3

    localparam [6:0]
        PISTOL_DAMAGE  = 7'd3,
        SHOTGUN_DAMAGE = 7'd20,
        RIFLE_DAMAGE   = 7'd5;

    localparam [4:0] SHOTGUN_COOLDOWN = 5'd17; // 18-frame interval

    reg [5:0] pistol_ammo;
    reg [5:0] shotgun_ammo;
    reg [5:0] rifle_ammo;

    reg [6:0] shotgun_reserve;
    reg [8:0] rifle_reserve;

    reg [4:0] cooldown_frames;

    // Ultimate rifle target = +30% over 10 shots/s = exactly 13 shots/s.
    // Over 13 shot intervals, use five 4-frame intervals and eight 5-frame
    // intervals: (5*4 + 8*5) = 60 frames for 13 shots.
    reg [3:0] rifle_ultimate_phase;

    reg semi_pending;

    reg reload_key_d;
    reg reload_pending;
    wire reload_key_press = reload_key && !reload_key_d;

    reg [2:0] reload_subframe;
    reg [1:0] last_weapon;

    wire [5:0] pistol_mag_max =
        pistol_ultimate ? PISTOL_MAG_ULT : PISTOL_MAG_BASE;

    wire [5:0] shotgun_mag_max =
        shotgun_ultimate ? SHOTGUN_MAG_ULT : SHOTGUN_MAG_BASE;

    wire [5:0] rifle_mag_max =
        rifle_ultimate ? RIFLE_MAG_ULT : RIFLE_MAG_BASE;

    wire [6:0] shotgun_reserve_max =
        shotgun_ultimate ? SHOTGUN_RESERVE_ULT : SHOTGUN_RESERVE_BASE;

    wire [8:0] rifle_reserve_max =
        rifle_ultimate ? RIFLE_RESERVE_ULT : RIFLE_RESERVE_BASE;

    // Reload times in tenths of a second.
    //
    // Base:
    //   pistol 1.2, shotgun 2.0, rifle 1.8
    //
    // Either Fast Reload perk OR Ultimate:
    //   -30%, rounded UP to one decimal:
    //   pistol 0.9, shotgun 1.4, rifle 1.3
    //
    // Both stack multiplicatively (0.7*0.7 = 0.49):
    //   pistol ceil(1.2*0.49)=0.6
    //   shotgun ceil(2.0*0.49)=1.0
    //   rifle ceil(1.8*0.49)=0.9
    reg [4:0] current_reload_tenths;

    always @(*) begin
        case (equipped_weapon)
            WEAPON_SHOTGUN: begin
                if (fast_reload_perk && shotgun_ultimate)
                    current_reload_tenths = 5'd10;
                else if (fast_reload_perk || shotgun_ultimate)
                    current_reload_tenths = 5'd14;
                else
                    current_reload_tenths = 5'd20;
            end

            WEAPON_RIFLE: begin
                if (fast_reload_perk && rifle_ultimate)
                    current_reload_tenths = 5'd9;
                else if (fast_reload_perk || rifle_ultimate)
                    current_reload_tenths = 5'd13;
                else
                    current_reload_tenths = 5'd18;
            end

            default: begin
                if (fast_reload_perk && pistol_ultimate)
                    current_reload_tenths = 5'd6;
                else if (fast_reload_perk || pistol_ultimate)
                    current_reload_tenths = 5'd9;
                else
                    current_reload_tenths = 5'd12;
            end
        endcase
    end

    wire [5:0] shotgun_needed =
        shotgun_mag_max - shotgun_ammo;

    wire [5:0] rifle_needed =
        rifle_mag_max - rifle_ammo;

    assign fire_pulse =
        pistol_fire_pulse || shotgun_fire_pulse || rifle_fire_pulse;

    always @(*) begin
        case (equipped_weapon)
            WEAPON_SHOTGUN: begin
                ammo_count = shotgun_ammo;
                reserve_count = {2'b00,shotgun_reserve};
                reserve_unlimited = 1'b0;
                shot_damage = SHOTGUN_DAMAGE;
            end

            WEAPON_RIFLE: begin
                ammo_count = rifle_ammo;
                reserve_count = rifle_reserve;
                reserve_unlimited = 1'b0;
                shot_damage = RIFLE_DAMAGE;
            end

            default: begin
                ammo_count = pistol_ammo;
                reserve_count = 9'd0;
                reserve_unlimited = 1'b1;
                shot_damage = PISTOL_DAMAGE;
            end
        endcase
    end

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            pistol_ammo  <= PISTOL_MAG_BASE;
            shotgun_ammo <= SHOTGUN_MAG_BASE;
            rifle_ammo   <= RIFLE_MAG_BASE;

            shotgun_reserve <= SHOTGUN_RESERVE_BASE;
            rifle_reserve <= RIFLE_RESERVE_BASE;

            cooldown_frames <= 5'd0;
            rifle_ultimate_phase <= 4'd0;

            semi_pending <= 1'b0;
            reload_key_d <= 1'b0;
            reload_pending <= 1'b0;

            reload_active <= 1'b0;
            reload_tenths_remaining <= 5'd0;
            reload_subframe <= 3'd0;

            last_weapon <= WEAPON_PISTOL;

            pistol_fire_pulse  <= 1'b0;
            shotgun_fire_pulse <= 1'b0;
            rifle_fire_pulse   <= 1'b0;
        end
        else begin
            pistol_fire_pulse  <= 1'b0;
            shotgun_fire_pulse <= 1'b0;
            rifle_fire_pulse   <= 1'b0;

            reload_key_d <= reload_key;

            if (left_click_pulse)
                semi_pending <= 1'b1;

            if (reload_key_press)
                reload_pending <= 1'b1;

            // ------------------------------------------------------------
            // V26B WALL MAX-AMMO REFILL FIX.
            //
            // Refill BOTH the magazine and reserve. In V26 only reserve was
            // restored, so the existing magazine-only HUD made the refill look
            // broken. This now behaves as an immediate full-ammo station.
            // ------------------------------------------------------------
            if (ammo_refill_pulse) begin
                case (ammo_refill_weapon)
                    WEAPON_SHOTGUN: begin
                        shotgun_ammo <= shotgun_mag_max;
                        shotgun_reserve <= shotgun_reserve_max;
                    end

                    WEAPON_RIFLE: begin
                        rifle_ammo <= rifle_mag_max;
                        rifle_reserve <= rifle_reserve_max;
                    end

                    default: ;
                endcase
            end

            // ------------------------------------------------------------
            // Ultimate purchase:
            // refill reserve to the new maximum and force current gun reload.
            // ------------------------------------------------------------
            if (ultimate_upgrade_pulse) begin
                case (ultimate_upgrade_weapon)
                    WEAPON_SHOTGUN:
                        shotgun_reserve <= SHOTGUN_RESERVE_ULT;
                    WEAPON_RIFLE:
                        rifle_reserve <= RIFLE_RESERVE_ULT;
                    default: ;
                endcase
            end

            if (ultimate_upgrade_pulse &&
                (ultimate_upgrade_weapon == equipped_weapon)) begin

                last_weapon <= equipped_weapon;
                cooldown_frames <= 5'd0;
                semi_pending <= 1'b0;
                reload_pending <= 1'b0;

                reload_active <= 1'b1;
                reload_tenths_remaining <= current_reload_tenths;
                reload_subframe <= 3'd5;
            end

            // Switching weapons cancels reload/cooldown but keeps each mag.
            else if (equipped_weapon != last_weapon) begin
                last_weapon <= equipped_weapon;
                cooldown_frames <= 5'd0;
                semi_pending <= 1'b0;
                reload_pending <= 1'b0;
                reload_active <= 1'b0;
                reload_tenths_remaining <= 5'd0;
                reload_subframe <= 3'd0;
            end

            // Wall max-ammo refill gets a clean clock of priority so a
            // reload completion cannot overwrite the refill values.
            else if (ammo_refill_pulse) begin
                cooldown_frames <= 5'd0;
                semi_pending <= 1'b0;
                reload_pending <= 1'b0;
                reload_active <= 1'b0;
                reload_tenths_remaining <= 5'd0;
                reload_subframe <= 3'd0;

                // Economy re-equips the refilled gun on the same interaction.
                // Capture the requested target here so the next clock does not
                // create a spurious weapon-switch cleanup cycle.
                last_weapon <= ammo_refill_weapon;
            end

            else if (frame_tick) begin
                // ------------------------------------------------------------
                // Reload countdown.
                // ------------------------------------------------------------
                if (reload_active) begin
                    semi_pending <= 1'b0;
                    reload_pending <= 1'b0;

                    if (reload_subframe != 3'd0) begin
                        reload_subframe <= reload_subframe - 3'd1;
                    end
                    else if (reload_tenths_remaining > 5'd1) begin
                        reload_tenths_remaining <= reload_tenths_remaining - 5'd1;
                        reload_subframe <= 3'd5;
                    end
                    else begin
                        reload_active <= 1'b0;
                        reload_tenths_remaining <= 5'd0;
                        reload_subframe <= 3'd0;

                        case (equipped_weapon)
                            // Pistol reserve is unlimited.
                            WEAPON_PISTOL:
                                pistol_ammo <= pistol_mag_max;

                            WEAPON_SHOTGUN: begin
                                if (shotgun_reserve >= {1'b0,shotgun_needed}) begin
                                    shotgun_ammo <= shotgun_mag_max;
                                    shotgun_reserve <=
                                        shotgun_reserve - {1'b0,shotgun_needed};
                                end
                                else begin
                                    shotgun_ammo <=
                                        shotgun_ammo + shotgun_reserve[5:0];
                                    shotgun_reserve <= 7'd0;
                                end
                            end

                            WEAPON_RIFLE: begin
                                if (rifle_reserve >= {3'b000,rifle_needed}) begin
                                    rifle_ammo <= rifle_mag_max;
                                    rifle_reserve <=
                                        rifle_reserve - {3'b000,rifle_needed};
                                end
                                else begin
                                    rifle_ammo <=
                                        rifle_ammo + rifle_reserve[5:0];
                                    rifle_reserve <= 9'd0;
                                end
                            end

                            default: ;
                        endcase
                    end
                end

                else begin
                    if (cooldown_frames != 0)
                        cooldown_frames <= cooldown_frames - 5'd1;

                    case (equipped_weapon)
                        // ----------------------------------------------------
                        // PISTOL: unlimited reserve.
                        // ----------------------------------------------------
                        WEAPON_PISTOL: begin
                            if ((pistol_ammo == 0) ||
                                (reload_pending &&
                                 (pistol_ammo < pistol_mag_max))) begin

                                reload_active <= 1'b1;
                                reload_tenths_remaining <= current_reload_tenths;
                                reload_subframe <= 3'd5;
                                reload_pending <= 1'b0;
                                semi_pending <= 1'b0;
                            end
                            else begin
                                if (reload_pending)
                                    reload_pending <= 1'b0;

                                if (semi_pending) begin
                                    semi_pending <= 1'b0;

                                    if (pistol_ammo != 0) begin
                                        pistol_fire_pulse <= 1'b1;
                                        pistol_ammo <= pistol_ammo - 6'd1;

                                        if (pistol_ammo == 6'd1) begin
                                            reload_active <= 1'b1;
                                            reload_tenths_remaining <=
                                                current_reload_tenths;
                                            reload_subframe <= 3'd5;
                                        end
                                    end
                                end
                            end
                        end

                        // ----------------------------------------------------
                        // SHOTGUN: max reserve 80 / 104 Ultimate.
                        // ----------------------------------------------------
                        WEAPON_SHOTGUN: begin
                            if (((shotgun_ammo == 0) &&
                                 (shotgun_reserve != 0)) ||
                                (reload_pending &&
                                 (shotgun_ammo < shotgun_mag_max) &&
                                 (shotgun_reserve != 0))) begin

                                reload_active <= 1'b1;
                                reload_tenths_remaining <= current_reload_tenths;
                                reload_subframe <= 3'd5;
                                reload_pending <= 1'b0;
                                semi_pending <= 1'b0;
                            end
                            else begin
                                if (reload_pending)
                                    reload_pending <= 1'b0;

                                if (semi_pending) begin
                                    semi_pending <= 1'b0;

                                    if ((cooldown_frames == 0) &&
                                        (shotgun_ammo != 0)) begin

                                        shotgun_fire_pulse <= 1'b1;
                                        cooldown_frames <= SHOTGUN_COOLDOWN;
                                        shotgun_ammo <= shotgun_ammo - 6'd1;

                                        if ((shotgun_ammo == 6'd1) &&
                                            (shotgun_reserve != 0)) begin

                                            reload_active <= 1'b1;
                                            reload_tenths_remaining <=
                                                current_reload_tenths;
                                            reload_subframe <= 3'd5;
                                        end
                                    end
                                end
                            end
                        end

                        // ----------------------------------------------------
                        // RIFLE: max reserve 300 / 390 Ultimate.
                        // ----------------------------------------------------
                        WEAPON_RIFLE: begin
                            semi_pending <= 1'b0;

                            if (((rifle_ammo == 0) &&
                                 (rifle_reserve != 0)) ||
                                (reload_pending &&
                                 (rifle_ammo < rifle_mag_max) &&
                                 (rifle_reserve != 0))) begin

                                reload_active <= 1'b1;
                                reload_tenths_remaining <= current_reload_tenths;
                                reload_subframe <= 3'd5;
                                reload_pending <= 1'b0;
                            end
                            else begin
                                if (reload_pending)
                                    reload_pending <= 1'b0;

                                if (left_mouse_held &&
                                    (cooldown_frames == 0) &&
                                    (rifle_ammo != 0)) begin

                                    rifle_fire_pulse <= 1'b1;
                                    rifle_ammo <= rifle_ammo - 6'd1;

                                    if (rifle_ultimate) begin
                                        // 5 x 4-frame intervals, then
                                        // 8 x 5-frame intervals = 60 frames
                                        // for 13 shots exactly.
                                        if (rifle_ultimate_phase < 4'd5)
                                            cooldown_frames <= 5'd3;
                                        else
                                            cooldown_frames <= 5'd4;

                                        if (rifle_ultimate_phase == 4'd12)
                                            rifle_ultimate_phase <= 4'd0;
                                        else
                                            rifle_ultimate_phase <=
                                                rifle_ultimate_phase + 4'd1;
                                    end
                                    else begin
                                        cooldown_frames <= 5'd5; // 6 frames
                                        rifle_ultimate_phase <= 4'd0;
                                    end

                                    if ((rifle_ammo == 6'd1) &&
                                        (rifle_reserve != 0)) begin

                                        reload_active <= 1'b1;
                                        reload_tenths_remaining <=
                                            current_reload_tenths;
                                        reload_subframe <= 3'd5;
                                    end
                                end
                            end
                        end

                        default: ;
                    endcase
                end
            end
        end
    end
endmodule


// ============================================================================
// FOUR-DIGIT SCREEN MONEY HUD
//
// 4 x seven-segment-style glyphs at upper-left, no division/modulo and no
// multiplication. Leading zeroes are intentionally shown (0000..9999).
// ============================================================================
module money_hud_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,

    input  wire [3:0] digit_thousands,
    input  wire [3:0] digit_hundreds,
    input  wire [3:0] digit_tens,
    input  wire [3:0] digit_ones,

    output reg        money_pixel
);

    reg [3:0] digit_value;
    reg [4:0] local_x;
    reg [4:0] local_y;
    reg       inside_digit;
    reg [6:0] segments;

    function [6:0] digit_segments;
        input [3:0] d;
        begin
            // bits: a b c d e f g
            case (d)
                4'd0: digit_segments = 7'b1111110;
                4'd1: digit_segments = 7'b0110000;
                4'd2: digit_segments = 7'b1101101;
                4'd3: digit_segments = 7'b1111001;
                4'd4: digit_segments = 7'b0110011;
                4'd5: digit_segments = 7'b1011011;
                4'd6: digit_segments = 7'b1011111;
                4'd7: digit_segments = 7'b1110000;
                4'd8: digit_segments = 7'b1111111;
                4'd9: digit_segments = 7'b1111011;
                default: digit_segments = 7'b0000000;
            endcase
        end
    endfunction

    always @(*) begin
        inside_digit = 1'b1;
        digit_value  = 4'd0;
        local_x      = 5'd0;
        local_y      = 5'd0;
        money_pixel  = 1'b0;

        // Each digit is 12x22 with 4 pixels of spacing.
        // Overall HUD begins at x=12, y=14.
        if ((pixel_y >= 10'd14) && (pixel_y < 10'd36)) begin
            local_y = pixel_y - 10'd14;

            if ((pixel_x >= 10'd12) && (pixel_x < 10'd24)) begin
                digit_value = digit_thousands;
                local_x = pixel_x - 10'd12;
            end
            else if ((pixel_x >= 10'd28) && (pixel_x < 10'd40)) begin
                digit_value = digit_hundreds;
                local_x = pixel_x - 10'd28;
            end
            else if ((pixel_x >= 10'd44) && (pixel_x < 10'd56)) begin
                digit_value = digit_tens;
                local_x = pixel_x - 10'd44;
            end
            else if ((pixel_x >= 10'd60) && (pixel_x < 10'd72)) begin
                digit_value = digit_ones;
                local_x = pixel_x - 10'd60;
            end
            else begin
                inside_digit = 1'b0;
            end
        end
        else begin
            inside_digit = 1'b0;
        end

        segments = digit_segments(digit_value);

        if (inside_digit) begin
            // 2-pixel-thick seven-segment strokes.
            // a
            if (segments[6] && (local_y <= 5'd1) &&
                (local_x >= 5'd2) && (local_x <= 5'd9))
                money_pixel = 1'b1;
            // b
            if (segments[5] && (local_x >= 5'd10) &&
                (local_y >= 5'd2) && (local_y <= 5'd9))
                money_pixel = 1'b1;
            // c
            if (segments[4] && (local_x >= 5'd10) &&
                (local_y >= 5'd12) && (local_y <= 5'd19))
                money_pixel = 1'b1;
            // d
            if (segments[3] && (local_y >= 5'd20) &&
                (local_x >= 5'd2) && (local_x <= 5'd9))
                money_pixel = 1'b1;
            // e
            if (segments[2] && (local_x <= 5'd1) &&
                (local_y >= 5'd12) && (local_y <= 5'd19))
                money_pixel = 1'b1;
            // f
            if (segments[1] && (local_x <= 5'd1) &&
                (local_y >= 5'd2) && (local_y <= 5'd9))
                money_pixel = 1'b1;
            // g
            if (segments[0] && (local_y >= 5'd10) && (local_y <= 5'd11) &&
                (local_x >= 5'd2) && (local_x <= 5'd9))
                money_pixel = 1'b1;
        end
    end

endmodule


// ============================================================================
// FPGA -> PC SOUND EVENT SENDER
//
// Event bytes:
//   0xA1 = gun shot
//   0xA2 = target hit / destroyed
//   0xA3 = Speed Flick / 99 Bots target appeared
//
// Priority when several events happen together:
//   shot -> hit -> appearance.
// ============================================================================
module sound_event_sender (
    input  wire clk_100mhz,
    input  wire reset,

    input  wire pistol_shot_pulse,
    input  wire shotgun_shot_pulse,
    input  wire rifle_shot_pulse,

    input  wire hit_pulse,
    input  wire appear_pulse,
    input  wire round_change_pulse,

    input  wire       music_cmd_valid,
    input  wire [2:0] music_cmd_code,

    output wire RsTx
);

    // PC-side host script V5:
    //   A1 = pistol
    //   A4 = shotgun
    //   A5 = rifle
    //   A2 = zombie hit
    //   A3 = zombie appearance
    localparam [7:0] EVENT_PISTOL  = 8'hA1;
    localparam [7:0] EVENT_HIT     = 8'hA2;
    localparam [7:0] EVENT_APPEAR  = 8'hA3;
    localparam [7:0] EVENT_SHOTGUN = 8'hA4;
    localparam [7:0] EVENT_RIFLE   = 8'hA5;
    localparam [7:0] EVENT_ROUND   = 8'hA6;

    // V24C music-control bytes.
    localparam [7:0] EVENT_MUSIC_START_RESET = 8'hA7;
    localparam [7:0] EVENT_MUSIC_PAUSE       = 8'hA8;
    localparam [7:0] EVENT_MUSIC_RESUME      = 8'hA9;
    localparam [7:0] EVENT_MUSIC_STOP_RESET  = 8'hAA;

    reg pending_pistol;
    reg pending_shotgun;
    reg pending_rifle;
    reg pending_hit;
    reg pending_appear;
    reg pending_round;

    // Only one music transition can be outstanding at a time.
    reg       pending_music_valid;
    reg [2:0] pending_music_code;

    reg [7:0] tx_data;
    reg       tx_start;
    wire      tx_busy;

    uart_tx_115200 uart_tx_inst (
        .clk_100mhz(clk_100mhz),
        .reset(reset),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .RsTx(RsTx),
        .tx_busy(tx_busy)
    );

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            pending_pistol  <= 1'b0;
            pending_shotgun <= 1'b0;
            pending_rifle   <= 1'b0;
            pending_hit     <= 1'b0;
            pending_appear  <= 1'b0;
            pending_round   <= 1'b0;
            pending_music_valid <= 1'b0;
            pending_music_code  <= 3'd0;
            tx_data         <= 8'h00;
            tx_start        <= 1'b0;
        end
        else begin
            tx_start <= 1'b0;

            if (pistol_shot_pulse)
                pending_pistol <= 1'b1;
            if (shotgun_shot_pulse)
                pending_shotgun <= 1'b1;
            if (rifle_shot_pulse)
                pending_rifle <= 1'b1;
            if (hit_pulse)
                pending_hit <= 1'b1;
            if (appear_pulse)
                pending_appear <= 1'b1;
            if (round_change_pulse)
                pending_round <= 1'b1;

            if (music_cmd_valid) begin
                pending_music_valid <= 1'b1;
                pending_music_code  <= music_cmd_code;
            end

            if (!tx_busy && !tx_start) begin
                if (pending_music_valid) begin
                    case (pending_music_code)
                        3'd1: tx_data <= EVENT_MUSIC_START_RESET;
                        3'd2: tx_data <= EVENT_MUSIC_PAUSE;
                        3'd3: tx_data <= EVENT_MUSIC_RESUME;
                        3'd4: tx_data <= EVENT_MUSIC_STOP_RESET;
                        default: tx_data <= EVENT_MUSIC_STOP_RESET;
                    endcase

                    tx_start <= 1'b1;
                    pending_music_valid <= 1'b0;
                end
                else if (pending_pistol) begin
                    tx_data <= EVENT_PISTOL;
                    tx_start <= 1'b1;
                    pending_pistol <= 1'b0;
                end
                else if (pending_shotgun) begin
                    tx_data <= EVENT_SHOTGUN;
                    tx_start <= 1'b1;
                    pending_shotgun <= 1'b0;
                end
                else if (pending_rifle) begin
                    tx_data <= EVENT_RIFLE;
                    tx_start <= 1'b1;
                    pending_rifle <= 1'b0;
                end
                else if (pending_hit) begin
                    tx_data <= EVENT_HIT;
                    tx_start <= 1'b1;
                    pending_hit <= 1'b0;
                end
                else if (pending_round) begin
                    tx_data <= EVENT_ROUND;
                    tx_start <= 1'b1;
                    pending_round <= 1'b0;
                end
                else if (pending_appear) begin
                    tx_data <= EVENT_APPEAR;
                    tx_start <= 1'b1;
                    pending_appear <= 1'b0;
                end
            end
        end
    end

endmodule


// ============================================================================
// UART TRANSMITTER - 115200 BAUD, 8N1
// ============================================================================
module uart_tx_115200 #(
    parameter integer CLOCK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE     = 115_200
)(
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire [7:0] tx_data,
    input  wire       tx_start,

    output reg        RsTx,
    output reg        tx_busy
);

    localparam integer CLKS_PER_BIT = CLOCK_FREQ_HZ / BAUD_RATE;

    localparam [1:0]
        TX_IDLE  = 2'd0,
        TX_START = 2'd1,
        TX_DATA  = 2'd2,
        TX_STOP  = 2'd3;

    reg [1:0] state;
    reg [9:0] baud_counter;
    reg [2:0] bit_index;
    reg [7:0] tx_shift;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            state        <= TX_IDLE;
            baud_counter <= 10'd0;
            bit_index    <= 3'd0;
            tx_shift     <= 8'd0;
            RsTx         <= 1'b1;
            tx_busy      <= 1'b0;
        end else begin
            case (state)

                TX_IDLE: begin
                    RsTx         <= 1'b1;
                    tx_busy      <= 1'b0;
                    baud_counter <= 10'd0;
                    bit_index    <= 3'd0;

                    if (tx_start) begin
                        tx_shift <= tx_data;
                        tx_busy  <= 1'b1;
                        RsTx     <= 1'b0; // start bit
                        state    <= TX_START;
                    end
                end

                TX_START: begin
                    tx_busy <= 1'b1;
                    RsTx    <= 1'b0;

                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter <= 10'd0;
                        RsTx         <= tx_shift[0];
                        state        <= TX_DATA;
                    end else begin
                        baud_counter <= baud_counter + 10'd1;
                    end
                end

                TX_DATA: begin
                    tx_busy <= 1'b1;
                    RsTx    <= tx_shift[bit_index];

                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter <= 10'd0;

                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            RsTx      <= 1'b1;
                            state     <= TX_STOP;
                        end else begin
                            bit_index <= bit_index + 3'd1;
                            RsTx      <= tx_shift[bit_index + 3'd1];
                        end
                    end else begin
                        baud_counter <= baud_counter + 10'd1;
                    end
                end

                TX_STOP: begin
                    tx_busy <= 1'b1;
                    RsTx    <= 1'b1;

                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter <= 10'd0;
                        tx_busy      <= 1'b0;
                        state        <= TX_IDLE;
                    end else begin
                        baud_counter <= baud_counter + 10'd1;
                    end
                end

                default: begin
                    state   <= TX_IDLE;
                    RsTx    <= 1'b1;
                    tx_busy <= 1'b0;
                end

            endcase
        end
    end

endmodule


// ============================================================================
// VGA CONTROLLER - 640x480 @ ~60 Hz
// ============================================================================
module vga_controller_640x480 (
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire       pixel_tick,
    output wire       hsync,
    output wire       vsync,
    output wire       active_video,
    output wire [9:0] pixel_x,
    output wire [9:0] pixel_y,
    output reg        frame_tick
);

    localparam H_ACTIVE = 640;
    localparam H_FRONT  = 16;
    localparam H_SYNC   = 96;
    localparam H_TOTAL  = 800;

    localparam V_ACTIVE = 480;
    localparam V_FRONT  = 10;
    localparam V_SYNC   = 2;
    localparam V_TOTAL  = 525;

    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
            frame_tick <= 1'b0;
        end else begin
            frame_tick <= 1'b0;

            if (pixel_tick) begin
                if (h_cnt == H_TOTAL - 1) begin
                    h_cnt <= 10'd0;

                    if (v_cnt == V_TOTAL - 1) begin
                        v_cnt <= 10'd0;
                        frame_tick <= 1'b1;
                    end else begin
                        v_cnt <= v_cnt + 10'd1;
                    end
                end else begin
                    h_cnt <= h_cnt + 10'd1;
                end
            end
        end
    end

    assign hsync = ~((h_cnt >= H_ACTIVE + H_FRONT) &&
                     (h_cnt <  H_ACTIVE + H_FRONT + H_SYNC));

    assign vsync = ~((v_cnt >= V_ACTIVE + V_FRONT) &&
                     (v_cnt <  V_ACTIVE + V_FRONT + V_SYNC));

    assign active_video = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);
    assign pixel_x = h_cnt;
    assign pixel_y = v_cnt;

endmodule


// ============================================================================
// UART RECEIVER - 115200 BAUD, 8N1
// ============================================================================
module uart_rx_115200 #(
    parameter integer CLOCK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE     = 115_200
)(
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire       RsRx,
    output reg [7:0]  rx_byte,
    output reg        rx_valid,
    output reg        framing_error
);

    localparam integer CLKS_PER_BIT  = CLOCK_FREQ_HZ / BAUD_RATE;
    localparam integer HALF_BIT_CLKS = CLKS_PER_BIT / 2;

    localparam [2:0]
        STATE_IDLE  = 3'd0,
        STATE_START = 3'd1,
        STATE_DATA  = 3'd2,
        STATE_STOP  = 3'd3;

    reg rx_meta;
    reg rx_sync;

    reg [2:0] state;
    reg [9:0] baud_counter;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= RsRx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            state <= STATE_IDLE;
            baud_counter <= 10'd0;
            bit_index <= 3'd0;
            shift_reg <= 8'd0;
            rx_byte <= 8'd0;
            rx_valid <= 1'b0;
            framing_error <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            framing_error <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    baud_counter <= 10'd0;
                    bit_index <= 3'd0;
                    if (!rx_sync)
                        state <= STATE_START;
                end

                STATE_START: begin
                    if (baud_counter == HALF_BIT_CLKS - 1) begin
                        baud_counter <= 10'd0;
                        if (!rx_sync) begin
                            bit_index <= 3'd0;
                            state <= STATE_DATA;
                        end else begin
                            state <= STATE_IDLE;
                        end
                    end else begin
                        baud_counter <= baud_counter + 10'd1;
                    end
                end

                STATE_DATA: begin
                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter <= 10'd0;
                        shift_reg[bit_index] <= rx_sync;

                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            state <= STATE_STOP;
                        end else begin
                            bit_index <= bit_index + 3'd1;
                        end
                    end else begin
                        baud_counter <= baud_counter + 10'd1;
                    end
                end

                STATE_STOP: begin
                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter <= 10'd0;

                        if (rx_sync) begin
                            rx_byte <= shift_reg;
                            rx_valid <= 1'b1;
                        end else begin
                            framing_error <= 1'b1;
                        end

                        state <= STATE_IDLE;
                    end else begin
                        baud_counter <= baud_counter + 10'd1;
                    end
                end

                default:
                    state <= STATE_IDLE;
            endcase
        end
    end

endmodule


// ============================================================================
// 3-BYTE PACKET PARSER + CONTINUOUS INPUT STATE + WATCHDOG
// ============================================================================
module input_packet_parser (
    input  wire             clk_100mhz,
    input  wire             reset,
    input  wire [7:0]       rx_byte,
    input  wire             rx_valid,

    output reg signed [7:0] mouse_dx,
    output reg signed [7:0] mouse_dy,
    output reg              mouse_move_valid,

    output reg              key_w,
    output reg              key_a,
    output reg              key_s,
    output reg              key_d,
    output reg              key_e,
    output reg              key_p,
    output reg              key_r,
    output reg              key_y,
    output reg              key_1,
    output reg              key_2,
    output reg              key_3,
    output reg              key_4,
    output reg              key_space,

    output reg              left_mouse,
    output reg              right_mouse,
    output reg              left_click_pulse,
    output reg              wheel_up_pulse,
    output reg              wheel_down_pulse,
    output reg              host_alive
);

    localparam [7:0] PKT_MOUSE_MOVE  = 8'hC1;
    localparam [7:0] PKT_MOUSE_LEFT  = 8'hD0;
    localparam [7:0] PKT_MOUSE_RIGHT = 8'hD1;
    localparam [7:0] PKT_MOUSE_WHEEL = 8'hD2;
    localparam [7:0] PKT_KEYBOARD    = 8'hE0;
    localparam [7:0] PKT_HEARTBEAT   = 8'hF0;

    localparam [24:0] WATCHDOG_LIMIT = 25'd24_999_999;

    localparam [1:0]
        WAIT_HEADER = 2'd0,
        WAIT_B1     = 2'd1,
        WAIT_B2     = 2'd2;

    reg [1:0] parser_state;
    reg [7:0] header;
    reg [7:0] byte1;
    reg [24:0] watchdog_counter;

    wire known_header =
        (rx_byte == PKT_MOUSE_MOVE)  ||
        (rx_byte == PKT_MOUSE_LEFT)  ||
        (rx_byte == PKT_MOUSE_RIGHT) ||
        (rx_byte == PKT_MOUSE_WHEEL) ||
        (rx_byte == PKT_KEYBOARD)    ||
        (rx_byte == PKT_HEARTBEAT);

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            parser_state <= WAIT_HEADER;
            header <= 8'd0;
            byte1 <= 8'd0;

            mouse_dx <= 8'sd0;
            mouse_dy <= 8'sd0;
            mouse_move_valid <= 1'b0;

            key_w <= 1'b0;
            key_a <= 1'b0;
            key_s <= 1'b0;
            key_d <= 1'b0;
            key_e <= 1'b0;
            key_p <= 1'b0;
            key_r <= 1'b0;
            key_y <= 1'b0;
            key_1 <= 1'b0;
            key_2 <= 1'b0;
            key_3 <= 1'b0;
            key_4 <= 1'b0;
            key_space <= 1'b0;

            left_mouse <= 1'b0;
            right_mouse <= 1'b0;
            left_click_pulse <= 1'b0;
            wheel_up_pulse <= 1'b0;
            wheel_down_pulse <= 1'b0;

            watchdog_counter <= WATCHDOG_LIMIT;
            host_alive <= 1'b0;
        end else begin
            mouse_move_valid <= 1'b0;
            left_click_pulse <= 1'b0;
            wheel_up_pulse <= 1'b0;
            wheel_down_pulse <= 1'b0;

            if (watchdog_counter < WATCHDOG_LIMIT)
                watchdog_counter <= watchdog_counter + 25'd1;
            else begin
                host_alive <= 1'b0;
                key_w <= 1'b0;
                key_a <= 1'b0;
                key_s <= 1'b0;
                key_d <= 1'b0;
                key_e <= 1'b0;
                key_p <= 1'b0;
                key_r <= 1'b0;
                key_y <= 1'b0;
                key_1 <= 1'b0;
                key_2 <= 1'b0;
                key_3 <= 1'b0;
                key_4 <= 1'b0;
                key_space <= 1'b0;
                left_mouse <= 1'b0;
                right_mouse <= 1'b0;
            end

            if (rx_valid) begin
                case (parser_state)

                    WAIT_HEADER: begin
                        if (known_header) begin
                            header <= rx_byte;
                            parser_state <= WAIT_B1;
                        end
                    end

                    WAIT_B1: begin
                        byte1 <= rx_byte;
                        parser_state <= WAIT_B2;
                    end

                    WAIT_B2: begin
                        parser_state <= WAIT_HEADER;

                        case (header)
                            PKT_MOUSE_MOVE: begin
                                mouse_dx <= $signed(byte1);
                                mouse_dy <= $signed(rx_byte);
                                mouse_move_valid <= 1'b1;
                            end

                            PKT_MOUSE_LEFT: begin
                                left_mouse <= byte1[0];
                                if (byte1[0])
                                    left_click_pulse <= 1'b1;
                            end

                            PKT_MOUSE_RIGHT: begin
                                right_mouse <= byte1[0];
                            end

                            PKT_MOUSE_WHEEL: begin
                                if ($signed(byte1) > 8'sd0)
                                    wheel_up_pulse <= 1'b1;
                                else if ($signed(byte1) < 8'sd0)
                                    wheel_down_pulse <= 1'b1;
                            end

                            PKT_KEYBOARD: begin
                                case (byte1)
                                    8'h77: key_w <= rx_byte[0];
                                    8'h61: key_a <= rx_byte[0];
                                    8'h73: key_s <= rx_byte[0];
                                    8'h64: key_d <= rx_byte[0];
                                    8'h65: key_e <= rx_byte[0];
                                    8'h70: key_p <= rx_byte[0];
                                    8'h72: key_r <= rx_byte[0];
                                    8'h79: key_y <= rx_byte[0];
                                    8'h31: key_1 <= rx_byte[0];
                                    8'h32: key_2 <= rx_byte[0];
                                    8'h33: key_3 <= rx_byte[0];
                                    8'h34: key_4 <= rx_byte[0];
                                    8'h20: key_space <= rx_byte[0];
                                    default: ;
                                endcase
                            end

                            PKT_HEARTBEAT: begin
                                watchdog_counter <= 25'd0;
                                host_alive <= 1'b1;
                            end

                            default: ;
                        endcase
                    end

                    default:
                        parser_state <= WAIT_HEADER;
                endcase
            end
        end
    end

endmodule


// ============================================================================
// SENSITIVITY BUTTON CONTROLLER
// Basys 3 T18 pushbutton, active high.
//
// Debounce: ~20 ms @ 100 MHz.
// Each clean button press cycles:
//     1 -> 2 -> 3 -> 4 -> 1
// ============================================================================
module sensitivity_button_controller (
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire       button_in,
    output reg [2:0]  sensitivity_level
);

    localparam [20:0] DEBOUNCE_COUNT_MAX = 21'd1_999_999;

    reg button_meta;
    reg button_sync;
    reg button_stable;
    reg button_stable_d;
    reg [20:0] debounce_counter;

    wire button_pressed =
        button_stable && !button_stable_d;

    // Synchronize asynchronous mechanical pushbutton.
    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            button_meta <= 1'b0;
            button_sync <= 1'b0;
        end else begin
            button_meta <= button_in;
            button_sync <= button_meta;
        end
    end

    // Debounce.
    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            button_stable    <= 1'b0;
            debounce_counter <= 21'd0;
        end else begin
            if (button_sync == button_stable) begin
                debounce_counter <= 21'd0;
            end else begin
                if (debounce_counter == DEBOUNCE_COUNT_MAX) begin
                    button_stable    <= button_sync;
                    debounce_counter <= 21'd0;
                end else begin
                    debounce_counter <= debounce_counter + 21'd1;
                end
            end
        end
    end

    // Rising-edge history.
    always @(posedge clk_100mhz or posedge reset) begin
        if (reset)
            button_stable_d <= 1'b0;
        else
            button_stable_d <= button_stable;
    end

    // 1x -> 2x -> 3x -> 4x -> 1x
    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            sensitivity_level <= 3'd1;
        end else if (button_pressed) begin
            if (sensitivity_level >= 3'd4)
                sensitivity_level <= 3'd1;
            else
                sensitivity_level <= sensitivity_level + 3'd1;
        end
    end

endmodule



// ============================================================================
// V22G START / DEATH SCREEN TEXT
//
// Start:
//      PRESS Y TO START
//
// Death:
//      YOU DIED
//      PRESS Y TO RESTART
//
// 5x7 font, scale 4. Black background is selected by the top-level VGA mux.
// ============================================================================
module game_flow_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire       show_start,
    input  wire       show_dead,
    output reg        text_pixel,
    output reg        red_pixel
);

    function [4:0] glyph_row;
        input [7:0] ch;
        input [2:0] row;
        begin
            glyph_row = 5'b00000;
            case (ch)
                "A": case(row)
                    0:glyph_row=5'b01110; 1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001; 3:glyph_row=5'b11111;
                    4:glyph_row=5'b10001; 5:glyph_row=5'b10001;
                    6:glyph_row=5'b10001; default:glyph_row=0;
                endcase
                "D": case(row)
                    0:glyph_row=5'b11110; 1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001; 3:glyph_row=5'b10001;
                    4:glyph_row=5'b10001; 5:glyph_row=5'b10001;
                    6:glyph_row=5'b11110; default:glyph_row=0;
                endcase
                "E": case(row)
                    0:glyph_row=5'b11111; 1:glyph_row=5'b10000;
                    2:glyph_row=5'b10000; 3:glyph_row=5'b11110;
                    4:glyph_row=5'b10000; 5:glyph_row=5'b10000;
                    6:glyph_row=5'b11111; default:glyph_row=0;
                endcase
                "I": case(row)
                    0:glyph_row=5'b11111; 1:glyph_row=5'b00100;
                    2:glyph_row=5'b00100; 3:glyph_row=5'b00100;
                    4:glyph_row=5'b00100; 5:glyph_row=5'b00100;
                    6:glyph_row=5'b11111; default:glyph_row=0;
                endcase
                "O": case(row)
                    0:glyph_row=5'b01110; 1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001; 3:glyph_row=5'b10001;
                    4:glyph_row=5'b10001; 5:glyph_row=5'b10001;
                    6:glyph_row=5'b01110; default:glyph_row=0;
                endcase
                "P": case(row)
                    0:glyph_row=5'b11110; 1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001; 3:glyph_row=5'b11110;
                    4:glyph_row=5'b10000; 5:glyph_row=5'b10000;
                    6:glyph_row=5'b10000; default:glyph_row=0;
                endcase
                "R": case(row)
                    0:glyph_row=5'b11110; 1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001; 3:glyph_row=5'b11110;
                    4:glyph_row=5'b10100; 5:glyph_row=5'b10010;
                    6:glyph_row=5'b10001; default:glyph_row=0;
                endcase
                "S": case(row)
                    0:glyph_row=5'b01111; 1:glyph_row=5'b10000;
                    2:glyph_row=5'b10000; 3:glyph_row=5'b01110;
                    4:glyph_row=5'b00001; 5:glyph_row=5'b00001;
                    6:glyph_row=5'b11110; default:glyph_row=0;
                endcase
                "T": case(row)
                    0:glyph_row=5'b11111; 1:glyph_row=5'b00100;
                    2:glyph_row=5'b00100; 3:glyph_row=5'b00100;
                    4:glyph_row=5'b00100; 5:glyph_row=5'b00100;
                    6:glyph_row=5'b00100; default:glyph_row=0;
                endcase
                "U": case(row)
                    0:glyph_row=5'b10001; 1:glyph_row=5'b10001;
                    2:glyph_row=5'b10001; 3:glyph_row=5'b10001;
                    4:glyph_row=5'b10001; 5:glyph_row=5'b10001;
                    6:glyph_row=5'b01110; default:glyph_row=0;
                endcase
                "Y": case(row)
                    0:glyph_row=5'b10001; 1:glyph_row=5'b10001;
                    2:glyph_row=5'b01010; 3:glyph_row=5'b00100;
                    4:glyph_row=5'b00100; 5:glyph_row=5'b00100;
                    6:glyph_row=5'b00100; default:glyph_row=0;
                endcase
                default: glyph_row=5'b00000;
            endcase
        end
    endfunction

    // Separate fixed-string character functions. Spaces intentionally return
    // ASCII 0x20, whose glyph is blank.
    function [7:0] start_string_char;
        input [4:0] idx;
        begin
            case(idx)
                0:start_string_char="P"; 1:start_string_char="R";
                2:start_string_char="E"; 3:start_string_char="S";
                4:start_string_char="S"; 5:start_string_char=" ";
                6:start_string_char="Y"; 7:start_string_char=" ";
                8:start_string_char="T"; 9:start_string_char="O";
                10:start_string_char=" "; 11:start_string_char="S";
                12:start_string_char="T"; 13:start_string_char="A";
                14:start_string_char="R"; 15:start_string_char="T";
                default:start_string_char=" ";
            endcase
        end
    endfunction

    function [7:0] died_string_char;
        input [3:0] idx;
        begin
            case(idx)
                0:died_string_char="Y"; 1:died_string_char="O";
                2:died_string_char="U"; 3:died_string_char=" ";
                4:died_string_char="D"; 5:died_string_char="I";
                6:died_string_char="E"; 7:died_string_char="D";
                default:died_string_char=" ";
            endcase
        end
    endfunction

    function [7:0] restart_string_char;
        input [4:0] idx;
        begin
            case(idx)
                0:restart_string_char="P"; 1:restart_string_char="R";
                2:restart_string_char="E"; 3:restart_string_char="S";
                4:restart_string_char="S"; 5:restart_string_char=" ";
                6:restart_string_char="Y"; 7:restart_string_char=" ";
                8:restart_string_char="T"; 9:restart_string_char="O";
                10:restart_string_char=" "; 11:restart_string_char="R";
                12:restart_string_char="E"; 13:restart_string_char="S";
                14:restart_string_char="T"; 15:restart_string_char="A";
                16:restart_string_char="R"; 17:restart_string_char="T";
                default:restart_string_char=" ";
            endcase
        end
    endfunction

    reg [9:0] lx;
    reg [9:0] ly;
    reg [6:0] cell_x;
    reg [4:0] char_index;
    reg [2:0] glyph_col;
    reg [2:0] glyph_row_index;
    reg [7:0] selected_char;
    reg [4:0] selected_row;
    reg       inside_text;
    reg       selected_red;

    // x logical cell / 6. For the used range (0..107), floor(43*x/256)
    // exactly equals floor(x/6). Constant 43 is shift/add friendly.
    reg [14:0] char_mult;

    always @(*) begin
        text_pixel = 1'b0;
        red_pixel = 1'b0;

        lx = 10'd0;
        ly = 10'd0;
        cell_x = 7'd0;
        char_index = 5'd0;
        glyph_col = 3'd0;
        glyph_row_index = 3'd0;
        selected_char = " ";
        selected_row = 5'b00000;
        inside_text = 1'b0;
        selected_red = 1'b0;
        char_mult = 15'd0;

        // ------------------------------------------------------------
        // START: PRESS Y TO START
        // 16 chars * 24 pixels = 384 px, centered -> X=128.
        // ------------------------------------------------------------
        if (show_start &&
            (pixel_x >= 10'd128) && (pixel_x < 10'd512) &&
            (pixel_y >= 10'd226) && (pixel_y < 10'd254)) begin

            lx = pixel_x - 10'd128;
            ly = pixel_y - 10'd226;
            cell_x = lx[9:2];

            char_mult = (cell_x << 5) + (cell_x << 3) +
                        (cell_x << 1) + cell_x;
            char_index = char_mult[14:8];
            glyph_col = cell_x - ((char_index << 2) + (char_index << 1));
            glyph_row_index = ly[4:2];

            if ((char_index < 5'd16) && (glyph_col < 3'd5) &&
                (glyph_row_index < 3'd7)) begin
                selected_char = start_string_char(char_index);
                inside_text = 1'b1;
                selected_red = 1'b0;
            end
        end

        // ------------------------------------------------------------
        // DEAD title: YOU DIED
        // 8 chars * 24 = 192 px, centered -> X=224.
        // ------------------------------------------------------------
        else if (show_dead &&
            (pixel_x >= 10'd224) && (pixel_x < 10'd416) &&
            (pixel_y >= 10'd190) && (pixel_y < 10'd218)) begin

            lx = pixel_x - 10'd224;
            ly = pixel_y - 10'd190;
            cell_x = lx[9:2];

            char_mult = (cell_x << 5) + (cell_x << 3) +
                        (cell_x << 1) + cell_x;
            char_index = char_mult[14:8];
            glyph_col = cell_x - ((char_index << 2) + (char_index << 1));
            glyph_row_index = ly[4:2];

            if ((char_index < 5'd8) && (glyph_col < 3'd5) &&
                (glyph_row_index < 3'd7)) begin
                selected_char = died_string_char(char_index[3:0]);
                inside_text = 1'b1;
                selected_red = 1'b1;
            end
        end

        // ------------------------------------------------------------
        // DEAD prompt: PRESS Y TO RESTART
        // 18 chars * 24 = 432 px, centered -> X=104.
        // ------------------------------------------------------------
        else if (show_dead &&
            (pixel_x >= 10'd104) && (pixel_x < 10'd536) &&
            (pixel_y >= 10'd250) && (pixel_y < 10'd278)) begin

            lx = pixel_x - 10'd104;
            ly = pixel_y - 10'd250;
            cell_x = lx[9:2];

            char_mult = (cell_x << 5) + (cell_x << 3) +
                        (cell_x << 1) + cell_x;
            char_index = char_mult[14:8];
            glyph_col = cell_x - ((char_index << 2) + (char_index << 1));
            glyph_row_index = ly[4:2];

            if ((char_index < 5'd18) && (glyph_col < 3'd5) &&
                (glyph_row_index < 3'd7)) begin
                selected_char = restart_string_char(char_index);
                inside_text = 1'b1;
                selected_red = 1'b0;
            end
        end

        selected_row = glyph_row(selected_char, glyph_row_index);

        if (inside_text) begin
            case(glyph_col)
                0:text_pixel = selected_row[4];
                1:text_pixel = selected_row[3];
                2:text_pixel = selected_row[2];
                3:text_pixel = selected_row[1];
                default:text_pixel = selected_row[0];
            endcase

            if (text_pixel)
                red_pixel = selected_red;
        end
    end
endmodule


// ============================================================================
// PAUSE BUTTON CONTROLLER
// Basys 3 T17 / BTNR, active high.
//
// Debounce: ~20 ms @ 100 MHz.
// Each clean rising edge toggles pause_active.
// ============================================================================
module pause_button_controller (
    input  wire clk_100mhz,
    input  wire reset,
    input  wire frame_tick,
    input  wire button_in,
    output reg  pause_active
);
    // LUT-optimized T17 pause input:
    // synchronize at 100 MHz, then sample once per VGA frame (~60 Hz).
    // A press toggles once; release re-arms the next press.
    reg button_meta;
    reg button_sync;
    reg button_held;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            button_meta <= 1'b0;
            button_sync <= 1'b0;
        end
        else begin
            button_meta <= button_in;
            button_sync <= button_meta;
        end
    end

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            button_held <= 1'b0;
            pause_active <= 1'b0;
        end
        else if (frame_tick) begin
            if (button_sync) begin
                if (!button_held) begin
                    pause_active <= ~pause_active;
                    button_held <= 1'b1;
                end
            end
            else begin
                button_held <= 1'b0;
            end
        end
    end
endmodule


// ============================================================================
// CENTER-SCREEN "PAUSE" WORD
// 5x7 block font, scale 6 -> 174 x 42 pixels centered at 640x480.
// Display only.
// ============================================================================
module pause_word_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire       pause_active,
    output reg        pause_pixel
);
    localparam [9:0] START_X = 10'd233;
    localparam [9:0] START_Y = 10'd219;

    reg [2:0] char_index;
    reg [2:0] glyph_row_index;
    reg [2:0] glyph_col_index;
    reg       inside_char;
    reg [4:0] glyph_bits;
    reg [9:0] local_x;
    reg [9:0] local_y;

    // Return one 5-pixel row. bit[4] = left-most column.
    function [4:0] pause_glyph_row;
        input [2:0] ch;
        input [2:0] row;
        begin
            pause_glyph_row = 5'b00000;
            case (ch)
                // P
                3'd0: case (row)
                    0: pause_glyph_row=5'b11110;
                    1: pause_glyph_row=5'b10001;
                    2: pause_glyph_row=5'b10001;
                    3: pause_glyph_row=5'b11110;
                    4: pause_glyph_row=5'b10000;
                    5: pause_glyph_row=5'b10000;
                    6: pause_glyph_row=5'b10000;
                    default: pause_glyph_row=0;
                endcase
                // A
                3'd1: case (row)
                    0: pause_glyph_row=5'b01110;
                    1: pause_glyph_row=5'b10001;
                    2: pause_glyph_row=5'b10001;
                    3: pause_glyph_row=5'b11111;
                    4: pause_glyph_row=5'b10001;
                    5: pause_glyph_row=5'b10001;
                    6: pause_glyph_row=5'b10001;
                    default: pause_glyph_row=0;
                endcase
                // U
                3'd2: case (row)
                    0,1,2,3,4,5: pause_glyph_row=5'b10001;
                    6: pause_glyph_row=5'b01110;
                    default: pause_glyph_row=0;
                endcase
                // S
                3'd3: case (row)
                    0: pause_glyph_row=5'b01111;
                    1: pause_glyph_row=5'b10000;
                    2: pause_glyph_row=5'b10000;
                    3: pause_glyph_row=5'b01110;
                    4: pause_glyph_row=5'b00001;
                    5: pause_glyph_row=5'b00001;
                    6: pause_glyph_row=5'b11110;
                    default: pause_glyph_row=0;
                endcase
                // E
                3'd4: case (row)
                    0: pause_glyph_row=5'b11111;
                    1: pause_glyph_row=5'b10000;
                    2: pause_glyph_row=5'b10000;
                    3: pause_glyph_row=5'b11110;
                    4: pause_glyph_row=5'b10000;
                    5: pause_glyph_row=5'b10000;
                    6: pause_glyph_row=5'b11111;
                    default: pause_glyph_row=0;
                endcase
                default: pause_glyph_row=5'b00000;
            endcase
        end
    endfunction

    always @(*) begin
        pause_pixel = 1'b0;
        char_index = 3'd0;
        glyph_row_index = 3'd0;
        glyph_col_index = 3'd0;
        inside_char = 1'b0;
        glyph_bits = 5'b00000;
        local_x = 10'd0;
        local_y = 10'd0;

        if (pause_active &&
            (pixel_x >= START_X) && (pixel_x < START_X + 10'd174) &&
            (pixel_y >= START_Y) && (pixel_y < START_Y + 10'd42)) begin

            local_x = pixel_x - START_X;
            local_y = pixel_y - START_Y;

            // Character cells are 36 px wide: 30 px glyph + 6 px gap.
            if (local_x < 10'd30) begin
                char_index = 3'd0; inside_char = 1'b1; local_x = local_x;
            end else if ((local_x >= 10'd36) && (local_x < 10'd66)) begin
                char_index = 3'd1; inside_char = 1'b1; local_x = local_x - 10'd36;
            end else if ((local_x >= 10'd72) && (local_x < 10'd102)) begin
                char_index = 3'd2; inside_char = 1'b1; local_x = local_x - 10'd72;
            end else if ((local_x >= 10'd108) && (local_x < 10'd138)) begin
                char_index = 3'd3; inside_char = 1'b1; local_x = local_x - 10'd108;
            end else if ((local_x >= 10'd144) && (local_x < 10'd174)) begin
                char_index = 3'd4; inside_char = 1'b1; local_x = local_x - 10'd144;
            end

            if (local_y < 6) glyph_row_index=0;
            else if (local_y < 12) glyph_row_index=1;
            else if (local_y < 18) glyph_row_index=2;
            else if (local_y < 24) glyph_row_index=3;
            else if (local_y < 30) glyph_row_index=4;
            else if (local_y < 36) glyph_row_index=5;
            else glyph_row_index=6;

            if (local_x < 6) glyph_col_index=0;
            else if (local_x < 12) glyph_col_index=1;
            else if (local_x < 18) glyph_col_index=2;
            else if (local_x < 24) glyph_col_index=3;
            else glyph_col_index=4;

            glyph_bits = pause_glyph_row(char_index, glyph_row_index);

            if (inside_char)
                case (glyph_col_index)
                    0: pause_pixel = glyph_bits[4];
                    1: pause_pixel = glyph_bits[3];
                    2: pause_pixel = glyph_bits[2];
                    3: pause_pixel = glyph_bits[1];
                    default: pause_pixel = glyph_bits[0];
                endcase
        end
    end
endmodule


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


// ============================================================================
// GAME STATE / TARGET RESPAWN / SCORE
// ============================================================================
module game_controller (
    input  wire              clk_100mhz,
    input  wire              reset,
    input  wire              frame_tick,
    input  wire              left_click_pulse,
    input  wire              target_crosshair_hit,
    input  wire              speed_selector_hit,
    input  wire              bots_selector_hit,
    input  wire              moving_selector_hit,

    output reg signed [15:0] target_x,
    output reg signed [15:0] target_y,
    output reg signed [15:0] target_z,
    output reg               target_active,
    output reg               target_half_size,
    output reg [1:0]         current_mode,

    output reg [6:0]         display_left,
    output reg [6:0]         display_right,
    output reg               display_enable,
    output reg               main_target_destroy_pulse,
    output reg               target_appear_pulse
);

    localparam [1:0] MODE_FREE   = 2'd0;
    localparam [1:0] MODE_SPEED  = 2'd1;
    localparam [1:0] MODE_99BOTS = 2'd2;
    localparam [1:0] MODE_MOVING = 2'd3;

    localparam signed [15:0] FIXED_TARGET_Y = 16'sd96;
    localparam signed [15:0] TARGET_WALL_Z  = 16'sd500;

    // Moving target travels within +/- one 64-unit room block of a RANDOM
    // spawn origin. The origin itself is restricted to -256..+255, so the
    // whole motion window remains safely inside the +/-384 side walls.
    localparam signed [15:0] MOVING_RADIUS = 16'sd64;
    localparam signed [15:0] MOVING_SPEED  = 16'sd2;

    reg [15:0] lfsr;
    wire feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];

    // Speed Flick
    reg [5:0] speed_targets_left;
    reg [6:0] speed_hits;
    reg [5:0] speed_frame_count;
    reg       speed_initial_wait;

    // 99 Bots
    reg [6:0] bots_elapsed_seconds;
    reg [6:0] bots_hits;
    reg [5:0] bots_frame_count;

    // Moving Target
    reg signed [15:0] moving_origin_x;
    reg signed [15:0] moving_destination_x;
    reg [5:0]         moving_wait_frames;
    reg [7:0]         move_right_threshold;
    reg [7:0]         move_available_distance;
    reg [15:0]        move_distance_product;
    reg [7:0]         move_distance;

    wire signed [15:0] moving_min_x = moving_origin_x - MOVING_RADIUS;
    wire signed [15:0] moving_max_x = moving_origin_x + MOVING_RADIUS;

    wire selector_any_hit =
        speed_selector_hit || bots_selector_hit || moving_selector_hit;

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------
    function signed [15:0] random_target_x;
        input [15:0] r;
        begin
            // -256 .. +255, safely inside the front wall width.
            random_target_x = $signed({1'b0, r[8:0]}) - 16'sd256;
        end
    endfunction

    function [5:0] uniform_move_wait;
        input [7:0] r;
        reg [13:0] scaled;
        begin
            // Uniform dwell from 6..30 frames = about 0.10..0.50 s @ 60 Hz.
            // 25 equally possible frame counts.
            scaled = r * 8'd25;
            uniform_move_wait = 6'd6 + (scaled >> 8);
            if (uniform_move_wait > 6'd30)
                uniform_move_wait = 6'd30;
        end
    endfunction

    always @(*) begin
        // Center-restoring probability approximates a bell/Gaussian tendency.
        if (target_x <= -16'sd48)
            move_right_threshold = 8'd205; // ~80% right
        else if (target_x <= -16'sd16)
            move_right_threshold = 8'd166; // ~65% right
        else if (target_x < 16'sd16)
            move_right_threshold = 8'd128; // 50/50 around center
        else if (target_x < 16'sd48)
            move_right_threshold = 8'd90;  // ~35% right
        else
            move_right_threshold = 8'd51;  // ~20% right

        if (lfsr[7:0] < move_right_threshold) begin
            if (target_x >= moving_max_x)
                move_available_distance = 8'd1;
            else
                move_available_distance = moving_max_x - target_x;
        end else begin
            if (target_x <= moving_min_x)
                move_available_distance = 8'd1;
            else
                move_available_distance = target_x - moving_min_x;
        end

        // Uniform-ish distance in [1, available] using multiply/shift.
        move_distance_product = lfsr[15:8] * move_available_distance;
        move_distance = 8'd1 + (move_distance_product >> 8);
        if (move_distance > move_available_distance)
            move_distance = move_available_distance;
    end

    // ------------------------------------------------------------------------
    // Main game state machine
    // ------------------------------------------------------------------------
    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            lfsr <= 16'hACE1;

            current_mode <= MODE_FREE;
            target_x <= 16'sd0;
            target_y <= 16'sd128;
            target_z <= TARGET_WALL_Z;
            target_active <= 1'b1;
            target_half_size <= 1'b0;

            display_left <= 7'd0;
            display_right <= 7'd0;
            display_enable <= 1'b0;

            main_target_destroy_pulse <= 1'b0;
            target_appear_pulse <= 1'b0;

            speed_targets_left <= 6'd30;
            speed_hits <= 7'd0;
            speed_frame_count <= 6'd0;
            speed_initial_wait <= 1'b0;

            bots_elapsed_seconds <= 7'd0;
            bots_hits <= 7'd0;
            bots_frame_count <= 6'd0;

            moving_origin_x <= 16'sd0;
            moving_destination_x <= 16'sd0;
            moving_wait_frames <= 6'd0;
        end else begin
            main_target_destroy_pulse <= 1'b0;
            target_appear_pulse <= 1'b0;

            if (frame_tick)
                lfsr <= {lfsr[14:0], feedback};

            // ================================================================
            // MODE SELECTOR CLICKS HAVE HIGHEST PRIORITY
            // ================================================================
            if (left_click_pulse && selector_any_hit) begin
                if (current_mode != MODE_FREE) begin
                    // Any selector click while a mode is running = cancel to
                    // Free Practice. Retained Speed/99 display is untouched.
                    current_mode <= MODE_FREE;
                    target_half_size <= 1'b0;
                    target_active <= 1'b1;
                    target_x <= random_target_x(lfsr);
                    target_y <= 16'sd72 + {9'd0, lfsr[6:0]};
                    target_z <= TARGET_WALL_Z;
                end else if (speed_selector_hit) begin
                    // --------------------------------------------------------
                    // START SPEED FLICK
                    // --------------------------------------------------------
                    current_mode <= MODE_SPEED;
                    target_half_size <= 1'b1;
                    target_active <= 1'b0; // first target appears after 1 second
                    target_x <= random_target_x(lfsr);
                    target_y <= FIXED_TARGET_Y;
                    target_z <= TARGET_WALL_Z;

                    speed_targets_left <= 6'd30;
                    speed_hits <= 7'd0;
                    speed_frame_count <= 6'd0;
                    speed_initial_wait <= 1'b1;

                    display_left <= 7'd30;
                    display_right <= 7'd0;
                    display_enable <= 1'b1;
                end else if (bots_selector_hit) begin
                    // --------------------------------------------------------
                    // START 99 BOTS
                    // --------------------------------------------------------
                    current_mode <= MODE_99BOTS;
                    target_half_size <= 1'b1;
                    target_active <= 1'b0; // first bot after ~1 second
                    target_x <= random_target_x(lfsr);
                    target_y <= FIXED_TARGET_Y;
                    target_z <= TARGET_WALL_Z;

                    bots_elapsed_seconds <= 7'd0;
                    bots_hits <= 7'd0;
                    bots_frame_count <= 6'd0;

                    display_left <= 7'd0;
                    display_right <= 7'd0;
                    display_enable <= 1'b1;
                end else if (moving_selector_hit) begin
                    // --------------------------------------------------------
                    // START MOVING TARGET
                    // --------------------------------------------------------
                    current_mode <= MODE_MOVING;
                    target_half_size <= 1'b1;
                    target_active <= 1'b1;

                    // Random free-practice-like origin, but safely inset:
                    // X origin is -256..+255, leaving >=64 units on both sides
                    // for the one-block movement radius.
                    target_x <= random_target_x(lfsr);
                    target_y <= 16'sd72 + {9'd0, lfsr[6:0]};
                    target_z <= TARGET_WALL_Z;

                    moving_origin_x <= random_target_x(lfsr);
                    moving_destination_x <= random_target_x(lfsr);
                    moving_wait_frames <= uniform_move_wait(lfsr[7:0]);

                    // Moving mode has no score display. Choosing it counts as
                    // choosing another non-free mode, so old retained results
                    // are no longer displayed.
                    display_enable <= 1'b0;
                end
            end else begin
                // ============================================================
                // MAIN TARGET HIT
                // ============================================================
                if (left_click_pulse && target_crosshair_hit && target_active) begin
                    main_target_destroy_pulse <= 1'b1;

                    case (current_mode)
                        MODE_FREE: begin
                            target_x <= random_target_x(lfsr);
                            target_y <= 16'sd72 + {9'd0, lfsr[6:0]};
                            target_z <= TARGET_WALL_Z;
                        end

                        MODE_SPEED: begin
                            if (speed_hits < 7'd99) begin
                                speed_hits <= speed_hits + 7'd1;
                                display_right <= speed_hits + 7'd1;
                            end
                            // Destroyed target remains gone until next 1 s slot.
                            target_active <= 1'b0;
                        end

                        MODE_99BOTS: begin
                            if (bots_hits < 7'd99) begin
                                bots_hits <= bots_hits + 7'd1;
                                display_right <= bots_hits + 7'd1;

                                if (bots_hits == 7'd98) begin
                                    // 99th bot destroyed: finish immediately.
                                    // Returning to Free Practice freezes the timer
                                    // because MODE_99BOTS timing no longer runs.
                                    // The final timer + score remain on 7-seg.
                                    current_mode <= MODE_FREE;
                                    target_half_size <= 1'b0;
                                    target_active <= 1'b1;
                                    target_x <= random_target_x(lfsr);
                                    target_y <= 16'sd72 + {9'd0, lfsr[6:0]};
                                    target_z <= TARGET_WALL_Z;
                                end else begin
                                    // Next bot appears immediately and stays
                                    // until destroyed.
                                    target_x <= random_target_x({lfsr[7:0], lfsr[15:8]});
                                    target_y <= FIXED_TARGET_Y;
                                    target_z <= TARGET_WALL_Z;
                                    target_active <= 1'b1;
                                    target_appear_pulse <= 1'b1;
                                end
                            end
                        end

                        MODE_MOVING: begin
                            // Like Free Practice: successful shot respawns at a
                            // new random safe origin. It then waits a uniform
                            // 0.1..0.5 s before beginning constant-speed motion.
                            target_x <= random_target_x({lfsr[7:0], lfsr[15:8]});
                            target_y <= 16'sd72 + {9'd0, lfsr[6:0]};
                            target_z <= TARGET_WALL_Z;

                            moving_origin_x <= random_target_x({lfsr[7:0], lfsr[15:8]});
                            moving_destination_x <= random_target_x({lfsr[7:0], lfsr[15:8]});
                            moving_wait_frames <= uniform_move_wait(lfsr[15:8]);
                        end
                    endcase
                end else if (frame_tick) begin
                    // ========================================================
                    // 60 Hz MODE TIMING / MOVEMENT
                    // ========================================================
                    case (current_mode)

                        MODE_SPEED: begin
                            if (speed_initial_wait) begin
                                // Valorant-like start delay: wait 1 full second
                                // before the first of the 30 target slots.
                                target_active <= 1'b0;

                                if (speed_frame_count == 6'd59) begin
                                    speed_frame_count <= 6'd0;
                                    speed_initial_wait <= 1'b0;

                                    target_x <= random_target_x(lfsr);
                                    target_y <= FIXED_TARGET_Y;
                                    target_z <= TARGET_WALL_Z;
                                    target_active <= 1'b1;
                                    target_appear_pulse <= 1'b1;
                                end else begin
                                    speed_frame_count <= speed_frame_count + 6'd1;
                                end
                            end else begin
                                // One target per ~1 second slot, visible for the
                                // first ~0.5 second (30 of 60 frames).
                                if (speed_frame_count == 6'd29)
                                    target_active <= 1'b0;

                                if (speed_frame_count == 6'd59) begin
                                    speed_frame_count <= 6'd0;

                                    if (speed_targets_left > 6'd1) begin
                                        speed_targets_left <= speed_targets_left - 6'd1;
                                        display_left <= speed_targets_left - 6'd1;

                                        target_x <= random_target_x({lfsr[8:0], lfsr[15:9]});
                                        target_y <= FIXED_TARGET_Y;
                                        target_z <= TARGET_WALL_Z;
                                        target_active <= 1'b1;
                                        target_appear_pulse <= 1'b1;
                                    end else begin
                                        // All 30 target slots finished -> Free Practice.
                                        speed_targets_left <= 6'd0;
                                        display_left <= 7'd0;
                                        current_mode <= MODE_FREE;
                                        target_half_size <= 1'b0;
                                        target_active <= 1'b1;
                                        target_x <= random_target_x(lfsr);
                                        target_y <= 16'sd72 + {9'd0, lfsr[6:0]};
                                        target_z <= TARGET_WALL_Z;
                                        // display_enable/result intentionally retained.
                                    end
                                end else begin
                                    speed_frame_count <= speed_frame_count + 6'd1;
                                end
                            end
                        end

                        MODE_99BOTS: begin
                            if (bots_frame_count == 6'd59) begin
                                bots_frame_count <= 6'd0;

                                if (bots_elapsed_seconds < 7'd100) begin
                                    bots_elapsed_seconds <= bots_elapsed_seconds + 7'd1;

                                    // Two-digit display saturates at 99 even
                                    // though the state machine ends at 100 s.
                                    if (bots_elapsed_seconds < 7'd99)
                                        display_left <= bots_elapsed_seconds + 7'd1;
                                    else
                                        display_left <= 7'd99;

                                    // First bot appears after ~1 second.
                                    if (bots_elapsed_seconds == 7'd0 && bots_hits < 7'd99) begin
                                        target_x <= random_target_x(lfsr);
                                        target_y <= FIXED_TARGET_Y;
                                        target_z <= TARGET_WALL_Z;
                                        target_active <= 1'b1;
                                        target_appear_pulse <= 1'b1;
                                    end

                                    // At the 100-second boundary return to Free.
                                    if (bots_elapsed_seconds == 7'd99) begin
                                        current_mode <= MODE_FREE;
                                        target_half_size <= 1'b0;
                                        target_active <= 1'b1;
                                        target_x <= random_target_x(lfsr);
                                        target_y <= 16'sd72 + {9'd0, lfsr[6:0]};
                                        target_z <= TARGET_WALL_Z;
                                        // Frozen timer/score remain displayed.
                                    end
                                end
                            end else begin
                                bots_frame_count <= bots_frame_count + 6'd1;
                            end
                        end

                        MODE_MOVING: begin
                            // Small target moves at constant speed between
                            // destinations inside +/-1 block of its random origin.
                            // Each spawn/destination pauses uniformly 0.1..0.5 s.
                            if (moving_wait_frames != 6'd0) begin
                                moving_wait_frames <= moving_wait_frames - 6'd1;
                            end else if (target_x < moving_destination_x) begin
                                if (target_x + MOVING_SPEED >= moving_destination_x) begin
                                    target_x <= moving_destination_x;
                                    moving_wait_frames <= uniform_move_wait(lfsr[7:0]);
                                end else begin
                                    target_x <= target_x + MOVING_SPEED;
                                end
                            end else if (target_x > moving_destination_x) begin
                                if (target_x - MOVING_SPEED <= moving_destination_x) begin
                                    target_x <= moving_destination_x;
                                    moving_wait_frames <= uniform_move_wait(lfsr[7:0]);
                                end else begin
                                    target_x <= target_x - MOVING_SPEED;
                                end
                            end else begin
                                // At destination and dwell is finished: choose a
                                // new side using center-biased probability, then
                                // choose uniform distance within that side's
                                // remaining one-block boundary.
                                if (lfsr[7:0] < move_right_threshold) begin
                                    if (target_x >= moving_max_x)
                                        moving_destination_x <= target_x - 16'sd1;
                                    else if (target_x + $signed({8'd0, move_distance}) > moving_max_x)
                                        moving_destination_x <= moving_max_x;
                                    else
                                        moving_destination_x <= target_x + $signed({8'd0, move_distance});
                                end else begin
                                    if (target_x <= moving_min_x)
                                        moving_destination_x <= target_x + 16'sd1;
                                    else if (target_x - $signed({8'd0, move_distance}) < moving_min_x)
                                        moving_destination_x <= moving_min_x;
                                    else
                                        moving_destination_x <= target_x - $signed({8'd0, move_distance});
                                end
                            end
                        end

                        default: begin
                            // Free Practice has no automatic timer behavior.
                        end
                    endcase
                end
            end
        end
    end

endmodule



// ============================================================================
// LIGHTWEIGHT FREE-PRACTICE TARGET CONTROLLER
//
// Intentionally tiny:
//   - one 16-bit LFSR
//   - target X/Y/Z registers
//   - respawn on successful shot
//
// This is the type of control architecture we will use for Zombies:
// only hardware needed by the current game, no legacy Aimlabs modes.
// ============================================================================
module lightweight_target_controller (
    input  wire               clk_100mhz,
    input  wire               reset,
    input  wire               frame_tick,

    input  wire               shot_pulse,
    input  wire               crosshair_hit,

    output reg signed [15:0]  target_x,
    output reg signed [15:0]  target_y,
    output reg signed [15:0]  target_z,

    output reg                target_hit_pulse
);

    reg [15:0] lfsr;

    wire feedback =
        lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];

    // Pure wiring/subtraction. No multiplier/divider.
    wire signed [15:0] random_x =
        $signed({1'b0, lfsr[8:0]}) - 16'sd256;

    // 72..199 world units.
    wire signed [15:0] random_y =
        16'sd72 + $signed({9'd0, lfsr[6:0]});

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            lfsr            <= 16'hACE1;

            target_x        <= 16'sd0;
            target_y        <= 16'sd128;
            target_z        <= 16'sd500;

            target_hit_pulse <= 1'b0;
        end
        else begin
            target_hit_pulse <= 1'b0;

            if (frame_tick)
                lfsr <= {lfsr[14:0], feedback};

            if (shot_pulse && crosshair_hit) begin
                target_x <= random_x;
                target_y <= random_y;
                target_z <= 16'sd500;

                target_hit_pulse <= 1'b1;

                // Advance once immediately so repeated fast hits do not reuse
                // exactly the same pseudo-random bits.
                lfsr <= {lfsr[14:0], feedback};
            end
        end
    end

endmodule



// ============================================================================
// TIMING-SAFE SINGLE ZOMBIE AI
//
// No display/projection signal is used here.
//
// Navigation refreshes at ~10 Hz.
// LOS checks are sequential: one map sample per 100 MHz clock.
// This avoids the long combinational path that broke V16G/V16H.
//
// Four main-room nodes:
//   N0 (-500,+500)       N1 (+500,+500)
//   N2 (-500,-500)       N3 (+500,-500)
//
// Navigation rule:
//   1) zombie -> player LOS clear?       chase player
//   2) otherwise player-nearest node.
//      zombie -> player node clear?      chase that node
//   3) otherwise                         chase zombie-nearest node
// ============================================================================

// ============================================================================
// V22 ROUND + POISSON SPAWN CONTROLLER
// ============================================================================
module zombies_round_spawn_controller (
    input  wire               clk_100mhz,
    input  wire               reset,
    input  wire               frame_tick,

    input  wire               door_ul_open,
    input  wire               door_ur_open,
    input  wire               door_ll_open,
    input  wire               door_lr_open,

    input  wire [7:0]         zombie_alive_mask,
    input  wire [7:0]         zombie_death_pulses,

    output reg  [6:0]         current_round,
    output reg  [6:0]         round_quota,
    output reg  [6:0]         round_spawned_count,
    output reg                round_grace_active,

    output reg                spawn_pulse,
    output reg  [2:0]         spawn_slot,
    output reg signed [15:0]  spawn_x,
    output reg signed [15:0]  spawn_z,

    output reg signed [15:0]  spawn_exit_x,
    output reg signed [15:0]  spawn_exit_z
);
    localparam [8:0] ROUND_GRACE_FRAMES = 9'd300; // 5 s @ ~60 Hz

    localparam signed [15:0] SPAWN_MAIN_LEFT_X   = -16'sd736;
    localparam signed [15:0] SPAWN_MAIN_LEFT_Z   =  16'sd0;
    localparam signed [15:0] SPAWN_MAIN_RIGHT_X  =  16'sd736;
    localparam signed [15:0] SPAWN_MAIN_RIGHT_Z  =  16'sd0;
    localparam signed [15:0] SPAWN_MAIN_BOTTOM_X =  16'sd0;
    localparam signed [15:0] SPAWN_MAIN_BOTTOM_Z = -16'sd736;
    localparam signed [15:0] SPAWN_UL_X = -16'sd1312;
    localparam signed [15:0] SPAWN_UL_Z =  16'sd768;
    localparam signed [15:0] SPAWN_UR_X =  16'sd1184;
    localparam signed [15:0] SPAWN_UR_Z =  16'sd704;
    localparam signed [15:0] SPAWN_LL_X = -16'sd640;
    localparam signed [15:0] SPAWN_LL_Z = -16'sd1056;
    localparam signed [15:0] SPAWN_LR_X =  16'sd640;
    localparam signed [15:0] SPAWN_LR_Z = -16'sd1056;

    // V24E safe exit nodes.
    // Each point lies beyond the spawn-room connector and inside the playable room.
    localparam signed [15:0] EXIT_MAIN_LEFT_X   = -16'sd560;
    localparam signed [15:0] EXIT_MAIN_LEFT_Z   =  16'sd0;
    localparam signed [15:0] EXIT_MAIN_RIGHT_X  =  16'sd560;
    localparam signed [15:0] EXIT_MAIN_RIGHT_Z  =  16'sd0;
    localparam signed [15:0] EXIT_MAIN_BOTTOM_X =  16'sd0;
    localparam signed [15:0] EXIT_MAIN_BOTTOM_Z = -16'sd560;

    localparam signed [15:0] EXIT_UL_X = -16'sd1140;
    localparam signed [15:0] EXIT_UL_Z =  16'sd768;
    localparam signed [15:0] EXIT_UR_X =  16'sd1020;
    localparam signed [15:0] EXIT_UR_Z =  16'sd704;
    localparam signed [15:0] EXIT_LL_X = -16'sd640;
    localparam signed [15:0] EXIT_LL_Z = -16'sd900;
    localparam signed [15:0] EXIT_LR_X =  16'sd640;
    localparam signed [15:0] EXIT_LR_Z = -16'sd900;

    reg [15:0] lfsr;
    wire lfsr_feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];

    reg [8:0] grace_counter;
    reg [8:0] spawn_wait_counter;

    wire any_alive = |zombie_alive_mask;
    wire [7:0] free_mask = ~zombie_alive_mask;
    wire any_free = |free_mask;

    function [6:0] quota_for_round;
        input [6:0] r;
        reg [7:0] temp;
        begin
            if (r <= 7'd20)
                quota_for_round = 7'd5 + r;       // R1=6, R20=25
            else if (r <= 7'd30) begin
                temp = 8'd25 + ((r - 7'd20) << 1); // R30=45
                quota_for_round = temp[6:0];
            end
            else
                quota_for_round = 7'd45;
        end
    endfunction

    // Inverse-exponential approximation. Uniform LFSR bins mapped to an
    // exponential-ish waiting-time tail -> Poisson-process arrivals.
    function [8:0] poisson_gap_frames;
        input [3:0] u;
        begin
            case (u)
                4'h0: poisson_gap_frames = 9'd8;
                4'h1: poisson_gap_frames = 9'd12;
                4'h2: poisson_gap_frames = 9'd16;
                4'h3: poisson_gap_frames = 9'd20;
                4'h4: poisson_gap_frames = 9'd26;
                4'h5: poisson_gap_frames = 9'd32;
                4'h6: poisson_gap_frames = 9'd39;
                4'h7: poisson_gap_frames = 9'd47;
                4'h8: poisson_gap_frames = 9'd56;
                4'h9: poisson_gap_frames = 9'd67;
                4'hA: poisson_gap_frames = 9'd80;
                4'hB: poisson_gap_frames = 9'd96;
                4'hC: poisson_gap_frames = 9'd116;
                4'hD: poisson_gap_frames = 9'd144;
                4'hE: poisson_gap_frames = 9'd184;
                default: poisson_gap_frames = 9'd240;
            endcase
        end
    endfunction

    // Wrap-around search from a random room candidate. Rooms 0..2 are always
    // eligible; 3..6 correspond UL/UR/LL/LR.
    reg [2:0] chosen_room;
    reg [2:0] candidate_room;
    integer k;
    reg found_room;

    function room_enabled;
        input [2:0] room_id;
        begin
            case (room_id)
                3'd0,3'd1,3'd2: room_enabled = 1'b1;
                3'd3: room_enabled = door_ul_open;
                3'd4: room_enabled = door_ur_open;
                3'd5: room_enabled = door_ll_open;
                3'd6: room_enabled = door_lr_open;
                default: room_enabled = 1'b0;
            endcase
        end
    endfunction

    always @(*) begin
        candidate_room = (lfsr[2:0] == 3'd7) ? 3'd0 : lfsr[2:0];
        chosen_room = 3'd0;
        found_room = 1'b0;
        for (k = 0; k < 7; k = k + 1) begin
            if (!found_room) begin
                if ((candidate_room + k) >= 7)
                    chosen_room = candidate_room + k - 7;
                else
                    chosen_room = candidate_room + k;
                if (room_enabled(chosen_room))
                    found_room = 1'b1;
            end
        end
    end

    reg [2:0] free_slot_choice;
    always @(*) begin
        casex (free_mask)
            8'bxxxxxxx1: free_slot_choice = 3'd0;
            8'bxxxxxx10: free_slot_choice = 3'd1;
            8'bxxxxx100: free_slot_choice = 3'd2;
            8'bxxxx1000: free_slot_choice = 3'd3;
            8'bxxx10000: free_slot_choice = 3'd4;
            8'bxx100000: free_slot_choice = 3'd5;
            8'bx1000000: free_slot_choice = 3'd6;
            8'b10000000: free_slot_choice = 3'd7;
            default:     free_slot_choice = 3'd0;
        endcase
    end

    task set_spawn_coordinates;
        input [2:0] room_id;
        begin
            case (room_id)
                3'd0: begin
                    spawn_x <= SPAWN_MAIN_LEFT_X;  spawn_z <= SPAWN_MAIN_LEFT_Z;
                    spawn_exit_x <= EXIT_MAIN_LEFT_X;  spawn_exit_z <= EXIT_MAIN_LEFT_Z;
                end
                3'd1: begin
                    spawn_x <= SPAWN_MAIN_RIGHT_X; spawn_z <= SPAWN_MAIN_RIGHT_Z;
                    spawn_exit_x <= EXIT_MAIN_RIGHT_X; spawn_exit_z <= EXIT_MAIN_RIGHT_Z;
                end
                3'd2: begin
                    spawn_x <= SPAWN_MAIN_BOTTOM_X; spawn_z <= SPAWN_MAIN_BOTTOM_Z;
                    spawn_exit_x <= EXIT_MAIN_BOTTOM_X; spawn_exit_z <= EXIT_MAIN_BOTTOM_Z;
                end
                3'd3: begin
                    spawn_x <= SPAWN_UL_X; spawn_z <= SPAWN_UL_Z;
                    spawn_exit_x <= EXIT_UL_X; spawn_exit_z <= EXIT_UL_Z;
                end
                3'd4: begin
                    spawn_x <= SPAWN_UR_X; spawn_z <= SPAWN_UR_Z;
                    spawn_exit_x <= EXIT_UR_X; spawn_exit_z <= EXIT_UR_Z;
                end
                3'd5: begin
                    spawn_x <= SPAWN_LL_X; spawn_z <= SPAWN_LL_Z;
                    spawn_exit_x <= EXIT_LL_X; spawn_exit_z <= EXIT_LL_Z;
                end
                default: begin
                    spawn_x <= SPAWN_LR_X; spawn_z <= SPAWN_LR_Z;
                    spawn_exit_x <= EXIT_LR_X; spawn_exit_z <= EXIT_LR_Z;
                end
            endcase
        end
    endtask

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            current_round <= 7'd1;
            round_quota <= 7'd6;
            round_spawned_count <= 7'd0;
            round_grace_active <= 1'b1;
            grace_counter <= 9'd0;
            spawn_wait_counter <= 9'd0;
            spawn_pulse <= 1'b0;
            spawn_slot <= 3'd0;
            spawn_x <= SPAWN_MAIN_LEFT_X;
            spawn_z <= SPAWN_MAIN_LEFT_Z;
            spawn_exit_x <= EXIT_MAIN_LEFT_X;
            spawn_exit_z <= EXIT_MAIN_LEFT_Z;
            lfsr <= 16'hA5C3;
        end
        else begin
            spawn_pulse <= 1'b0;

            if (frame_tick) begin
                lfsr <= {lfsr[14:0], lfsr_feedback};

                // Round complete only after quota has been spawned AND every
                // active zombie from that round has been killed.
                if ((round_spawned_count >= round_quota) && !any_alive) begin
                    if (current_round < 7'd99)
                        current_round <= current_round + 7'd1;

                    if (current_round < 7'd99)
                        round_quota <= quota_for_round(current_round + 7'd1);
                    else
                        round_quota <= quota_for_round(current_round);

                    round_spawned_count <= 7'd0;
                    round_grace_active <= 1'b1;
                    grace_counter <= 9'd0;
                    spawn_wait_counter <= 9'd0;
                end
                else if (round_grace_active) begin
                    if (grace_counter >= ROUND_GRACE_FRAMES - 1'b1) begin
                        round_grace_active <= 1'b0;
                        grace_counter <= grace_counter;
                        spawn_wait_counter <= 9'd0;
                    end
                    else begin
                        grace_counter <= grace_counter + 9'd1;
                    end
                end
                else if (round_spawned_count < round_quota) begin
                    if (spawn_wait_counter != 0) begin
                        spawn_wait_counter <= spawn_wait_counter - 9'd1;
                    end
                    else if (any_free) begin
                        spawn_slot <= free_slot_choice;
                        set_spawn_coordinates(chosen_room);
                        spawn_pulse <= 1'b1;
                        round_spawned_count <= round_spawned_count + 7'd1;
                        spawn_wait_counter <= poisson_gap_frames(lfsr[7:4]);
                    end
                end
            end
        end
    end
endmodule


// ============================================================================
// SHARED PLAYER HEALTH FOR MULTIPLE ZOMBIES
// ============================================================================
module zombie_player_health (
    input wire clk_100mhz,
    input wire reset,
    input wire frame_tick,
    input wire extra_hp_perk,
    input wire [7:0] melee_attempts,
    output reg [2:0] player_hp
);
    localparam [5:0] PLAYER_INVULN_FRAMES      = 6'd30;
    localparam [8:0] PLAYER_REGEN_DELAY_FRAMES = 9'd300;
    localparam [4:0] PLAYER_REGEN_STEP_FRAMES  = 5'd12;

    reg [5:0] invuln_counter;
    reg [8:0] regen_delay;
    reg [4:0] regen_step;
    reg       extra_hp_d;

    wire [2:0] player_max_hp =
        extra_hp_perk ? 3'd4 : 3'd3;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            player_hp <= 3'd3;
            invuln_counter <= 6'd0;
            regen_delay <= 9'd0;
            regen_step <= 5'd0;
            extra_hp_d <= 1'b0;
        end
        else begin
            extra_hp_d <= extra_hp_perk;

            // Buying the +1 HP perk grants the new point immediately.
            if (extra_hp_perk && !extra_hp_d &&
                (player_hp != 0) && (player_hp < 3'd4)) begin

                player_hp <= player_hp + 3'd1;
            end
            else if ((|melee_attempts) &&
                     (invuln_counter == 0) &&
                     (player_hp != 0)) begin

                player_hp <= player_hp - 3'd1;
                invuln_counter <= PLAYER_INVULN_FRAMES;
                regen_delay <= PLAYER_REGEN_DELAY_FRAMES;
                regen_step <= 5'd0;
            end
            else if (frame_tick) begin
                if (invuln_counter != 0)
                    invuln_counter <= invuln_counter - 6'd1;

                if ((player_hp != 0) &&
                    (player_hp < player_max_hp)) begin

                    if (regen_delay != 0) begin
                        regen_delay <= regen_delay - 9'd1;
                        regen_step <= 5'd0;
                    end
                    else if (regen_step >=
                             PLAYER_REGEN_STEP_FRAMES - 1'b1) begin

                        player_hp <= player_hp + 3'd1;
                        regen_step <= 5'd0;
                    end
                    else begin
                        regen_step <= regen_step + 5'd1;
                    end
                end
                else begin
                    regen_delay <= 9'd0;
                    regen_step <= 5'd0;
                end
            end
        end
    end
endmodule


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




// ============================================================================
// V22H SEQUENTIAL AIMED PISTOL HIT SELECTOR
//
// This module is intentionally staged:
//   IDLE  : accept click, snapshot wall depth
//   LOAD  : mux one zombie's already-registered projection into local regs
//   CHECK : test the crosshair against that local snapshot
//   FIRE  : emit one one-clock pulse for the nearest target
//
// Only ONE zombie is examined at a time. There is no eight-zombie combinational
// projection -> HP path.
//
// Hit silhouette exactly matches zombie_pill_pixel at crosshair (320,240):
//   body: |dy| <= r && |dx| <= r
//   lower cap: r < |dy| <= 2r && |dx| + (|dy|-r) <= r
// ============================================================================
module zombie_aim_hit_selector_seq (
    input  wire               clk_100mhz,
    input  wire               reset,
    input  wire               shot_pulse,

    input  wire               wall_valid,
    input  wire [15:0]        wall_depth,

    input  wire [7:0]         alive_mask,

    input  wire signed [11:0] z0_x, input wire signed [11:0] z0_y,
    input  wire [7:0]         z0_radius, input wire z0_visible, input wire [15:0] z0_depth,

    input  wire signed [11:0] z1_x, input wire signed [11:0] z1_y,
    input  wire [7:0]         z1_radius, input wire z1_visible, input wire [15:0] z1_depth,

    input  wire signed [11:0] z2_x, input wire signed [11:0] z2_y,
    input  wire [7:0]         z2_radius, input wire z2_visible, input wire [15:0] z2_depth,

    input  wire signed [11:0] z3_x, input wire signed [11:0] z3_y,
    input  wire [7:0]         z3_radius, input wire z3_visible, input wire [15:0] z3_depth,

    input  wire signed [11:0] z4_x, input wire signed [11:0] z4_y,
    input  wire [7:0]         z4_radius, input wire z4_visible, input wire [15:0] z4_depth,

    input  wire signed [11:0] z5_x, input wire signed [11:0] z5_y,
    input  wire [7:0]         z5_radius, input wire z5_visible, input wire [15:0] z5_depth,

    input  wire signed [11:0] z6_x, input wire signed [11:0] z6_y,
    input  wire [7:0]         z6_radius, input wire z6_visible, input wire [15:0] z6_depth,

    input  wire signed [11:0] z7_x, input wire signed [11:0] z7_y,
    input  wire [7:0]         z7_radius, input wire z7_visible, input wire [15:0] z7_depth,

    output reg  [7:0]         hit_onehot
);

    localparam [1:0]
        HT_IDLE  = 2'd0,
        HT_LOAD  = 2'd1,
        HT_CHECK = 2'd2,
        HT_FIRE  = 2'd3;

    reg [1:0] state;
    reg [2:0] slot_index;

    // Per-slot local snapshot. LOAD isolates the 8:1 mux from the CHECK logic.
    reg signed [11:0] slot_x_reg;
    reg signed [11:0] slot_y_reg;
    reg [7:0]         slot_radius_reg;
    reg               slot_visible_reg;
    reg               slot_alive_reg;
    reg [15:0]        slot_depth_reg;

    reg               wall_valid_snap;
    reg [15:0]        wall_depth_snap;

    reg               best_valid;
    reg [2:0]         best_slot;
    reg [15:0]        best_depth;

    // Combinational 8:1 selector used ONLY by HT_LOAD.
    reg signed [11:0] selected_x;
    reg signed [11:0] selected_y;
    reg [7:0]         selected_radius;
    reg               selected_visible;
    reg               selected_alive;
    reg [15:0]        selected_depth;

    always @(*) begin
        selected_x       = z0_x;
        selected_y       = z0_y;
        selected_radius  = z0_radius;
        selected_visible = z0_visible;
        selected_alive   = alive_mask[0];
        selected_depth   = z0_depth;

        case (slot_index)
            3'd0: begin
                selected_x=z0_x; selected_y=z0_y; selected_radius=z0_radius;
                selected_visible=z0_visible; selected_alive=alive_mask[0]; selected_depth=z0_depth;
            end
            3'd1: begin
                selected_x=z1_x; selected_y=z1_y; selected_radius=z1_radius;
                selected_visible=z1_visible; selected_alive=alive_mask[1]; selected_depth=z1_depth;
            end
            3'd2: begin
                selected_x=z2_x; selected_y=z2_y; selected_radius=z2_radius;
                selected_visible=z2_visible; selected_alive=alive_mask[2]; selected_depth=z2_depth;
            end
            3'd3: begin
                selected_x=z3_x; selected_y=z3_y; selected_radius=z3_radius;
                selected_visible=z3_visible; selected_alive=alive_mask[3]; selected_depth=z3_depth;
            end
            3'd4: begin
                selected_x=z4_x; selected_y=z4_y; selected_radius=z4_radius;
                selected_visible=z4_visible; selected_alive=alive_mask[4]; selected_depth=z4_depth;
            end
            3'd5: begin
                selected_x=z5_x; selected_y=z5_y; selected_radius=z5_radius;
                selected_visible=z5_visible; selected_alive=alive_mask[5]; selected_depth=z5_depth;
            end
            3'd6: begin
                selected_x=z6_x; selected_y=z6_y; selected_radius=z6_radius;
                selected_visible=z6_visible; selected_alive=alive_mask[6]; selected_depth=z6_depth;
            end
            default: begin
                selected_x=z7_x; selected_y=z7_y; selected_radius=z7_radius;
                selected_visible=z7_visible; selected_alive=alive_mask[7]; selected_depth=z7_depth;
            end
        endcase
    end

    // CHECK stage: exact pill test at crosshair center.
    wire signed [12:0] cross_dx =
        13'sd320 - $signed({slot_x_reg[11],slot_x_reg});

    wire signed [12:0] cross_dy =
        13'sd240 - $signed({slot_y_reg[11],slot_y_reg});

    wire [12:0] cross_ax = cross_dx[12] ? -cross_dx : cross_dx;
    wire [12:0] cross_ay = cross_dy[12] ? -cross_dy : cross_dy;
    wire [12:0] cross_r  = {5'd0,slot_radius_reg};
    wire [13:0] cross_2r = {5'd0,slot_radius_reg,1'b0};

    wire cross_body =
        (cross_ay <= cross_r) &&
        (cross_ax <= cross_r);

    wire [13:0] cap_offset =
        {1'b0,cross_ay} - {1'b0,cross_r};

    wire cross_cap =
        (cross_ay > cross_r) &&
        ({1'b0,cross_ay} <= cross_2r) &&
        (({1'b0,cross_ax} + cap_offset) <= {1'b0,cross_r});

    wire crosshair_inside_sprite = cross_body || cross_cap;

    // Match V22F wall occlusion tolerance.
    wire [16:0] wall_depth_tolerant =
        {1'b0,wall_depth_snap} + 17'd4;

    wire target_in_front_of_wall =
        !wall_valid_snap ||
        ({1'b0,slot_depth_reg} <= wall_depth_tolerant);

    wire slot_is_valid_target =
        slot_alive_reg &&
        slot_visible_reg &&
        crosshair_inside_sprite &&
        target_in_front_of_wall;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            state <= HT_IDLE;
            slot_index <= 3'd0;

            slot_x_reg <= 12'sd0;
            slot_y_reg <= 12'sd0;
            slot_radius_reg <= 8'd0;
            slot_visible_reg <= 1'b0;
            slot_alive_reg <= 1'b0;
            slot_depth_reg <= 16'hFFFF;

            wall_valid_snap <= 1'b0;
            wall_depth_snap <= 16'hFFFF;

            best_valid <= 1'b0;
            best_slot <= 3'd0;
            best_depth <= 16'hFFFF;

            hit_onehot <= 8'b00000000;
        end
        else begin
            // One-clock output by default.
            hit_onehot <= 8'b00000000;

            case (state)
                HT_IDLE: begin
                    if (shot_pulse) begin
                        wall_valid_snap <= wall_valid;
                        wall_depth_snap <= wall_depth;

                        slot_index <= 3'd0;
                        best_valid <= 1'b0;
                        best_slot <= 3'd0;
                        best_depth <= 16'hFFFF;

                        state <= HT_LOAD;
                    end
                end

                HT_LOAD: begin
                    slot_x_reg       <= selected_x;
                    slot_y_reg       <= selected_y;
                    slot_radius_reg  <= selected_radius;
                    slot_visible_reg <= selected_visible;
                    slot_alive_reg   <= selected_alive;
                    slot_depth_reg   <= selected_depth;

                    state <= HT_CHECK;
                end

                HT_CHECK: begin
                    if (slot_is_valid_target &&
                        (!best_valid || (slot_depth_reg < best_depth))) begin
                        best_valid <= 1'b1;
                        best_slot <= slot_index;
                        best_depth <= slot_depth_reg;
                    end

                    if (slot_index == 3'd7) begin
                        state <= HT_FIRE;
                    end
                    else begin
                        slot_index <= slot_index + 1'b1;
                        state <= HT_LOAD;
                    end
                end

                HT_FIRE: begin
                    if (best_valid)
                        hit_onehot <= (8'b00000001 << best_slot);

                    state <= HT_IDLE;
                end

                default: state <= HT_IDLE;
            endcase
        end
    end
endmodule


// ============================================================================
// V22D SHARED SMOOTH DISPLAY-ONLY ZOMBIE PROJECTION BANK
//
// IMPORTANT ARCHITECTURE RULE:
//   These screen coordinates are REGISTERED.
//   V22H may use them only through zombie_aim_hit_selector_seq, which stages
//   the hit test over multiple clocks before generating a damage pulse.
//   Never reconnect them directly/combinationally to zombie HP or AI.
//
// Why this exists:
//   The old projector used factors 8,4,2,1,1/2,1/4... based on large depth
//   buckets. Zombie X/Z moved every frame, but the displayed perspective only
//   changed at those thresholds, so walking toward the player appeared jumpy.
//
// V22D:
//   - one shared trig unit
//   - one shared signed multiplier
//   - processes eight zombies sequentially after each frame_tick
//   - smooth piecewise-linear Q8 perspective scale
//   - roughly 80 sequential clocks/frame (< 1 us at 100 MHz)
// ============================================================================
module zombie_projection_bank_smooth (
    input  wire               clk_100mhz,
    input  wire               reset,
    input  wire               frame_tick,

    input  wire signed [15:0] camera_x,
    input  wire signed [15:0] camera_y,
    input  wire signed [15:0] camera_z,
    input  wire        [7:0]  camera_yaw,
    input  wire signed [8:0]  camera_pitch,

    input  wire signed [15:0] z0_x, input wire signed [15:0] z0_z,
    input  wire signed [15:0] z1_x, input wire signed [15:0] z1_z,
    input  wire signed [15:0] z2_x, input wire signed [15:0] z2_z,
    input  wire signed [15:0] z3_x, input wire signed [15:0] z3_z,
    input  wire signed [15:0] z4_x, input wire signed [15:0] z4_z,
    input  wire signed [15:0] z5_x, input wire signed [15:0] z5_z,
    input  wire signed [15:0] z6_x, input wire signed [15:0] z6_z,
    input  wire signed [15:0] z7_x, input wire signed [15:0] z7_z,

    output reg signed [11:0] z0_screen_x, output reg signed [11:0] z0_screen_y,
    output reg [7:0] z0_radius, output reg z0_visible, output reg [15:0] z0_depth,

    output reg signed [11:0] z1_screen_x, output reg signed [11:0] z1_screen_y,
    output reg [7:0] z1_radius, output reg z1_visible, output reg [15:0] z1_depth,

    output reg signed [11:0] z2_screen_x, output reg signed [11:0] z2_screen_y,
    output reg [7:0] z2_radius, output reg z2_visible, output reg [15:0] z2_depth,

    output reg signed [11:0] z3_screen_x, output reg signed [11:0] z3_screen_y,
    output reg [7:0] z3_radius, output reg z3_visible, output reg [15:0] z3_depth,

    output reg signed [11:0] z4_screen_x, output reg signed [11:0] z4_screen_y,
    output reg [7:0] z4_radius, output reg z4_visible, output reg [15:0] z4_depth,

    output reg signed [11:0] z5_screen_x, output reg signed [11:0] z5_screen_y,
    output reg [7:0] z5_radius, output reg z5_visible, output reg [15:0] z5_depth,

    output reg signed [11:0] z6_screen_x, output reg signed [11:0] z6_screen_y,
    output reg [7:0] z6_radius, output reg z6_visible, output reg [15:0] z6_depth,

    output reg signed [11:0] z7_screen_x, output reg signed [11:0] z7_screen_y,
    output reg [7:0] z7_radius, output reg z7_visible, output reg [15:0] z7_depth
);

    // ------------------------------------------------------------------------
    // Shared camera snapshot.
    // ------------------------------------------------------------------------
    reg signed [15:0] cam_x_snap;
    reg signed [15:0] cam_y_snap;
    reg signed [15:0] cam_z_snap;
    reg        [7:0]  yaw_snap;
    reg signed [8:0]  pitch_snap;

    wire signed [8:0] shared_sin;
    wire signed [8:0] shared_cos;
    trig_q17 shared_trig (
        .angle(yaw_snap),
        .sin_value(shared_sin),
        .cos_value(shared_cos)
    );

    // ------------------------------------------------------------------------
    // Pitch/horizon lookup. Shared once for all eight zombies.
    // ------------------------------------------------------------------------
    function signed [11:0] pitch_shift_lut;
        input [5:0] m;
        begin
            case(m)
                0:pitch_shift_lut=0;1:pitch_shift_lut=6;2:pitch_shift_lut=13;3:pitch_shift_lut=19;
                4:pitch_shift_lut=25;5:pitch_shift_lut=32;6:pitch_shift_lut=38;7:pitch_shift_lut=44;
                8:pitch_shift_lut=51;9:pitch_shift_lut=57;10:pitch_shift_lut=64;11:pitch_shift_lut=71;
                12:pitch_shift_lut=78;13:pitch_shift_lut=85;14:pitch_shift_lut=92;15:pitch_shift_lut=99;
                16:pitch_shift_lut=106;17:pitch_shift_lut=113;18:pitch_shift_lut=121;19:pitch_shift_lut=129;
                20:pitch_shift_lut=137;21:pitch_shift_lut=145;22:pitch_shift_lut=153;23:pitch_shift_lut=162;
                24:pitch_shift_lut=171;25:pitch_shift_lut=180;26:pitch_shift_lut=190;27:pitch_shift_lut=200;
                28:pitch_shift_lut=210;29:pitch_shift_lut=221;30:pitch_shift_lut=232;31:pitch_shift_lut=244;
                32:pitch_shift_lut=256;33:pitch_shift_lut=269;34:pitch_shift_lut=282;35:pitch_shift_lut=297;
                36:pitch_shift_lut=312;37:pitch_shift_lut=328;38:pitch_shift_lut=345;39:pitch_shift_lut=363;
                40:pitch_shift_lut=383;41:pitch_shift_lut=404;default:pitch_shift_lut=427;
            endcase
        end
    endfunction

    function signed [11:0] horizon_from_pitch;
        input signed [8:0] p;
        reg [5:0] m;
        begin
            if (p < 0) begin
                if ((-p) > 9'sd42) m = 6'd42;
                else m = -p;
                horizon_from_pitch = 12'sd240 - pitch_shift_lut(m);
            end
            else begin
                if (p > 9'sd42) m = 6'd42;
                else m = p[5:0];
                horizon_from_pitch = 12'sd240 + pitch_shift_lut(m);
            end
        end
    endfunction

    reg signed [11:0] horizon_reg;

    // ------------------------------------------------------------------------
    // Smooth Q8 perspective scale.
    //
    // Ideal:
    //      scale_q8 ~= (256 / depth) * 256 = 65536/depth
    //
    // Instead of division or a large ROM, each range uses a linear expression
    // made only from shifts/adds. Values meet almost continuously at range
    // boundaries. Unlike the old power-of-two factors, scale changes gradually
    // as depth changes.
    // ------------------------------------------------------------------------
    function [15:0] smooth_scale_q8;
        input signed [18:0] depth_in;
        reg [18:0] d;
        reg signed [31:0] s;
        begin
            if (depth_in <= 0)
                d = 19'd1;
            else
                d = depth_in[18:0];

            if (d < 19'd24)
                s = 32'sd2752;
            else if (d < 19'd48)
                // ~= 4096 - 56*d
                s = 32'sd4096 - ($signed({1'b0,d}) <<< 6)
                               + ($signed({1'b0,d}) <<< 3);
            else if (d < 19'd96)
                // ~= 2048 - 14*d
                s = 32'sd2048 - ($signed({1'b0,d}) <<< 4)
                               + ($signed({1'b0,d}) <<< 1);
            else if (d < 19'd192)
                // ~= 1024 - 3.5*d
                s = 32'sd1024 - ($signed({1'b0,d}) <<< 2)
                               + ($signed({1'b0,d}) >>> 1);
            else if (d < 19'd384)
                // ~= 512 - 0.875*d
                s = 32'sd512 - $signed({1'b0,d})
                              + ($signed({1'b0,d}) >>> 3);
            else if (d < 19'd768)
                // ~= 256 - 0.21875*d
                s = 32'sd256 - ($signed({1'b0,d}) >>> 2)
                              + ($signed({1'b0,d}) >>> 5);
            else if (d < 19'd1536)
                // ~= 128 - 0.0546875*d
                s = 32'sd128 - ($signed({1'b0,d}) >>> 4)
                              + ($signed({1'b0,d}) >>> 7);
            else if (d < 19'd3072)
                // ~= 64 - 0.01367*d
                s = 32'sd64 - ($signed({1'b0,d}) >>> 6)
                             + ($signed({1'b0,d}) >>> 9);
            else
                s = 32'sd16;

            if (s < 32'sd8)
                smooth_scale_q8 = 16'd8;
            else if (s > 32'sd4095)
                smooth_scale_q8 = 16'd4095;
            else
                smooth_scale_q8 = s[15:0];
        end
    endfunction

    // ------------------------------------------------------------------------
    // Slot selector.
    // ------------------------------------------------------------------------
    reg [2:0] slot_index;
    reg signed [15:0] selected_x;
    reg signed [15:0] selected_z;

    always @(*) begin
        case (slot_index)
            3'd0: begin selected_x=z0_x; selected_z=z0_z; end
            3'd1: begin selected_x=z1_x; selected_z=z1_z; end
            3'd2: begin selected_x=z2_x; selected_z=z2_z; end
            3'd3: begin selected_x=z3_x; selected_z=z3_z; end
            3'd4: begin selected_x=z4_x; selected_z=z4_z; end
            3'd5: begin selected_x=z5_x; selected_z=z5_z; end
            3'd6: begin selected_x=z6_x; selected_z=z6_z; end
            default: begin selected_x=z7_x; selected_z=z7_z; end
        endcase
    end

    // ------------------------------------------------------------------------
    // Sequential shared arithmetic.
    // ------------------------------------------------------------------------
    localparam [3:0]
        PS_IDLE      = 4'd0,
        PS_LOAD      = 4'd1,
        PS_XCOS      = 4'd2,
        PS_ZSIN      = 4'd3,
        PS_XSIN      = 4'd4,
        PS_ZCOS      = 4'd5,
        PS_SCALE     = 4'd6,
        PS_XPROJECT  = 4'd7,
        PS_YPROJECT  = 4'd8,
        PS_STORE     = 4'd9;

    reg [3:0] pstate;

    reg signed [16:0] rel_x_reg;
    reg signed [16:0] rel_y_reg;
    reg signed [16:0] rel_z_reg;

    reg signed [34:0] xcos_reg;
    reg signed [34:0] xsin_reg;

    reg signed [18:0] camera_space_x_reg;
    reg signed [18:0] depth_reg;

    reg [15:0] scale_reg;
    reg signed [34:0] xproject_reg;
    reg signed [34:0] yproject_reg;

    // ONE shared multiplier. Both trig and perspective products fit here.
    reg signed [18:0] mul_a_reg;
    reg signed [15:0] mul_b_reg;
    wire signed [34:0] mul_product =
        $signed(mul_a_reg) * $signed(mul_b_reg);

    wire [15:0] scale_calc = smooth_scale_q8(depth_reg);

    // radius ~= 36 * 256 / depth = (36*scale_q8)>>8.
    wire [23:0] radius_scaled =
        ({8'd0,scale_reg} << 5) + ({8'd0,scale_reg} << 2);
    wire [15:0] radius_unclipped = radius_scaled[23:8];
    wire [7:0] radius_calc =
        (radius_unclipped > 16'd80) ? 8'd80 :
        (radius_unclipped < 16'd4)  ? 8'd4  :
                                      radius_unclipped[7:0];

    // Clamp signed camera-space depth to the 16-bit wall-depth format.
    wire [15:0] depth_output_calc =
        (depth_reg <= 19'sd0)      ? 16'd0 :
        (depth_reg > 19'sd65535)   ? 16'hFFFF :
                                     depth_reg[15:0];

    wire signed [31:0] xoffset_calc =
        $signed(xproject_reg) >>> 8;
    wire signed [31:0] yoffset_calc =
        $signed(yproject_reg) >>> 8;

    wire signed [31:0] projected_x_calc =
        32'sd320 + xoffset_calc;
    wire signed [31:0] projected_y_calc =
        $signed({{20{horizon_reg[11]}},horizon_reg}) - yoffset_calc;

    wire signed [31:0] radius_signed =
        $signed({24'd0,radius_calc});

    wire projection_visible_calc =
        (depth_reg > 19'sd24) &&
        ((projected_x_calc + radius_signed) >= 0) &&
        ((projected_x_calc - radius_signed) < 32'sd640) &&
        ((projected_y_calc + radius_signed) >= 0) &&
        ((projected_y_calc - radius_signed) < 32'sd480);

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            cam_x_snap <= 0; cam_y_snap <= 0; cam_z_snap <= 0;
            yaw_snap <= 0; pitch_snap <= 0; horizon_reg <= 12'sd240;

            slot_index <= 0;
            pstate <= PS_IDLE;

            rel_x_reg <= 0; rel_y_reg <= 0; rel_z_reg <= 0;
            xcos_reg <= 0; xsin_reg <= 0;
            camera_space_x_reg <= 0; depth_reg <= 0;
            scale_reg <= 0; xproject_reg <= 0; yproject_reg <= 0;
            mul_a_reg <= 0; mul_b_reg <= 0;

            z0_screen_x<=320; z0_screen_y<=240; z0_radius<=4; z0_visible<=0; z0_depth<=0;
            z1_screen_x<=320; z1_screen_y<=240; z1_radius<=4; z1_visible<=0; z1_depth<=0;
            z2_screen_x<=320; z2_screen_y<=240; z2_radius<=4; z2_visible<=0; z2_depth<=0;
            z3_screen_x<=320; z3_screen_y<=240; z3_radius<=4; z3_visible<=0; z3_depth<=0;
            z4_screen_x<=320; z4_screen_y<=240; z4_radius<=4; z4_visible<=0; z4_depth<=0;
            z5_screen_x<=320; z5_screen_y<=240; z5_radius<=4; z5_visible<=0; z5_depth<=0;
            z6_screen_x<=320; z6_screen_y<=240; z6_radius<=4; z6_visible<=0; z6_depth<=0;
            z7_screen_x<=320; z7_screen_y<=240; z7_radius<=4; z7_visible<=0; z7_depth<=0;
        end
        else begin
            case (pstate)
                PS_IDLE: begin
                    if (frame_tick) begin
                        cam_x_snap <= camera_x;
                        cam_y_snap <= camera_y;
                        cam_z_snap <= camera_z;
                        yaw_snap <= camera_yaw;
                        pitch_snap <= camera_pitch;
                        horizon_reg <= horizon_from_pitch(camera_pitch);

                        slot_index <= 3'd0;
                        pstate <= PS_LOAD;
                    end
                end

                PS_LOAD: begin
                    rel_x_reg <=
                        $signed({selected_x[15],selected_x}) -
                        $signed({cam_x_snap[15],cam_x_snap});

                    // Zombie visual center remains Y=48, same as V22.
                    rel_y_reg <=
                        17'sd48 -
                        $signed({cam_y_snap[15],cam_y_snap});

                    rel_z_reg <=
                        $signed({selected_z[15],selected_z}) -
                        $signed({cam_z_snap[15],cam_z_snap});

                    pstate <= PS_XCOS;
                end

                PS_XCOS: begin
                    mul_a_reg <= {{2{rel_x_reg[16]}},rel_x_reg};
                    mul_b_reg <= {{7{shared_cos[8]}},shared_cos};
                    pstate <= PS_ZSIN;
                end

                PS_ZSIN: begin
                    xcos_reg <= mul_product;
                    mul_a_reg <= {{2{rel_z_reg[16]}},rel_z_reg};
                    mul_b_reg <= {{7{shared_sin[8]}},shared_sin};
                    pstate <= PS_XSIN;
                end

                PS_XSIN: begin
                    camera_space_x_reg <=
                        ($signed(xcos_reg) - $signed(mul_product)) >>> 7;

                    mul_a_reg <= {{2{rel_x_reg[16]}},rel_x_reg};
                    mul_b_reg <= {{7{shared_sin[8]}},shared_sin};
                    pstate <= PS_ZCOS;
                end

                PS_ZCOS: begin
                    xsin_reg <= mul_product;
                    mul_a_reg <= {{2{rel_z_reg[16]}},rel_z_reg};
                    mul_b_reg <= {{7{shared_cos[8]}},shared_cos};
                    pstate <= PS_SCALE;
                end

                PS_SCALE: begin
                    depth_reg <=
                        ($signed(xsin_reg) + $signed(mul_product)) >>> 7;
                    pstate <= PS_XPROJECT;
                end

                PS_XPROJECT: begin
                    scale_reg <= scale_calc;

                    mul_a_reg <= camera_space_x_reg;
                    mul_b_reg <= $signed(scale_calc);
                    pstate <= PS_YPROJECT;
                end

                PS_YPROJECT: begin
                    xproject_reg <= mul_product;

                    mul_a_reg <= {{2{rel_y_reg[16]}},rel_y_reg};
                    mul_b_reg <= $signed(scale_reg);
                    pstate <= PS_STORE;
                end

                PS_STORE: begin
                    yproject_reg <= mul_product;

                    // yproject_reg receives mul_product on this edge, so use
                    // the current multiplier output directly for Y below.
                    case (slot_index)
                        3'd0: begin
                            z0_screen_x <= projected_x_calc[11:0];
                            z0_screen_y <=
                                ($signed({{20{horizon_reg[11]}},horizon_reg})
                                 - ($signed(mul_product) >>> 8));
                            z0_radius <= radius_calc;
                            z0_depth <= depth_output_calc;
                            z0_visible <=
                                (depth_reg > 19'sd24) &&
                                ((projected_x_calc + radius_signed) >= 0) &&
                                ((projected_x_calc - radius_signed) < 32'sd640) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   + radius_signed) >= 0) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   - radius_signed) < 32'sd480);
                        end
                        3'd1: begin
                            z1_screen_x <= projected_x_calc[11:0];
                            z1_screen_y <=
                                ($signed({{20{horizon_reg[11]}},horizon_reg})
                                 - ($signed(mul_product) >>> 8));
                            z1_radius <= radius_calc;
                            z1_depth <= depth_output_calc;
                            z1_visible <=
                                (depth_reg > 19'sd24) &&
                                ((projected_x_calc + radius_signed) >= 0) &&
                                ((projected_x_calc - radius_signed) < 32'sd640) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   + radius_signed) >= 0) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   - radius_signed) < 32'sd480);
                        end
                        3'd2: begin
                            z2_screen_x <= projected_x_calc[11:0];
                            z2_screen_y <=
                                ($signed({{20{horizon_reg[11]}},horizon_reg})
                                 - ($signed(mul_product) >>> 8));
                            z2_radius <= radius_calc;
                            z2_depth <= depth_output_calc;
                            z2_visible <=
                                (depth_reg > 19'sd24) &&
                                ((projected_x_calc + radius_signed) >= 0) &&
                                ((projected_x_calc - radius_signed) < 32'sd640) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   + radius_signed) >= 0) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   - radius_signed) < 32'sd480);
                        end
                        3'd3: begin
                            z3_screen_x <= projected_x_calc[11:0];
                            z3_screen_y <=
                                ($signed({{20{horizon_reg[11]}},horizon_reg})
                                 - ($signed(mul_product) >>> 8));
                            z3_radius <= radius_calc;
                            z3_depth <= depth_output_calc;
                            z3_visible <=
                                (depth_reg > 19'sd24) &&
                                ((projected_x_calc + radius_signed) >= 0) &&
                                ((projected_x_calc - radius_signed) < 32'sd640) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   + radius_signed) >= 0) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   - radius_signed) < 32'sd480);
                        end
                        3'd4: begin
                            z4_screen_x <= projected_x_calc[11:0];
                            z4_screen_y <=
                                ($signed({{20{horizon_reg[11]}},horizon_reg})
                                 - ($signed(mul_product) >>> 8));
                            z4_radius <= radius_calc;
                            z4_depth <= depth_output_calc;
                            z4_visible <=
                                (depth_reg > 19'sd24) &&
                                ((projected_x_calc + radius_signed) >= 0) &&
                                ((projected_x_calc - radius_signed) < 32'sd640) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   + radius_signed) >= 0) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   - radius_signed) < 32'sd480);
                        end
                        3'd5: begin
                            z5_screen_x <= projected_x_calc[11:0];
                            z5_screen_y <=
                                ($signed({{20{horizon_reg[11]}},horizon_reg})
                                 - ($signed(mul_product) >>> 8));
                            z5_radius <= radius_calc;
                            z5_depth <= depth_output_calc;
                            z5_visible <=
                                (depth_reg > 19'sd24) &&
                                ((projected_x_calc + radius_signed) >= 0) &&
                                ((projected_x_calc - radius_signed) < 32'sd640) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   + radius_signed) >= 0) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   - radius_signed) < 32'sd480);
                        end
                        3'd6: begin
                            z6_screen_x <= projected_x_calc[11:0];
                            z6_screen_y <=
                                ($signed({{20{horizon_reg[11]}},horizon_reg})
                                 - ($signed(mul_product) >>> 8));
                            z6_radius <= radius_calc;
                            z6_depth <= depth_output_calc;
                            z6_visible <=
                                (depth_reg > 19'sd24) &&
                                ((projected_x_calc + radius_signed) >= 0) &&
                                ((projected_x_calc - radius_signed) < 32'sd640) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   + radius_signed) >= 0) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   - radius_signed) < 32'sd480);
                        end
                        default: begin
                            z7_screen_x <= projected_x_calc[11:0];
                            z7_screen_y <=
                                ($signed({{20{horizon_reg[11]}},horizon_reg})
                                 - ($signed(mul_product) >>> 8));
                            z7_radius <= radius_calc;
                            z7_depth <= depth_output_calc;
                            z7_visible <=
                                (depth_reg > 19'sd24) &&
                                ((projected_x_calc + radius_signed) >= 0) &&
                                ((projected_x_calc - radius_signed) < 32'sd640) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   + radius_signed) >= 0) &&
                                ((($signed({{20{horizon_reg[11]}},horizon_reg})
                                   - ($signed(mul_product) >>> 8))
                                   - radius_signed) < 32'sd480);
                        end
                    endcase

                    if (slot_index == 3'd7) begin
                        pstate <= PS_IDLE;
                    end
                    else begin
                        slot_index <= slot_index + 1'b1;
                        pstate <= PS_LOAD;
                    end
                end

                default: pstate <= PS_IDLE;
            endcase
        end
    end
endmodule


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



// ============================================================================
// V22E PLAYER HP HUD
//
// Draws "HP3" immediately to the right of the four-digit money HUD.
// Money occupies x=12..71, y=14..35.
// HP begins at x=84, y=14.
//
// The H/P glyphs use only simple rectangle comparisons. The HP digit reuses
// seven-segment geometry, keeping this display-only overlay very small.
// ============================================================================
module player_hp_hud_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire [2:0] player_hp,
    output reg        hp_pixel
);
    reg [4:0] local_x;
    reg [4:0] local_y;
    reg [6:0] segments;
    reg       inside_digit;

    function [6:0] digit_segments;
        input [3:0] d;
        begin
            case (d)
                4'd0: digit_segments = 7'b1111110;
                4'd1: digit_segments = 7'b0110000;
                4'd2: digit_segments = 7'b1101101;
                4'd3: digit_segments = 7'b1111001;
                4'd4: digit_segments = 7'b0110011;
                default: digit_segments = 7'b0000000;
            endcase
        end
    endfunction

    always @(*) begin
        hp_pixel = 1'b0;
        local_x = 5'd0;
        local_y = 5'd0;
        inside_digit = 1'b0;
        segments = digit_segments({1'b0,player_hp});

        // H: x=84..94, y=14..35
        if ((pixel_y >= 10'd14) && (pixel_y < 10'd36)) begin
            if ((pixel_x >= 10'd84) && (pixel_x <= 10'd85))
                hp_pixel = 1'b1;
            if ((pixel_x >= 10'd93) && (pixel_x <= 10'd94))
                hp_pixel = 1'b1;
            if ((pixel_x >= 10'd84) && (pixel_x <= 10'd94) &&
                (pixel_y >= 10'd24) && (pixel_y <= 10'd25))
                hp_pixel = 1'b1;

            // P: x=100..110, y=14..35
            if ((pixel_x >= 10'd100) && (pixel_x <= 10'd101))
                hp_pixel = 1'b1;
            if ((pixel_y >= 10'd14) && (pixel_y <= 10'd15) &&
                (pixel_x >= 10'd100) && (pixel_x <= 10'd109))
                hp_pixel = 1'b1;
            if ((pixel_y >= 10'd24) && (pixel_y <= 10'd25) &&
                (pixel_x >= 10'd100) && (pixel_x <= 10'd109))
                hp_pixel = 1'b1;
            if ((pixel_x >= 10'd108) && (pixel_x <= 10'd109) &&
                (pixel_y >= 10'd16) && (pixel_y <= 10'd23))
                hp_pixel = 1'b1;

            // HP digit: x=116..127, same 12x22 geometry as money digits.
            if ((pixel_x >= 10'd116) && (pixel_x < 10'd128)) begin
                local_x = pixel_x - 10'd116;
                local_y = pixel_y - 10'd14;
                inside_digit = 1'b1;
            end
        end

        if (inside_digit) begin
            if (segments[6] && (local_y <= 5'd1) &&
                (local_x >= 5'd2) && (local_x <= 5'd9))
                hp_pixel = 1'b1;
            if (segments[5] && (local_x >= 5'd10) &&
                (local_y >= 5'd2) && (local_y <= 5'd9))
                hp_pixel = 1'b1;
            if (segments[4] && (local_x >= 5'd10) &&
                (local_y >= 5'd12) && (local_y <= 5'd19))
                hp_pixel = 1'b1;
            if (segments[3] && (local_y >= 5'd20) &&
                (local_x >= 5'd2) && (local_x <= 5'd9))
                hp_pixel = 1'b1;
            if (segments[2] && (local_x <= 5'd1) &&
                (local_y >= 5'd12) && (local_y <= 5'd19))
                hp_pixel = 1'b1;
            if (segments[1] && (local_x <= 5'd1) &&
                (local_y >= 5'd2) && (local_y <= 5'd9))
                hp_pixel = 1'b1;
            if (segments[0] && (local_y >= 5'd10) && (local_y <= 5'd11) &&
                (local_x >= 5'd2) && (local_x <= 5'd9))
                hp_pixel = 1'b1;
        end
    end
endmodule


// ============================================================================
// V22E EQUIPPED PISTOL ICON
//
// Simple fixed HUD sprite on the lower-right side.
// This is intentionally only an equipment icon for now, not a first-person
// weapon/hand model.
//
// Approximate screen bounds: x=566..627, y=414..461.
// ============================================================================
// ============================================================================
// V26B SELECTED POWER-UP ICON HUD
//
// Packed immediately to the right of HP:
//   slot 0: x=136..149
//   slot 1: x=154..167
//
// The two active perks are packed in fixed type order so there are never gaps.
// icon_kind:
//   1 shoes / move speed
//   2 down arrow / slow zombies
//   3 heart / +1 HP
//   0 magazine / fast reload
// ============================================================================
module powerup_perk_icon_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,

    input  wire       perk_move_speed,
    input  wire       perk_zombie_slow,
    input  wire       perk_extra_hp,
    input  wire       perk_fast_reload,

    output reg        icon_pixel,
    output reg  [1:0] icon_kind
);
    localparam [2:0]
        ICON_NONE   = 3'd0,
        ICON_SHOES  = 3'd1,
        ICON_SLOW   = 3'd2,
        ICON_HEART  = 3'd3,
        ICON_MAG    = 3'd4;

    reg [2:0] slot0_kind;
    reg [2:0] slot1_kind;
    reg [2:0] draw_kind;
    reg [3:0] sx;
    reg [3:0] sy;
    reg       in_slot;

    always @(*) begin
        // Pack the maximum two selected perks without extra state registers.
        slot0_kind = ICON_NONE;
        slot1_kind = ICON_NONE;

        case ({perk_fast_reload,perk_extra_hp,
               perk_zombie_slow,perk_move_speed})
            4'b0001: slot0_kind = ICON_SHOES;
            4'b0010: slot0_kind = ICON_SLOW;
            4'b0011: begin slot0_kind=ICON_SHOES; slot1_kind=ICON_SLOW; end
            4'b0100: slot0_kind = ICON_HEART;
            4'b0101: begin slot0_kind=ICON_SHOES; slot1_kind=ICON_HEART; end
            4'b0110: begin slot0_kind=ICON_SLOW; slot1_kind=ICON_HEART; end
            4'b1000: slot0_kind = ICON_MAG;
            4'b1001: begin slot0_kind=ICON_SHOES; slot1_kind=ICON_MAG; end
            4'b1010: begin slot0_kind=ICON_SLOW; slot1_kind=ICON_MAG; end
            4'b1100: begin slot0_kind=ICON_HEART; slot1_kind=ICON_MAG; end
            default: begin
                slot0_kind = ICON_NONE;
                slot1_kind = ICON_NONE;
            end
        endcase

        icon_pixel = 1'b0;
        icon_kind = 2'd0;
        draw_kind = ICON_NONE;
        sx = 4'd0;
        sy = 4'd0;
        in_slot = 1'b0;

        if ((pixel_y >= 10'd18) && (pixel_y <= 10'd31)) begin
            if ((pixel_x >= 10'd136) && (pixel_x <= 10'd149)) begin
                sx = pixel_x - 10'd136;
                sy = pixel_y - 10'd18;
                draw_kind = slot0_kind;
                in_slot = 1'b1;
            end
            else if ((pixel_x >= 10'd154) && (pixel_x <= 10'd167)) begin
                sx = pixel_x - 10'd154;
                sy = pixel_y - 10'd18;
                draw_kind = slot1_kind;
                in_slot = 1'b1;
            end
        end

        if (in_slot) begin
            case (draw_kind)
                // --------------------------------------------------------
                // Shoes: two compact boot silhouettes.
                // --------------------------------------------------------
                ICON_SHOES: begin
                    icon_kind = 2'd1;

                    if (((sx >= 4'd1) && (sx <= 4'd5) &&
                         (sy >= 4'd2) && (sy <= 4'd8)) ||
                        ((sx >= 4'd0) && (sx <= 4'd6) &&
                         (sy >= 4'd8) && (sy <= 4'd10)) ||
                        ((sx >= 4'd8) && (sx <= 4'd11) &&
                         (sy >= 4'd4) && (sy <= 4'd9)) ||
                        ((sx >= 4'd7) && (sx <= 4'd13) &&
                         (sy >= 4'd9) && (sy <= 4'd11)))
                        icon_pixel = 1'b1;
                end

                // --------------------------------------------------------
                // Slow: downward arrow.
                // --------------------------------------------------------
                ICON_SLOW: begin
                    icon_kind = 2'd2;

                    if (((sx >= 4'd6) && (sx <= 4'd7) &&
                         (sy >= 4'd1) && (sy <= 4'd7)) ||
                        ((sy == 4'd7) && (sx >= 4'd3) && (sx <= 4'd10)) ||
                        ((sy == 4'd8) && (sx >= 4'd4) && (sx <= 4'd9)) ||
                        ((sy == 4'd9) && (sx >= 4'd5) && (sx <= 4'd8)) ||
                        ((sy >= 4'd10) && (sy <= 4'd12) &&
                         (sx >= 4'd6) && (sx <= 4'd7)))
                        icon_pixel = 1'b1;
                end

                // --------------------------------------------------------
                // Heart.
                // --------------------------------------------------------
                ICON_HEART: begin
                    icon_kind = 2'd3;

                    if (((sy == 4'd2) &&
                         (((sx >= 4'd2) && (sx <= 4'd5)) ||
                          ((sx >= 4'd8) && (sx <= 4'd11)))) ||
                        ((sy >= 4'd3) && (sy <= 4'd6) &&
                         (sx >= 4'd1) && (sx <= 4'd12)) ||
                        ((sy == 4'd7) && (sx >= 4'd2) && (sx <= 4'd11)) ||
                        ((sy == 4'd8) && (sx >= 4'd3) && (sx <= 4'd10)) ||
                        ((sy == 4'd9) && (sx >= 4'd4) && (sx <= 4'd9)) ||
                        ((sy == 4'd10) && (sx >= 4'd5) && (sx <= 4'd8)) ||
                        ((sy >= 4'd11) && (sy <= 4'd12) &&
                         (sx >= 4'd6) && (sx <= 4'd7)))
                        icon_pixel = 1'b1;
                end

                // --------------------------------------------------------
                // Magazine / fast reload.
                // --------------------------------------------------------
                ICON_MAG: begin
                    icon_kind = 2'd0;

                    if (((sx >= 4'd4) && (sx <= 4'd9) &&
                         (sy >= 4'd1) && (sy <= 4'd10)) ||
                        ((sx >= 4'd5) && (sx <= 4'd9) &&
                         (sy >= 4'd11) && (sy <= 4'd12)) ||
                        ((sy == 4'd1) && (sx >= 4'd3) && (sx <= 4'd10)))
                        icon_pixel = 1'b1;
                end

                default: begin
                    icon_pixel = 1'b0;
                    icon_kind = 2'd0;
                end
            endcase
        end
    end
endmodule


module weapon_icon_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire [1:0] equipped_weapon,
    output reg        weapon_pixel
);
    localparam [1:0]
        WEAPON_PISTOL  = 2'd0,
        WEAPON_SHOTGUN = 2'd1,
        WEAPON_RIFLE   = 2'd2;

    always @(*) begin
        weapon_pixel = 1'b0;

        case (equipped_weapon)
            // ------------------------------------------------------------
            // SHOTGUN icon
            // ------------------------------------------------------------
            WEAPON_SHOTGUN: begin
                // Long barrel.
                if ((pixel_x >= 10'd557) && (pixel_x <= 10'd627) &&
                    (pixel_y >= 10'd416) && (pixel_y <= 10'd421))
                    weapon_pixel = 1'b1;

                // Receiver.
                if ((pixel_x >= 10'd580) && (pixel_x <= 10'd608) &&
                    (pixel_y >= 10'd422) && (pixel_y <= 10'd430))
                    weapon_pixel = 1'b1;

                // Pump.
                if ((pixel_x >= 10'd611) && (pixel_x <= 10'd623) &&
                    (pixel_y >= 10'd423) && (pixel_y <= 10'd428))
                    weapon_pixel = 1'b1;

                // Stock.
                if ((pixel_x >= 10'd556) && (pixel_x <= 10'd579) &&
                    (pixel_y >= 10'd422) && (pixel_y <= 10'd431))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd548) && (pixel_x <= 10'd560) &&
                    (pixel_y >= 10'd426) && (pixel_y <= 10'd435))
                    weapon_pixel = 1'b1;

                // Grip.
                if ((pixel_x >= 10'd590) && (pixel_x <= 10'd598) &&
                    (pixel_y >= 10'd431) && (pixel_y <= 10'd446))
                    weapon_pixel = 1'b1;
            end

            // ------------------------------------------------------------
            // RIFLE icon
            // ------------------------------------------------------------
            WEAPON_RIFLE: begin
                // Barrel.
                if ((pixel_x >= 10'd575) && (pixel_x <= 10'd627) &&
                    (pixel_y >= 10'd414) && (pixel_y <= 10'd419))
                    weapon_pixel = 1'b1;

                // Receiver/body.
                if ((pixel_x >= 10'd566) && (pixel_x <= 10'd608) &&
                    (pixel_y >= 10'd420) && (pixel_y <= 10'd429))
                    weapon_pixel = 1'b1;

                // Stock.
                if ((pixel_x >= 10'd548) && (pixel_x <= 10'd566) &&
                    (pixel_y >= 10'd417) && (pixel_y <= 10'd431))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd541) && (pixel_x <= 10'd551) &&
                    (pixel_y >= 10'd421) && (pixel_y <= 10'd434))
                    weapon_pixel = 1'b1;

                // Magazine.
                if ((pixel_x >= 10'd584) && (pixel_x <= 10'd596) &&
                    (pixel_y >= 10'd430) && (pixel_y <= 10'd440))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd587) && (pixel_x <= 10'd599) &&
                    (pixel_y >= 10'd441) && (pixel_y <= 10'd449))
                    weapon_pixel = 1'b1;

                // Grip.
                if ((pixel_x >= 10'd602) && (pixel_x <= 10'd609) &&
                    (pixel_y >= 10'd430) && (pixel_y <= 10'd444))
                    weapon_pixel = 1'b1;
            end

            // ------------------------------------------------------------
            // PISTOL icon
            // ------------------------------------------------------------
            default: begin
                if ((pixel_x >= 10'd566) && (pixel_x <= 10'd618) &&
                    (pixel_y >= 10'd414) && (pixel_y <= 10'd423))
                    weapon_pixel = 1'b1;

                if ((pixel_x >= 10'd618) && (pixel_x <= 10'd627) &&
                    (pixel_y >= 10'd416) && (pixel_y <= 10'd421))
                    weapon_pixel = 1'b1;

                if ((pixel_x >= 10'd576) && (pixel_x <= 10'd611) &&
                    (pixel_y >= 10'd424) && (pixel_y <= 10'd431))
                    weapon_pixel = 1'b1;

                if ((pixel_x >= 10'd586) && (pixel_x <= 10'd606) &&
                    (pixel_y >= 10'd432) && (pixel_y <= 10'd433))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd586) && (pixel_x <= 10'd588) &&
                    (pixel_y >= 10'd432) && (pixel_y <= 10'd441))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd604) && (pixel_x <= 10'd606) &&
                    (pixel_y >= 10'd432) && (pixel_y <= 10'd441))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd589) && (pixel_x <= 10'd603) &&
                    (pixel_y >= 10'd440) && (pixel_y <= 10'd442))
                    weapon_pixel = 1'b1;

                if ((pixel_x >= 10'd603) && (pixel_x <= 10'd613) &&
                    (pixel_y >= 10'd430) && (pixel_y <= 10'd437))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd601) && (pixel_x <= 10'd612) &&
                    (pixel_y >= 10'd438) && (pixel_y <= 10'd445))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd599) && (pixel_x <= 10'd610) &&
                    (pixel_y >= 10'd446) && (pixel_y <= 10'd453))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd597) && (pixel_x <= 10'd608) &&
                    (pixel_y >= 10'd454) && (pixel_y <= 10'd461))
                    weapon_pixel = 1'b1;

                if ((pixel_x >= 10'd572) && (pixel_x <= 10'd576) &&
                    (pixel_y >= 10'd411) && (pixel_y <= 10'd413))
                    weapon_pixel = 1'b1;
            end
        endcase
    end
endmodule



// ============================================================================
// V23 CURRENT MAGAZINE AMMO HUD
// Two white seven-segment digits above the weapon icon.
// ============================================================================
// ============================================================================
// V26B LOW-LUT RESERVE-AMMO BINARY -> BCD CONVERTER
//
// Converts only when value_in changes. Uses repeated subtraction over several
// 100 MHz clocks instead of a large combinational divider/network.
// Maximum input is 390, so conversion finishes essentially instantly to a
// human-visible 60 Hz HUD.
// ============================================================================
module ammo_reserve_bcd_converter (
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire [8:0] value_in,

    output reg  [3:0] hundreds,
    output reg  [3:0] tens,
    output reg  [3:0] ones
);
    localparam [1:0]
        BCD_IDLE     = 2'd0,
        BCD_HUNDREDS = 2'd1,
        BCD_TENS     = 2'd2;

    reg [1:0] state;
    reg [8:0] last_value;
    reg [8:0] work_value;
    reg [3:0] work_hundreds;
    reg [3:0] work_tens;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            state <= BCD_IDLE;
            last_value <= 9'h1FF;
            work_value <= 9'd0;
            work_hundreds <= 4'd0;
            work_tens <= 4'd0;

            hundreds <= 4'd0;
            tens <= 4'd0;
            ones <= 4'd0;
        end
        else begin
            case (state)
                BCD_IDLE: begin
                    if (value_in != last_value) begin
                        last_value <= value_in;
                        work_value <= value_in;
                        work_hundreds <= 4'd0;
                        work_tens <= 4'd0;
                        state <= BCD_HUNDREDS;
                    end
                end

                BCD_HUNDREDS: begin
                    if (work_value >= 9'd100) begin
                        work_value <= work_value - 9'd100;
                        work_hundreds <= work_hundreds + 4'd1;
                    end
                    else begin
                        state <= BCD_TENS;
                    end
                end

                BCD_TENS: begin
                    if (work_value >= 9'd10) begin
                        work_value <= work_value - 9'd10;
                        work_tens <= work_tens + 4'd1;
                    end
                    else begin
                        hundreds <= work_hundreds;
                        tens <= work_tens;
                        ones <= work_value[3:0];
                        state <= BCD_IDLE;
                    end
                end

                default:
                    state <= BCD_IDLE;
            endcase
        end
    end
endmodule


module weapon_ammo_hud_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire [5:0] ammo_count,

    input  wire       reserve_unlimited,
    input  wire [3:0] reserve_hundreds,
    input  wire [3:0] reserve_tens,
    input  wire [3:0] reserve_ones,

    output reg        ammo_pixel
);
    reg [3:0] mag_tens;
    reg [3:0] mag_ones;

    reg [6:0] segments;
    reg [4:0] lx;
    reg [4:0] ly;
    reg       inside;
    reg [3:0] digit;

    function [6:0] digit_segments;
        input [3:0] d;
        begin
            case(d)
                0:digit_segments=7'b1111110;
                1:digit_segments=7'b0110000;
                2:digit_segments=7'b1101101;
                3:digit_segments=7'b1111001;
                4:digit_segments=7'b0110011;
                5:digit_segments=7'b1011011;
                6:digit_segments=7'b1011111;
                7:digit_segments=7'b1110000;
                8:digit_segments=7'b1111111;
                9:digit_segments=7'b1111011;
                default:digit_segments=7'b0000000;
            endcase
        end
    endfunction

    always @(*) begin
        // Magazine is at most 39.
        if (ammo_count >= 6'd30) begin
            mag_tens = 4'd3;
            mag_ones = ammo_count - 6'd30;
        end
        else if (ammo_count >= 6'd20) begin
            mag_tens = 4'd2;
            mag_ones = ammo_count - 6'd20;
        end
        else if (ammo_count >= 6'd10) begin
            mag_tens = 4'd1;
            mag_ones = ammo_count - 6'd10;
        end
        else begin
            mag_tens = 4'd0;
            mag_ones = ammo_count[3:0];
        end

        ammo_pixel = 1'b0;
        lx = 0;
        ly = 0;
        inside = 1'b0;
        digit = 0;

        // V26B layout: MM / RRR
        // x=520..608, y=382..403.
        if ((pixel_y >= 10'd382) && (pixel_y < 10'd404)) begin
            // Magazine tens
            if ((pixel_x >= 10'd520) && (pixel_x < 10'd532)) begin
                lx = pixel_x - 10'd520;
                ly = pixel_y - 10'd382;
                digit = mag_tens;
                inside = 1'b1;
            end
            // Magazine ones
            else if ((pixel_x >= 10'd536) && (pixel_x < 10'd548)) begin
                lx = pixel_x - 10'd536;
                ly = pixel_y - 10'd382;
                digit = mag_ones;
                inside = 1'b1;
            end

            // Slash separator.
            else if ((pixel_x >= 10'd553) && (pixel_x <= 10'd558)) begin
                // Descending diagonal from upper-right to lower-left.
                if ((pixel_y >= 10'd384) && (pixel_y <= 10'd401)) begin
                    if (((pixel_x == 10'd558) &&
                         (pixel_y >= 10'd384) && (pixel_y <= 10'd386)) ||
                        ((pixel_x == 10'd557) &&
                         (pixel_y >= 10'd387) && (pixel_y <= 10'd389)) ||
                        ((pixel_x == 10'd556) &&
                         (pixel_y >= 10'd390) && (pixel_y <= 10'd392)) ||
                        ((pixel_x == 10'd555) &&
                         (pixel_y >= 10'd393) && (pixel_y <= 10'd395)) ||
                        ((pixel_x == 10'd554) &&
                         (pixel_y >= 10'd396) && (pixel_y <= 10'd398)) ||
                        ((pixel_x == 10'd553) &&
                         (pixel_y >= 10'd399) && (pixel_y <= 10'd401)))
                        ammo_pixel = 1'b1;
                end
            end

            else if (reserve_unlimited) begin
                // Compact infinity symbol occupying the reserve field.
                // Two linked outline loops.
                if ((pixel_y >= 10'd388) && (pixel_y <= 10'd398)) begin
                    if (((pixel_x >= 10'd569) && (pixel_x <= 10'd578) &&
                         ((pixel_y == 10'd388) || (pixel_y == 10'd398) ||
                          (pixel_x == 10'd569) || (pixel_x == 10'd578))) ||
                        ((pixel_x >= 10'd580) && (pixel_x <= 10'd589) &&
                         ((pixel_y == 10'd388) || (pixel_y == 10'd398) ||
                          (pixel_x == 10'd580) || (pixel_x == 10'd589))) ||
                        ((pixel_x >= 10'd577) && (pixel_x <= 10'd581) &&
                         (pixel_y >= 10'd392) && (pixel_y <= 10'd394)))
                        ammo_pixel = 1'b1;
                end
            end
            else begin
                // Reserve hundreds
                if ((pixel_x >= 10'd564) && (pixel_x < 10'd576)) begin
                    lx = pixel_x - 10'd564;
                    ly = pixel_y - 10'd382;
                    digit = reserve_hundreds;
                    inside = 1'b1;
                end
                // Reserve tens
                else if ((pixel_x >= 10'd580) && (pixel_x < 10'd592)) begin
                    lx = pixel_x - 10'd580;
                    ly = pixel_y - 10'd382;
                    digit = reserve_tens;
                    inside = 1'b1;
                end
                // Reserve ones
                else if ((pixel_x >= 10'd596) && (pixel_x < 10'd608)) begin
                    lx = pixel_x - 10'd596;
                    ly = pixel_y - 10'd382;
                    digit = reserve_ones;
                    inside = 1'b1;
                end
            end
        end

        segments = digit_segments(digit);

        if (inside) begin
            if (segments[6] && (ly <= 1) && (lx >= 2) && (lx <= 9))
                ammo_pixel = 1'b1;
            if (segments[5] && (lx >= 10) && (ly >= 2) && (ly <= 9))
                ammo_pixel = 1'b1;
            if (segments[4] && (lx >= 10) && (ly >= 12) && (ly <= 19))
                ammo_pixel = 1'b1;
            if (segments[3] && (ly >= 20) && (lx >= 2) && (lx <= 9))
                ammo_pixel = 1'b1;
            if (segments[2] && (lx <= 1) && (ly >= 12) && (ly <= 19))
                ammo_pixel = 1'b1;
            if (segments[1] && (lx <= 1) && (ly >= 2) && (ly <= 9))
                ammo_pixel = 1'b1;
            if (segments[0] && (ly >= 10) && (ly <= 11) &&
                (lx >= 2) && (lx <= 9))
                ammo_pixel = 1'b1;
        end
    end
endmodule


// ============================================================================
// V23 RELOAD COUNTDOWN UNDER CROSSHAIR
//
// tenths_remaining:
//   pistol  starts at 12 -> 1.2
//   shotgun starts at 20 -> 2.0
//   rifle   starts at 18 -> 1.8
//
// Draws one whole digit, decimal point, and one tenths digit.
// ============================================================================
module reload_timer_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire       reload_active,
    input  wire [4:0] tenths_remaining,
    output reg        reload_pixel
);
    reg [3:0] whole_digit;
    reg [3:0] decimal_digit;
    reg [6:0] segments;
    reg [3:0] lx;
    reg [3:0] ly;
    reg       inside;
    reg [3:0] digit;

    function [6:0] digit_segments;
        input [3:0] d;
        begin
            case(d)
                0:digit_segments=7'b1111110;
                1:digit_segments=7'b0110000;
                2:digit_segments=7'b1101101;
                3:digit_segments=7'b1111001;
                4:digit_segments=7'b0110011;
                5:digit_segments=7'b1011011;
                6:digit_segments=7'b1011111;
                7:digit_segments=7'b1110000;
                8:digit_segments=7'b1111111;
                9:digit_segments=7'b1111011;
                default:digit_segments=7'b0000000;
            endcase
        end
    endfunction

    always @(*) begin
        if (tenths_remaining >= 5'd20) begin
            whole_digit = 4'd2;
            decimal_digit = tenths_remaining - 5'd20;
        end
        else if (tenths_remaining >= 5'd10) begin
            whole_digit = 4'd1;
            decimal_digit = tenths_remaining - 5'd10;
        end
        else begin
            whole_digit = 4'd0;
            decimal_digit = tenths_remaining[3:0];
        end

        reload_pixel = 1'b0;
        lx = 0; ly = 0; inside = 1'b0; digit = 0;

        if (reload_active &&
            (pixel_y >= 10'd252) && (pixel_y < 10'd268)) begin

            // Whole digit: x=306..313, 8x16
            if ((pixel_x >= 10'd306) && (pixel_x < 10'd314)) begin
                lx = pixel_x - 10'd306;
                ly = pixel_y - 10'd252;
                digit = whole_digit;
                inside = 1'b1;
            end

            // Decimal dot.
            if ((pixel_x >= 10'd317) && (pixel_x <= 10'd319) &&
                (pixel_y >= 10'd264) && (pixel_y <= 10'd266))
                reload_pixel = 1'b1;

            // Tenths digit: x=322..329.
            if ((pixel_x >= 10'd322) && (pixel_x < 10'd330)) begin
                lx = pixel_x - 10'd322;
                ly = pixel_y - 10'd252;
                digit = decimal_digit;
                inside = 1'b1;
            end
        end

        segments = digit_segments(digit);

        // Mini 8x16 seven-segment geometry.
        if (inside) begin
            if (segments[6] && (ly <= 1) && (lx >= 2) && (lx <= 5))
                reload_pixel = 1'b1;
            if (segments[5] && (lx >= 6) && (ly >= 2) && (ly <= 6))
                reload_pixel = 1'b1;
            if (segments[4] && (lx >= 6) && (ly >= 9) && (ly <= 13))
                reload_pixel = 1'b1;
            if (segments[3] && (ly >= 14) && (lx >= 2) && (lx <= 5))
                reload_pixel = 1'b1;
            if (segments[2] && (lx <= 1) && (ly >= 9) && (ly <= 13))
                reload_pixel = 1'b1;
            if (segments[1] && (lx <= 1) && (ly >= 2) && (ly <= 6))
                reload_pixel = 1'b1;
            if (segments[0] && (ly >= 7) && (ly <= 8) &&
                (lx >= 2) && (lx <= 5))
                reload_pixel = 1'b1;
        end
    end
endmodule



// ============================================================================
// V23B WALL-BUY LABEL OVERLAY
//
// Tracks the visible screen-space bounding box of each pink buy-wall surface
// during one frame, then uses that box on the next frame to center a compact
// 5x7 label. The final pixel is still clipped by the CURRENT buy-wall surface,
// so white letters appear only on the pink wall:
//
//      SHOTGUN 500
//      RIFLE 1000
//
// Scale automatically uses 2x when the visible surface is wide enough;
// otherwise it falls back to 1x. At extreme distance the label may be tiny,
// which is appropriate because the physical sign is far away.
// ============================================================================

// ============================================================================
// V24 VISUAL-ONLY STATIC STATION LABELS
//
// POWER 1000
// ULTIMATE 1500
// POWER UP
// LUCKY BOX 1000
//
// Tracks the projected pink rectangle during one frame, then centers a 5x7
// label inside its previous-frame bounding box. These stations are visual-only.
// ============================================================================







// ============================================================================
// V24B SHARED LUT-OPTIMIZED PINK-STATION LABEL RENDERER
//
// One renderer serves all six projected pink surfaces:
//
//   SHOTGUN 500
//   RIFLE 1000
//   POWER 1000
//   ULTIMATE 1500
//   POWER UP
//   LUCKY BOX 1000
//
// The V24 build had TWO complete label renderers, duplicating the 5x7 font,
// character selection, division-by-6 approximation, and placement logic.
// V24B shares all of that logic.
//
// Text is intentionally fixed at 1x 5x7 size. Removing the optional 2x scaling
// branch recovers additional LUT headroom on the XC7A35T.
// ============================================================================
module shared_station_label_overlay (
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire       frame_tick,
    input  wire       pixel_tick,
    input  wire       active_video,
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire signed [8:0] camera_pitch,

    input  wire       shotgun_column,
    input  wire       rifle_column,
    input  wire       power_column,
    input  wire       ultimate_column,
    input  wire       powerup_column,
    input  wire       luckybox_column,

    input  wire       shotgun_surface_pixel,
    input  wire       rifle_surface_pixel,
    input  wire       power_surface_pixel,
    input  wire       ultimate_surface_pixel,
    input  wire       powerup_surface_pixel,
    input  wire       luckybox_surface_pixel,

    output reg        label_pixel
);

    localparam [2:0]
        K_NONE     = 3'd0,
        K_SHOTGUN  = 3'd1,
        K_RIFLE    = 3'd2,
        K_POWER    = 3'd3,
        K_ULTIMATE = 3'd4,
        K_POWERUP  = 3'd5,
        K_LUCKYBOX = 3'd6;

    // X-only projected bounds. Wall subtype is a per-column property, so
    // scanning once on active row 0 is enough.
    reg [9:0] shot_minx, shot_maxx, rifle_minx, rifle_maxx;
    reg [9:0] power_minx, power_maxx, ultimate_minx, ultimate_maxx;
    reg [9:0] powerup_minx, powerup_maxx, lucky_minx, lucky_maxx;

    reg [9:0] shot_bminx, shot_bmaxx, rifle_bminx, rifle_bmaxx;
    reg [9:0] power_bminx, power_bmaxx, ultimate_bminx, ultimate_bmaxx;
    reg [9:0] powerup_bminx, powerup_bmaxx, lucky_bminx, lucky_bmaxx;

    reg shot_valid, rifle_valid, power_valid;
    reg ultimate_valid, powerup_valid, lucky_valid;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            shot_minx<=639; shot_maxx<=0;
            rifle_minx<=639; rifle_maxx<=0;
            power_minx<=639; power_maxx<=0;
            ultimate_minx<=639; ultimate_maxx<=0;
            powerup_minx<=639; powerup_maxx<=0;
            lucky_minx<=639; lucky_maxx<=0;

            shot_bminx<=0; shot_bmaxx<=0;
            rifle_bminx<=0; rifle_bmaxx<=0;
            power_bminx<=0; power_bmaxx<=0;
            ultimate_bminx<=0; ultimate_bmaxx<=0;
            powerup_bminx<=0; powerup_bmaxx<=0;
            lucky_bminx<=0; lucky_bmaxx<=0;

            shot_valid<=0; rifle_valid<=0; power_valid<=0;
            ultimate_valid<=0; powerup_valid<=0; lucky_valid<=0;
        end
        else if (frame_tick) begin
            shot_valid <= (shot_minx <= shot_maxx);
            shot_bminx <= shot_minx; shot_bmaxx <= shot_maxx;

            rifle_valid <= (rifle_minx <= rifle_maxx);
            rifle_bminx <= rifle_minx; rifle_bmaxx <= rifle_maxx;

            power_valid <= (power_minx <= power_maxx);
            power_bminx <= power_minx; power_bmaxx <= power_maxx;

            ultimate_valid <= (ultimate_minx <= ultimate_maxx);
            ultimate_bminx <= ultimate_minx; ultimate_bmaxx <= ultimate_maxx;

            powerup_valid <= (powerup_minx <= powerup_maxx);
            powerup_bminx <= powerup_minx; powerup_bmaxx <= powerup_maxx;

            lucky_valid <= (lucky_minx <= lucky_maxx);
            lucky_bminx <= lucky_minx; lucky_bmaxx <= lucky_maxx;

            shot_minx<=639; shot_maxx<=0;
            rifle_minx<=639; rifle_maxx<=0;
            power_minx<=639; power_maxx<=0;
            ultimate_minx<=639; ultimate_maxx<=0;
            powerup_minx<=639; powerup_maxx<=0;
            lucky_minx<=639; lucky_maxx<=0;
        end
        else if (pixel_tick && active_video && (pixel_y == 10'd0)) begin
            if (shotgun_column) begin
                if(pixel_x<shot_minx) shot_minx<=pixel_x;
                if(pixel_x>shot_maxx) shot_maxx<=pixel_x;
            end
            if (rifle_column) begin
                if(pixel_x<rifle_minx) rifle_minx<=pixel_x;
                if(pixel_x>rifle_maxx) rifle_maxx<=pixel_x;
            end
            if (power_column) begin
                if(pixel_x<power_minx) power_minx<=pixel_x;
                if(pixel_x>power_maxx) power_maxx<=pixel_x;
            end
            if (ultimate_column) begin
                if(pixel_x<ultimate_minx) ultimate_minx<=pixel_x;
                if(pixel_x>ultimate_maxx) ultimate_maxx<=pixel_x;
            end
            if (powerup_column) begin
                if(pixel_x<powerup_minx) powerup_minx<=pixel_x;
                if(pixel_x>powerup_maxx) powerup_maxx<=pixel_x;
            end
            if (luckybox_column) begin
                if(pixel_x<lucky_minx) lucky_minx<=pixel_x;
                if(pixel_x>lucky_maxx) lucky_maxx<=pixel_x;
            end
        end
    end

    function [4:0] glyph_row;
        input [7:0] ch;
        input [2:0] row;
        begin
            glyph_row=0;
            case(ch)
                "A":case(row)0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b11111;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "B":case(row)0:glyph_row=5'b11110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b11110;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                "C":case(row)0:glyph_row=5'b01111;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b10000;4:glyph_row=5'b10000;5:glyph_row=5'b10000;6:glyph_row=5'b01111;default:glyph_row=0;endcase
                "E":case(row)0:glyph_row=5'b11111;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b11110;4:glyph_row=5'b10000;5:glyph_row=5'b10000;6:glyph_row=5'b11111;default:glyph_row=0;endcase
                "F":case(row)0:glyph_row=5'b11111;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b11110;4:glyph_row=5'b10000;5:glyph_row=5'b10000;6:glyph_row=5'b10000;default:glyph_row=0;endcase
                "G":case(row)0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b10000;3:glyph_row=5'b10111;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "H":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b11111;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "I":case(row)0:glyph_row=5'b11111;1:glyph_row=5'b00100;2:glyph_row=5'b00100;3:glyph_row=5'b00100;4:glyph_row=5'b00100;5:glyph_row=5'b00100;6:glyph_row=5'b11111;default:glyph_row=0;endcase
                "K":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b10010;2:glyph_row=5'b10100;3:glyph_row=5'b11000;4:glyph_row=5'b10100;5:glyph_row=5'b10010;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "L":case(row)0:glyph_row=5'b10000;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b10000;4:glyph_row=5'b10000;5:glyph_row=5'b10000;6:glyph_row=5'b11111;default:glyph_row=0;endcase
                "M":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b11011;2:glyph_row=5'b10101;3:glyph_row=5'b10101;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "N":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b11001;2:glyph_row=5'b11001;3:glyph_row=5'b10101;4:glyph_row=5'b10011;5:glyph_row=5'b10011;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "O":case(row)0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b10001;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "P":case(row)0:glyph_row=5'b11110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b11110;4:glyph_row=5'b10000;5:glyph_row=5'b10000;6:glyph_row=5'b10000;default:glyph_row=0;endcase
                "R":case(row)0:glyph_row=5'b11110;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b11110;4:glyph_row=5'b10100;5:glyph_row=5'b10010;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "S":case(row)0:glyph_row=5'b01111;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b01110;4:glyph_row=5'b00001;5:glyph_row=5'b00001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                "T":case(row)0:glyph_row=5'b11111;1:glyph_row=5'b00100;2:glyph_row=5'b00100;3:glyph_row=5'b00100;4:glyph_row=5'b00100;5:glyph_row=5'b00100;6:glyph_row=5'b00100;default:glyph_row=0;endcase
                "U":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b10001;4:glyph_row=5'b10001;5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "W":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b10001;3:glyph_row=5'b10101;4:glyph_row=5'b10101;5:glyph_row=5'b11011;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "X":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b01010;3:glyph_row=5'b00100;4:glyph_row=5'b01010;5:glyph_row=5'b10001;6:glyph_row=5'b10001;default:glyph_row=0;endcase
                "Y":case(row)0:glyph_row=5'b10001;1:glyph_row=5'b10001;2:glyph_row=5'b01010;3:glyph_row=5'b00100;4:glyph_row=5'b00100;5:glyph_row=5'b00100;6:glyph_row=5'b00100;default:glyph_row=0;endcase
                "0":case(row)0:glyph_row=5'b01110;1:glyph_row=5'b10001;2:glyph_row=5'b10011;3:glyph_row=5'b10101;4:glyph_row=5'b11001;5:glyph_row=5'b10001;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "1":case(row)0:glyph_row=5'b00100;1:glyph_row=5'b01100;2:glyph_row=5'b00100;3:glyph_row=5'b00100;4:glyph_row=5'b00100;5:glyph_row=5'b00100;6:glyph_row=5'b01110;default:glyph_row=0;endcase
                "5":case(row)0:glyph_row=5'b11111;1:glyph_row=5'b10000;2:glyph_row=5'b10000;3:glyph_row=5'b11110;4:glyph_row=5'b00001;5:glyph_row=5'b00001;6:glyph_row=5'b11110;default:glyph_row=0;endcase
                default:glyph_row=0;
            endcase
        end
    endfunction

    function [4:0] label_length;
        input [2:0] kind;
        begin
            case(kind)
                K_SHOTGUN:label_length=11;
                K_RIFLE:label_length=10;
                K_POWER:label_length=10;
                K_ULTIMATE:label_length=13;
                K_POWERUP:label_length=8;
                K_LUCKYBOX:label_length=14;
                default:label_length=0;
            endcase
        end
    endfunction

    function [7:0] label_char;
        input [2:0] kind;
        input [4:0] idx;
        begin
            label_char=" ";
            case(kind)
                K_SHOTGUN:case(idx)
                    0:label_char="S";1:label_char="H";2:label_char="O";3:label_char="T";
                    4:label_char="G";5:label_char="U";6:label_char="N";7:label_char=" ";
                    8:label_char="5";9:label_char="0";10:label_char="0";default:label_char=" ";
                endcase
                K_RIFLE:case(idx)
                    0:label_char="R";1:label_char="I";2:label_char="F";3:label_char="L";
                    4:label_char="E";5:label_char=" ";6:label_char="1";7:label_char="0";
                    8:label_char="0";9:label_char="0";default:label_char=" ";
                endcase
                K_POWER:case(idx)
                    0:label_char="P";1:label_char="O";2:label_char="W";3:label_char="E";
                    4:label_char="R";5:label_char=" ";6:label_char="1";7:label_char="0";
                    8:label_char="0";9:label_char="0";default:label_char=" ";
                endcase
                K_ULTIMATE:case(idx)
                    0:label_char="U";1:label_char="L";2:label_char="T";3:label_char="I";
                    4:label_char="M";5:label_char="A";6:label_char="T";7:label_char="E";
                    8:label_char=" ";9:label_char="1";10:label_char="5";11:label_char="0";
                    12:label_char="0";default:label_char=" ";
                endcase
                K_POWERUP:case(idx)
                    0:label_char="P";1:label_char="O";2:label_char="W";3:label_char="E";
                    4:label_char="R";5:label_char=" ";6:label_char="U";7:label_char="P";
                    default:label_char=" ";
                endcase
                K_LUCKYBOX:case(idx)
                    0:label_char="L";1:label_char="U";2:label_char="C";3:label_char="K";
                    4:label_char="Y";5:label_char=" ";6:label_char="B";7:label_char="O";
                    8:label_char="X";9:label_char=" ";10:label_char="1";11:label_char="0";
                    12:label_char="0";13:label_char="0";default:label_char=" ";
                endcase
                default:label_char=" ";
            endcase
        end
    endfunction

    reg [2:0] kind;
    reg selected_surface;
    reg [9:0] bminx,bmaxx,bw,text_w,x0,dx;
    reg [6:0] logical_x;
    reg [14:0] char_mult;
    reg [4:0] char_idx,chars;
    reg [2:0] char_col;
    reg [7:0] ch;
    reg [4:0] row_bits;

    reg signed [11:0] approx_horizon_y;
    reg signed [11:0] text_y0;
    reg signed [12:0] row_delta;

    always @(*) begin
        label_pixel=0; kind=K_NONE; selected_surface=0;
        bminx=0;bmaxx=0;bw=0;text_w=0;x0=0;dx=0;
        logical_x=0;char_mult=0;char_idx=0;chars=0;char_col=0;
        ch=" ";row_bits=0;

        approx_horizon_y=12'sd240+($signed(camera_pitch)<<<3);
        text_y0=approx_horizon_y-12'sd3;
        row_delta=$signed({3'b000,pixel_y})-$signed(text_y0);

        if(shotgun_column&&shot_valid)begin
            kind=K_SHOTGUN;selected_surface=shotgun_surface_pixel;
            bminx=shot_bminx;bmaxx=shot_bmaxx;
        end else if(rifle_column&&rifle_valid)begin
            kind=K_RIFLE;selected_surface=rifle_surface_pixel;
            bminx=rifle_bminx;bmaxx=rifle_bmaxx;
        end else if(power_column&&power_valid)begin
            kind=K_POWER;selected_surface=power_surface_pixel;
            bminx=power_bminx;bmaxx=power_bmaxx;
        end else if(ultimate_column&&ultimate_valid)begin
            kind=K_ULTIMATE;selected_surface=ultimate_surface_pixel;
            bminx=ultimate_bminx;bmaxx=ultimate_bmaxx;
        end else if(powerup_column&&powerup_valid)begin
            kind=K_POWERUP;selected_surface=powerup_surface_pixel;
            bminx=powerup_bminx;bmaxx=powerup_bmaxx;
        end else if(luckybox_column&&lucky_valid)begin
            kind=K_LUCKYBOX;selected_surface=luckybox_surface_pixel;
            bminx=lucky_bminx;bmaxx=lucky_bmaxx;
        end

        if((kind!=K_NONE)&&selected_surface)begin
            bw=bmaxx-bminx+1;
            chars=label_length(kind);
            text_w=(chars<<2)+(chars<<1);

            if((bw>=text_w)&&(row_delta>=0)&&(row_delta<=6))begin
                x0=bminx+((bw-text_w)>>1);
                if((pixel_x>=x0)&&(pixel_x<(x0+text_w)))begin
                    dx=pixel_x-x0;
                    logical_x=dx[6:0];
                    char_mult=({8'd0,logical_x}<<5)+
                              ({8'd0,logical_x}<<3)+
                              ({8'd0,logical_x}<<1)+
                               {8'd0,logical_x};
                    char_idx=char_mult[14:8];
                    char_col=logical_x-((char_idx<<2)+(char_idx<<1));
                    ch=label_char(kind,char_idx);
                    row_bits=glyph_row(ch,row_delta[2:0]);
                    if(char_col<5)begin
                        case(char_col)
                            0:label_pixel=row_bits[4];
                            1:label_pixel=row_bits[3];
                            2:label_pixel=row_bits[2];
                            3:label_pixel=row_bits[1];
                            default:label_pixel=row_bits[0];
                        endcase
                    end
                end
            end
        end
    end
endmodule


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


// ============================================================================
// TINY HP DEBUG DISPLAY
//
// leftmost digit  = zombie HP
// rightmost digit = player HP
// middle digits are blank.
// No division/modulo arithmetic.
// ============================================================================
module hp_debug_display (
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire [3:0] zombie_hp,
    input  wire [2:0] player_hp,
    output reg  [6:0] seg,
    output reg  [3:0] an,
    output reg        dp
);

    reg [17:0] refresh_counter;
    wire [1:0] digit_select = refresh_counter[17:16];

    function [6:0] encode_digit;
        input [3:0] d;
        begin
            case (d)
                4'd0: encode_digit = 7'b1000000;
                4'd1: encode_digit = 7'b1111001;
                4'd2: encode_digit = 7'b0100100;
                4'd3: encode_digit = 7'b0110000;
                4'd4: encode_digit = 7'b0011001;
                4'd5: encode_digit = 7'b0010010;
                4'd6: encode_digit = 7'b0000010;
                4'd7: encode_digit = 7'b1111000;
                4'd8: encode_digit = 7'b0000000;
                4'd9:  encode_digit = 7'b0010000;
                4'd10: encode_digit = 7'b0001000; // A = 10 HP debug
                default: encode_digit = 7'b1111111;
            endcase
        end
    endfunction

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset)
            refresh_counter <= 18'd0;
        else
            refresh_counter <= refresh_counter + 18'd1;
    end

    always @(*) begin
        seg = 7'b1111111;
        an  = 4'b1111;
        dp  = 1'b1;

        case (digit_select)
            2'd0: begin
                an  = 4'b1110;
                seg = encode_digit({1'b0, player_hp});
            end

            2'd3: begin
                an  = 4'b0111;
                seg = encode_digit(zombie_hp);
            end

            default: begin
                an  = 4'b1111;
                seg = 7'b1111111;
            end
        endcase
    end

endmodule


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


// ============================================================================
// IN-WORLD MODE SELECTOR OVERLAY
// Brown when inactive, green when its mode is active.
// ============================================================================
module mode_selector_overlay (
    input  wire [9:0]         pixel_x,
    input  wire [9:0]         pixel_y,
    input  wire [11:0]        base_rgb,
    input  wire [1:0]         current_mode,

    input  wire signed [11:0] speed_x,
    input  wire signed [11:0] speed_y,
    input  wire [7:0]         speed_radius,
    input  wire               speed_visible,

    input  wire signed [11:0] bots_x,
    input  wire signed [11:0] bots_y,
    input  wire [7:0]         bots_radius,
    input  wire               bots_visible,

    input  wire signed [11:0] moving_x,
    input  wire signed [11:0] moving_y,
    input  wire [7:0]         moving_radius,
    input  wire               moving_visible,

    output reg [11:0]         out_rgb
);

    localparam [1:0] MODE_SPEED  = 2'd1;
    localparam [1:0] MODE_99BOTS = 2'd2;
    localparam [1:0] MODE_MOVING = 2'd3;

    localparam [11:0] COLOR_BROWN = 12'h963;
    localparam [11:0] COLOR_GREEN = 12'h2F4;

    reg signed [12:0] dx0, dy0, dx1, dy1, dx2, dy2;
    reg signed [25:0] d0, d1, d2;
    reg [17:0] r0, r1, r2;
    reg p0, p1, p2;

    wire crosshair =
        (pixel_x >= 10'd319) && (pixel_x <= 10'd320) &&
        (pixel_y >= 10'd239) && (pixel_y <= 10'd240);

    always @(*) begin
        dx0 = $signed({3'b000,pixel_x}) - $signed(speed_x);
        dy0 = $signed({3'b000,pixel_y}) - $signed(speed_y);
        dx1 = $signed({3'b000,pixel_x}) - $signed(bots_x);
        dy1 = $signed({3'b000,pixel_y}) - $signed(bots_y);
        dx2 = $signed({3'b000,pixel_x}) - $signed(moving_x);
        dy2 = $signed({3'b000,pixel_y}) - $signed(moving_y);

        d0 = dx0*dx0 + dy0*dy0;
        d1 = dx1*dx1 + dy1*dy1;
        d2 = dx2*dx2 + dy2*dy2;

        r0 = speed_radius*speed_radius;
        r1 = bots_radius*bots_radius;
        r2 = moving_radius*moving_radius;

        p0 = speed_visible  && (d0 <= r0);
        p1 = bots_visible   && (d1 <= r1);
        p2 = moving_visible && (d2 <= r2);

        out_rgb = base_rgb;

        if (p0)
            out_rgb = (current_mode == MODE_SPEED) ? COLOR_GREEN : COLOR_BROWN;
        if (p1)
            out_rgb = (current_mode == MODE_99BOTS) ? COLOR_GREEN : COLOR_BROWN;
        if (p2)
            out_rgb = (current_mode == MODE_MOVING) ? COLOR_GREEN : COLOR_BROWN;

        // Crosshair remains top-most.
        if (crosshair)
            out_rgb = 12'hFFF;
    end

endmodule


// ============================================================================
// BASYS 3 FOUR-DIGIT SEVEN-SEGMENT DISPLAY
// Left two digits = left_value, right two digits = right_value.
// seg/an/dp are active-low on Basys 3.
// ============================================================================
module seven_segment_score_display (
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire       enable,
    input  wire [6:0] left_value,
    input  wire [6:0] right_value,
    output reg  [6:0] seg,
    output reg  [3:0] an,
    output reg        dp
);

    reg [17:0] refresh_counter;
    wire [1:0] digit_select = refresh_counter[17:16];

    reg [3:0] digit_value;
    reg [3:0] left_tens, left_ones, right_tens, right_ones;

    function [6:0] encode_digit;
        input [3:0] d;
        begin
            case (d)
                4'd0: encode_digit = 7'b1000000;
                4'd1: encode_digit = 7'b1111001;
                4'd2: encode_digit = 7'b0100100;
                4'd3: encode_digit = 7'b0110000;
                4'd4: encode_digit = 7'b0011001;
                4'd5: encode_digit = 7'b0010010;
                4'd6: encode_digit = 7'b0000010;
                4'd7: encode_digit = 7'b1111000;
                4'd8: encode_digit = 7'b0000000;
                4'd9: encode_digit = 7'b0010000;
                default: encode_digit = 7'b1111111;
            endcase
        end
    endfunction

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset)
            refresh_counter <= 18'd0;
        else
            refresh_counter <= refresh_counter + 18'd1;
    end

    always @(*) begin
        left_tens  = (left_value  > 7'd99) ? 4'd9 : left_value / 10;
        left_ones  = (left_value  > 7'd99) ? 4'd9 : left_value % 10;
        right_tens = (right_value > 7'd99) ? 4'd9 : right_value / 10;
        right_ones = (right_value > 7'd99) ? 4'd9 : right_value % 10;

        seg = 7'b1111111;
        an  = 4'b1111;
        dp  = 1'b1;
        digit_value = 4'd0;

        if (enable) begin
            case (digit_select)
                2'd0: begin
                    an = 4'b1110; // rightmost
                    digit_value = right_ones;
                end
                2'd1: begin
                    an = 4'b1101;
                    digit_value = right_tens;
                end
                2'd2: begin
                    an = 4'b1011;
                    digit_value = left_ones;
                end
                2'd3: begin
                    an = 4'b0111; // leftmost
                    digit_value = left_tens;
                end
            endcase
            seg = encode_digit(digit_value);
        end
    end

endmodule


// ============================================================================
// TRIG LUT - Q1.7
// 128 = +1.0
// ============================================================================
module trig_q17 (
    input  wire [7:0]        angle,
    output reg signed [8:0]  sin_value,
    output reg signed [8:0]  cos_value
);

    function signed [8:0] sin_quarter;
        input [6:0] qidx;
        begin
            case (qidx)
                7'd0: sin_quarter = 9'sd0;
                7'd1: sin_quarter = 9'sd3;
                7'd2: sin_quarter = 9'sd6;
                7'd3: sin_quarter = 9'sd9;
                7'd4: sin_quarter = 9'sd13;
                7'd5: sin_quarter = 9'sd16;
                7'd6: sin_quarter = 9'sd19;
                7'd7: sin_quarter = 9'sd22;
                7'd8: sin_quarter = 9'sd25;
                7'd9: sin_quarter = 9'sd28;
                7'd10: sin_quarter = 9'sd31;
                7'd11: sin_quarter = 9'sd34;
                7'd12: sin_quarter = 9'sd37;
                7'd13: sin_quarter = 9'sd40;
                7'd14: sin_quarter = 9'sd43;
                7'd15: sin_quarter = 9'sd46;
                7'd16: sin_quarter = 9'sd49;
                7'd17: sin_quarter = 9'sd52;
                7'd18: sin_quarter = 9'sd55;
                7'd19: sin_quarter = 9'sd58;
                7'd20: sin_quarter = 9'sd60;
                7'd21: sin_quarter = 9'sd63;
                7'd22: sin_quarter = 9'sd66;
                7'd23: sin_quarter = 9'sd68;
                7'd24: sin_quarter = 9'sd71;
                7'd25: sin_quarter = 9'sd74;
                7'd26: sin_quarter = 9'sd76;
                7'd27: sin_quarter = 9'sd79;
                7'd28: sin_quarter = 9'sd81;
                7'd29: sin_quarter = 9'sd84;
                7'd30: sin_quarter = 9'sd86;
                7'd31: sin_quarter = 9'sd88;
                7'd32: sin_quarter = 9'sd91;
                7'd33: sin_quarter = 9'sd93;
                7'd34: sin_quarter = 9'sd95;
                7'd35: sin_quarter = 9'sd97;
                7'd36: sin_quarter = 9'sd99;
                7'd37: sin_quarter = 9'sd101;
                7'd38: sin_quarter = 9'sd103;
                7'd39: sin_quarter = 9'sd105;
                7'd40: sin_quarter = 9'sd106;
                7'd41: sin_quarter = 9'sd108;
                7'd42: sin_quarter = 9'sd110;
                7'd43: sin_quarter = 9'sd111;
                7'd44: sin_quarter = 9'sd113;
                7'd45: sin_quarter = 9'sd114;
                7'd46: sin_quarter = 9'sd116;
                7'd47: sin_quarter = 9'sd117;
                7'd48: sin_quarter = 9'sd118;
                7'd49: sin_quarter = 9'sd119;
                7'd50: sin_quarter = 9'sd121;
                7'd51: sin_quarter = 9'sd122;
                7'd52: sin_quarter = 9'sd122;
                7'd53: sin_quarter = 9'sd123;
                7'd54: sin_quarter = 9'sd124;
                7'd55: sin_quarter = 9'sd125;
                7'd56: sin_quarter = 9'sd126;
                7'd57: sin_quarter = 9'sd126;
                7'd58: sin_quarter = 9'sd127;
                7'd59: sin_quarter = 9'sd127;
                7'd60: sin_quarter = 9'sd127;
                7'd61: sin_quarter = 9'sd128;
                7'd62: sin_quarter = 9'sd128;
                7'd63: sin_quarter = 9'sd128;
                7'd64: sin_quarter = 9'sd128;
                default: sin_quarter = 9'sd0;
            endcase
        end
    endfunction

    function signed [8:0] sin_full;
        input [7:0] a;
        reg [5:0] idx;
        reg [6:0] reflected_idx;
        begin
            idx = a[5:0];
            reflected_idx = 7'd0;

            case (a[7:6])
                2'b00:
                    sin_full = sin_quarter({1'b0, idx});

                2'b01: begin
                    reflected_idx = 7'd64 - {1'b0, idx};
                    sin_full = sin_quarter(reflected_idx);
                end

                2'b10:
                    sin_full = -sin_quarter({1'b0, idx});

                2'b11: begin
                    reflected_idx = 7'd64 - {1'b0, idx};
                    sin_full = -sin_quarter(reflected_idx);
                end
            endcase
        end
    endfunction

    always @(*) begin
        sin_value = sin_full(angle);
        cos_value = sin_full(angle + 8'd64);
    end

endmodule
