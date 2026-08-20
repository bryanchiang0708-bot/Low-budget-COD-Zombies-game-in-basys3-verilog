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
