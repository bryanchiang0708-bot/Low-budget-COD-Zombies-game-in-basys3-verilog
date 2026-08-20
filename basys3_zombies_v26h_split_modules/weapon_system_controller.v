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
        PISTOL_DAMAGE       = 7'd3,
        SHOTGUN_DAMAGE      = 7'd20,
        RIFLE_DAMAGE        = 7'd5,

        // V26F Ultimate damage.
        PISTOL_DAMAGE_ULT   = 7'd5,
        SHOTGUN_DAMAGE_ULT  = 7'd30,
        RIFLE_DAMAGE_ULT    = 7'd8;

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
                shot_damage =
                    shotgun_ultimate ? SHOTGUN_DAMAGE_ULT : SHOTGUN_DAMAGE;
            end

            WEAPON_RIFLE: begin
                ammo_count = rifle_ammo;
                reserve_count = rifle_reserve;
                reserve_unlimited = 1'b0;
                shot_damage =
                    rifle_ultimate ? RIFLE_DAMAGE_ULT : RIFLE_DAMAGE;
            end

            default: begin
                ammo_count = pistol_ammo;
                reserve_count = 9'd0;
                reserve_unlimited = 1'b1;
                shot_damage =
                    pistol_ultimate ? PISTOL_DAMAGE_ULT : PISTOL_DAMAGE;
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
