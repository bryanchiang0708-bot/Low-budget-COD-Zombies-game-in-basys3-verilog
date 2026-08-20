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
