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
