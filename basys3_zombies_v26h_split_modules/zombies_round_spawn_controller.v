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
