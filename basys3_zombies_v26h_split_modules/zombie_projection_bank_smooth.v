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
