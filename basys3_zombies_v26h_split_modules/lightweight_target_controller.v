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
