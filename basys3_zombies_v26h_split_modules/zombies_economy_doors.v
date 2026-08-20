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
    output reg                powerup_menu_open,

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

    // V26G money-cap handling.
    //
    // 9999 is a saturated special value rather than a normal multiple-of-10
    // balance, so paid transactions from exactly 9999 are handled explicitly.
    wire money_at_cap = (money_value == MONEY_MAX);

    // If debug P was used to reach 9999 and is still being held, do not let
    // it immediately refill a purchase. Releasing P re-enables debug top-up.
    reg debug_money_inhibit;

    // V26C: stretch the max-ammo refill request across several 100 MHz clocks
    // so the weapon controller cannot miss a one-clock event.
    reg [2:0] ammo_refill_hold;

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
        (player_z >= 16'sd480) && (player_z <= 16'sd620) &&
        (player_x >= -16'sd160) && (player_x <= 16'sd160);

    assign near_rifle_buy =
        (player_x >= 16'sd800) && (player_x <= 16'sd940) &&
        (player_z >= -16'sd800) && (player_z <= -16'sd480);

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
            debug_money_inhibit <= 1'b0;

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
            powerup_menu_open <= 1'b0;

            pistol_ultimate <= 1'b0;
            shotgun_ultimate <= 1'b0;
            rifle_ultimate <= 1'b0;

            ammo_refill_pulse <= 1'b0;
            ammo_refill_weapon <= WEAPON_PISTOL;
            ammo_refill_hold <= 3'd0;

            ultimate_upgrade_pulse <= 1'b0;
            ultimate_upgrade_weapon <= WEAPON_PISTOL;
        end
        else begin
            key_e_d <= key_e;
            key_1_d <= key_1;
            key_2_d <= key_2;
            key_3_d <= key_3;
            key_4_d <= key_4;

            if (!key_p)
                debug_money_inhibit <= 1'b0;

            if (ammo_refill_hold != 3'd0) begin
                ammo_refill_hold <= ammo_refill_hold - 3'd1;
                ammo_refill_pulse <= 1'b1;
            end
            else begin
                ammo_refill_pulse <= 1'b0;
            end

            ultimate_upgrade_pulse <= 1'b0;

            // V26D: leaving the machine closes the purchase menu.
            if (powerup_menu_open && !near_powerup_machine)
                powerup_menu_open <= 1'b0;

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
                        // V26H: shotgun max-ammo refill costs 500.
                        // Re-equip the shotgun even when the player cannot
                        // afford the refill, but only issue the refill event
                        // after the 500-point purchase succeeds.
                        equipped_weapon <= WEAPON_SHOTGUN;

                        if (money_value >= SHOTGUN_PRICE) begin
                            ammo_refill_pulse <= 1'b1;
                            ammo_refill_hold <= 3'd4;
                            ammo_refill_weapon <= WEAPON_SHOTGUN;
                            debug_money_inhibit <= key_p;

                            if (money_at_cap) begin
                                // 9999 - 500 = 9499
                                money_value <= 14'd9499;
                                money_thousands <= 4'd9;
                                money_hundreds <= 4'd4;
                                money_tens <= 4'd9;
                                money_ones <= 4'd9;
                            end
                            else begin
                                money_value <= money_value - SHOTGUN_PRICE;

                                if (money_hundreds >= 4'd5)
                                    money_hundreds <= money_hundreds - 4'd5;
                                else begin
                                    money_thousands <= money_thousands - 4'd1;
                                    money_hundreds <= money_hundreds + 4'd5;
                                end
                            end
                        end
                    end
                    else if (money_value >= SHOTGUN_PRICE) begin
                        shotgun_owned <= 1'b1;
                        equipped_weapon <= WEAPON_SHOTGUN;
                        ammo_refill_pulse <= 1'b1;
                        ammo_refill_hold <= 3'd4;
                        ammo_refill_weapon <= WEAPON_SHOTGUN;

                        debug_money_inhibit <= key_p;

                        if (money_at_cap) begin
                            // 9999 - 500 = 9499
                            money_value <= 14'd9499;
                            money_thousands <= 4'd9;
                            money_hundreds <= 4'd4;
                            money_tens <= 4'd9;
                            money_ones <= 4'd9;
                        end
                        else begin
                            money_value <= money_value - SHOTGUN_PRICE;

                            if (money_hundreds >= 4'd5)
                                money_hundreds <= money_hundreds - 4'd5;
                            else begin
                                money_thousands <= money_thousands - 4'd1;
                                money_hundreds <= money_hundreds + 4'd5;
                            end
                        end
                    end
                end

                // Rifle wall:
                // - first E buys for 1000
                // - later E re-equips + refills reserve ammo free
                else if (near_rifle_buy) begin
                    if (rifle_owned) begin
                        // V26H: rifle max-ammo refill costs 1000.
                        equipped_weapon <= WEAPON_RIFLE;

                        if (money_value >= RIFLE_PRICE) begin
                            ammo_refill_pulse <= 1'b1;
                            ammo_refill_hold <= 3'd4;
                            ammo_refill_weapon <= WEAPON_RIFLE;
                            debug_money_inhibit <= key_p;

                            if (money_at_cap) begin
                                // 9999 - 1000 = 8999
                                money_value <= 14'd8999;
                                money_thousands <= 4'd8;
                                money_hundreds <= 4'd9;
                                money_tens <= 4'd9;
                                money_ones <= 4'd9;
                            end
                            else begin
                                money_value <= money_value - RIFLE_PRICE;
                                money_thousands <= money_thousands - 4'd1;
                            end
                        end
                    end
                    else if (money_value >= RIFLE_PRICE) begin
                        rifle_owned <= 1'b1;
                        equipped_weapon <= WEAPON_RIFLE;
                        ammo_refill_pulse <= 1'b1;
                        ammo_refill_hold <= 3'd4;
                        ammo_refill_weapon <= WEAPON_RIFLE;

                        debug_money_inhibit <= key_p;

                        if (money_at_cap) begin
                            // 9999 - 1000 = 8999
                            money_value <= 14'd8999;
                            money_thousands <= 4'd8;
                            money_hundreds <= 4'd9;
                            money_tens <= 4'd9;
                            money_ones <= 4'd9;
                        end
                        else begin
                            money_value <= money_value - RIFLE_PRICE;
                            money_thousands <= money_thousands - 4'd1;
                        end
                    end
                end

                // POWER machine: one-time 1000 purchase.
                else if (near_power_machine) begin
                    if (!power_on && (money_value >= POWER_PRICE)) begin
                        power_on <= 1'b1;
                        debug_money_inhibit <= key_p;

                        if (money_at_cap) begin
                            // 9999 - 1000 = 8999
                            money_value <= 14'd8999;
                            money_thousands <= 4'd8;
                            money_hundreds <= 4'd9;
                            money_tens <= 4'd9;
                            money_ones <= 4'd9;
                        end
                        else begin
                            money_value <= money_value - POWER_PRICE;
                            money_thousands <= money_thousands - 4'd1;
                        end
                    end
                end

                // V26D POWER UP buy menu.
                // Requires Power. Press E once to open, E again to close.
                else if (near_powerup_machine && power_on) begin
                    if (perk_count < 2'd2)
                        powerup_menu_open <= !powerup_menu_open;
                    else
                        powerup_menu_open <= 1'b0;
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

                                debug_money_inhibit <= key_p;

                                if (money_at_cap) begin
                                    // 9999 - 1500 = 8499
                                    money_value <= 14'd8499;
                                    money_thousands <= 4'd8;
                                    money_hundreds <= 4'd4;
                                    money_tens <= 4'd9;
                                    money_ones <= 4'd9;
                                end
                                else begin
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
                        end

                        WEAPON_SHOTGUN: begin
                            if (!shotgun_ultimate) begin
                                shotgun_ultimate <= 1'b1;
                                ultimate_upgrade_pulse <= 1'b1;
                                ultimate_upgrade_weapon <= WEAPON_SHOTGUN;

                                debug_money_inhibit <= key_p;

                                if (money_at_cap) begin
                                    // 9999 - 1500 = 8499
                                    money_value <= 14'd8499;
                                    money_thousands <= 4'd8;
                                    money_hundreds <= 4'd4;
                                    money_tens <= 4'd9;
                                    money_ones <= 4'd9;
                                end
                                else begin
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
                        end

                        default: begin
                            if (!rifle_ultimate) begin
                                rifle_ultimate <= 1'b1;
                                ultimate_upgrade_pulse <= 1'b1;
                                ultimate_upgrade_weapon <= WEAPON_RIFLE;

                                debug_money_inhibit <= key_p;

                                if (money_at_cap) begin
                                    // 9999 - 1500 = 8499
                                    money_value <= 14'd8499;
                                    money_thousands <= 4'd8;
                                    money_hundreds <= 4'd4;
                                    money_tens <= 4'd9;
                                    money_ones <= 4'd9;
                                end
                                else begin
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
                        end
                    endcase
                end

                // Existing 1000-point room doors.
                else if (money_value >= DOOR_PRICE) begin
                    if (near_ul && !door_ul_open) begin
                        door_ul_open <= 1'b1;
                        debug_money_inhibit <= key_p;

                        if (money_at_cap) begin
                            // 9999 - 1000 = 8999
                            money_value <= 14'd8999;
                            money_thousands <= 4'd8;
                            money_hundreds <= 4'd9;
                            money_tens <= 4'd9;
                            money_ones <= 4'd9;
                        end
                        else begin
                            money_value <= money_value - DOOR_PRICE;
                            money_thousands <= money_thousands - 4'd1;
                        end
                    end
                    else if (near_ur && !door_ur_open) begin
                        door_ur_open <= 1'b1;
                        debug_money_inhibit <= key_p;

                        if (money_at_cap) begin
                            // 9999 - 1000 = 8999
                            money_value <= 14'd8999;
                            money_thousands <= 4'd8;
                            money_hundreds <= 4'd9;
                            money_tens <= 4'd9;
                            money_ones <= 4'd9;
                        end
                        else begin
                            money_value <= money_value - DOOR_PRICE;
                            money_thousands <= money_thousands - 4'd1;
                        end
                    end
                    else if (near_ll && !door_ll_open) begin
                        door_ll_open <= 1'b1;
                        debug_money_inhibit <= key_p;

                        if (money_at_cap) begin
                            // 9999 - 1000 = 8999
                            money_value <= 14'd8999;
                            money_thousands <= 4'd8;
                            money_hundreds <= 4'd9;
                            money_tens <= 4'd9;
                            money_ones <= 4'd9;
                        end
                        else begin
                            money_value <= money_value - DOOR_PRICE;
                            money_thousands <= money_thousands - 4'd1;
                        end
                    end
                    else if (near_lr && !door_lr_open) begin
                        door_lr_open <= 1'b1;
                        debug_money_inhibit <= key_p;

                        if (money_at_cap) begin
                            // 9999 - 1000 = 8999
                            money_value <= 14'd8999;
                            money_thousands <= 4'd8;
                            money_hundreds <= 4'd9;
                            money_tens <= 4'd9;
                            money_ones <= 4'd9;
                        end
                        else begin
                            money_value <= money_value - DOOR_PRICE;
                            money_thousands <= money_thousands - 4'd1;
                        end
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
                     powerup_menu_open &&
                     power_on &&
                     (perk_count < 2'd2) &&
                     (money_value >= PERK_PRICE)) begin

                if (perk1_press && !perk_move_speed) begin
                    perk_move_speed <= 1'b1;
                    perk_count <= perk_count + 2'd1;

                    // Current count=1 means this purchase is the second perk.
                    if (perk_count == 2'd1)
                        powerup_menu_open <= 1'b0;

                    debug_money_inhibit <= key_p;

                    if (money_at_cap) begin
                        // 9999 - 1000 = 8999
                        money_value <= 14'd8999;
                        money_thousands <= 4'd8;
                        money_hundreds <= 4'd9;
                        money_tens <= 4'd9;
                        money_ones <= 4'd9;
                    end
                    else begin
                        money_value <= money_value - PERK_PRICE;
                        money_thousands <= money_thousands - 4'd1;
                    end
                end
                else if (perk2_press && !perk_zombie_slow) begin
                    perk_zombie_slow <= 1'b1;
                    perk_count <= perk_count + 2'd1;

                    // Current count=1 means this purchase is the second perk.
                    if (perk_count == 2'd1)
                        powerup_menu_open <= 1'b0;

                    debug_money_inhibit <= key_p;

                    if (money_at_cap) begin
                        // 9999 - 1000 = 8999
                        money_value <= 14'd8999;
                        money_thousands <= 4'd8;
                        money_hundreds <= 4'd9;
                        money_tens <= 4'd9;
                        money_ones <= 4'd9;
                    end
                    else begin
                        money_value <= money_value - PERK_PRICE;
                        money_thousands <= money_thousands - 4'd1;
                    end
                end
                else if (perk3_press && !perk_extra_hp) begin
                    perk_extra_hp <= 1'b1;
                    perk_count <= perk_count + 2'd1;

                    // Current count=1 means this purchase is the second perk.
                    if (perk_count == 2'd1)
                        powerup_menu_open <= 1'b0;

                    debug_money_inhibit <= key_p;

                    if (money_at_cap) begin
                        // 9999 - 1000 = 8999
                        money_value <= 14'd8999;
                        money_thousands <= 4'd8;
                        money_hundreds <= 4'd9;
                        money_tens <= 4'd9;
                        money_ones <= 4'd9;
                    end
                    else begin
                        money_value <= money_value - PERK_PRICE;
                        money_thousands <= money_thousands - 4'd1;
                    end
                end
                else if (perk4_press && !perk_fast_reload) begin
                    perk_fast_reload <= 1'b1;
                    perk_count <= perk_count + 2'd1;

                    // Current count=1 means this purchase is the second perk.
                    if (perk_count == 2'd1)
                        powerup_menu_open <= 1'b0;

                    debug_money_inhibit <= key_p;

                    if (money_at_cap) begin
                        // 9999 - 1000 = 8999
                        money_value <= 14'd8999;
                        money_thousands <= 4'd8;
                        money_hundreds <= 4'd9;
                        money_tens <= 4'd9;
                        money_ones <= 4'd9;
                    end
                    else begin
                        money_value <= money_value - PERK_PRICE;
                        money_thousands <= money_thousands - 4'd1;
                    end
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
            else if (hit_reward_pulse ||
                     (frame_tick && key_p && !debug_money_inhibit)) begin
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
