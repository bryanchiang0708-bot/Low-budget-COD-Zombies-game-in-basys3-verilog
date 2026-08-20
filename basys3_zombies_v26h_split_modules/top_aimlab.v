`timescale 1ns / 1ps

// ============================================================================
// BASYS 3 FPGA FPS - V26H PAID AMMO REFILL
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
//   - E at an owned shotgun/rifle wall buys MAX AMMO: shotgun 500, rifle 1000.
//   - POWER costs 1000 and gates POWER UP + ULTIMATE.
//   - POWER UP: choose max 2 perks with number keys 1..4; each costs 1000.
//       1 = +30% move speed (6 -> 8 world units/frame after ceiling)
//       2 = zombies move 30% slower
//       3 = +1 max HP
//       4 = reload time -30%
//   - ULTIMATE costs 1500 per gun:
//       magazine +30%, reserve ammo +30%, reload time -30%;
 //       damage: pistol 5, shotgun 30, rifle 8;
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
    wire powerup_menu_open;

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
        .powerup_menu_open(powerup_menu_open),

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
    wire perk_icon_pixel;
    wire powerup_menu_fg_pixel;
    wire powerup_menu_bg_pixel;

    powerup_perk_icon_overlay perk_icon_inst (
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .perk_move_speed(perk_move_speed),
        .perk_zombie_slow(perk_zombie_slow),
        .perk_extra_hp(perk_extra_hp),
        .perk_fast_reload(perk_fast_reload),

        .menu_open(powerup_menu_open),

        .icon_pixel(perk_icon_pixel),
        .menu_fg_pixel(powerup_menu_fg_pixel),
        .menu_bg_pixel(powerup_menu_bg_pixel)
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
        .power_on(power_on),

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
        else if (powerup_menu_fg_pixel) begin
            final_rgb_mux = 12'hFFF;
        end
        else if (powerup_menu_bg_pixel) begin
            final_rgb_mux = 12'h222;
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
            // V26C fixed perk icons directly beside HP.
            final_rgb_mux = 12'hFFF;
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
