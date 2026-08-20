// ============================================================================
// VGA CONTROLLER - 640x480 @ ~60 Hz
// ============================================================================
module vga_controller_640x480 (
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire       pixel_tick,
    output wire       hsync,
    output wire       vsync,
    output wire       active_video,
    output wire [9:0] pixel_x,
    output wire [9:0] pixel_y,
    output reg        frame_tick
);

    localparam H_ACTIVE = 640;
    localparam H_FRONT  = 16;
    localparam H_SYNC   = 96;
    localparam H_TOTAL  = 800;

    localparam V_ACTIVE = 480;
    localparam V_FRONT  = 10;
    localparam V_SYNC   = 2;
    localparam V_TOTAL  = 525;

    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
            frame_tick <= 1'b0;
        end else begin
            frame_tick <= 1'b0;

            if (pixel_tick) begin
                if (h_cnt == H_TOTAL - 1) begin
                    h_cnt <= 10'd0;

                    if (v_cnt == V_TOTAL - 1) begin
                        v_cnt <= 10'd0;
                        frame_tick <= 1'b1;
                    end else begin
                        v_cnt <= v_cnt + 10'd1;
                    end
                end else begin
                    h_cnt <= h_cnt + 10'd1;
                end
            end
        end
    end

    assign hsync = ~((h_cnt >= H_ACTIVE + H_FRONT) &&
                     (h_cnt <  H_ACTIVE + H_FRONT + H_SYNC));

    assign vsync = ~((v_cnt >= V_ACTIVE + V_FRONT) &&
                     (v_cnt <  V_ACTIVE + V_FRONT + V_SYNC));

    assign active_video = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);
    assign pixel_x = h_cnt;
    assign pixel_y = v_cnt;

endmodule
