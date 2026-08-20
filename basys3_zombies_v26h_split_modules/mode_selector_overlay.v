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
