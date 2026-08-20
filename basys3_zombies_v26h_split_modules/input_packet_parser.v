// ============================================================================
// 3-BYTE PACKET PARSER + CONTINUOUS INPUT STATE + WATCHDOG
// ============================================================================
module input_packet_parser (
    input  wire             clk_100mhz,
    input  wire             reset,
    input  wire [7:0]       rx_byte,
    input  wire             rx_valid,

    output reg signed [7:0] mouse_dx,
    output reg signed [7:0] mouse_dy,
    output reg              mouse_move_valid,

    output reg              key_w,
    output reg              key_a,
    output reg              key_s,
    output reg              key_d,
    output reg              key_e,
    output reg              key_p,
    output reg              key_r,
    output reg              key_y,
    output reg              key_1,
    output reg              key_2,
    output reg              key_3,
    output reg              key_4,
    output reg              key_space,

    output reg              left_mouse,
    output reg              right_mouse,
    output reg              left_click_pulse,
    output reg              wheel_up_pulse,
    output reg              wheel_down_pulse,
    output reg              host_alive
);

    localparam [7:0] PKT_MOUSE_MOVE  = 8'hC1;
    localparam [7:0] PKT_MOUSE_LEFT  = 8'hD0;
    localparam [7:0] PKT_MOUSE_RIGHT = 8'hD1;
    localparam [7:0] PKT_MOUSE_WHEEL = 8'hD2;
    localparam [7:0] PKT_KEYBOARD    = 8'hE0;
    localparam [7:0] PKT_HEARTBEAT   = 8'hF0;

    localparam [24:0] WATCHDOG_LIMIT = 25'd24_999_999;

    localparam [1:0]
        WAIT_HEADER = 2'd0,
        WAIT_B1     = 2'd1,
        WAIT_B2     = 2'd2;

    reg [1:0] parser_state;
    reg [7:0] header;
    reg [7:0] byte1;
    reg [24:0] watchdog_counter;

    wire known_header =
        (rx_byte == PKT_MOUSE_MOVE)  ||
        (rx_byte == PKT_MOUSE_LEFT)  ||
        (rx_byte == PKT_MOUSE_RIGHT) ||
        (rx_byte == PKT_MOUSE_WHEEL) ||
        (rx_byte == PKT_KEYBOARD)    ||
        (rx_byte == PKT_HEARTBEAT);

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            parser_state <= WAIT_HEADER;
            header <= 8'd0;
            byte1 <= 8'd0;

            mouse_dx <= 8'sd0;
            mouse_dy <= 8'sd0;
            mouse_move_valid <= 1'b0;

            key_w <= 1'b0;
            key_a <= 1'b0;
            key_s <= 1'b0;
            key_d <= 1'b0;
            key_e <= 1'b0;
            key_p <= 1'b0;
            key_r <= 1'b0;
            key_y <= 1'b0;
            key_1 <= 1'b0;
            key_2 <= 1'b0;
            key_3 <= 1'b0;
            key_4 <= 1'b0;
            key_space <= 1'b0;

            left_mouse <= 1'b0;
            right_mouse <= 1'b0;
            left_click_pulse <= 1'b0;
            wheel_up_pulse <= 1'b0;
            wheel_down_pulse <= 1'b0;

            watchdog_counter <= WATCHDOG_LIMIT;
            host_alive <= 1'b0;
        end else begin
            mouse_move_valid <= 1'b0;
            left_click_pulse <= 1'b0;
            wheel_up_pulse <= 1'b0;
            wheel_down_pulse <= 1'b0;

            if (watchdog_counter < WATCHDOG_LIMIT)
                watchdog_counter <= watchdog_counter + 25'd1;
            else begin
                host_alive <= 1'b0;
                key_w <= 1'b0;
                key_a <= 1'b0;
                key_s <= 1'b0;
                key_d <= 1'b0;
                key_e <= 1'b0;
                key_p <= 1'b0;
                key_r <= 1'b0;
                key_y <= 1'b0;
                key_1 <= 1'b0;
                key_2 <= 1'b0;
                key_3 <= 1'b0;
                key_4 <= 1'b0;
                key_space <= 1'b0;
                left_mouse <= 1'b0;
                right_mouse <= 1'b0;
            end

            if (rx_valid) begin
                case (parser_state)

                    WAIT_HEADER: begin
                        if (known_header) begin
                            header <= rx_byte;
                            parser_state <= WAIT_B1;
                        end
                    end

                    WAIT_B1: begin
                        byte1 <= rx_byte;
                        parser_state <= WAIT_B2;
                    end

                    WAIT_B2: begin
                        parser_state <= WAIT_HEADER;

                        case (header)
                            PKT_MOUSE_MOVE: begin
                                mouse_dx <= $signed(byte1);
                                mouse_dy <= $signed(rx_byte);
                                mouse_move_valid <= 1'b1;
                            end

                            PKT_MOUSE_LEFT: begin
                                left_mouse <= byte1[0];
                                if (byte1[0])
                                    left_click_pulse <= 1'b1;
                            end

                            PKT_MOUSE_RIGHT: begin
                                right_mouse <= byte1[0];
                            end

                            PKT_MOUSE_WHEEL: begin
                                if ($signed(byte1) > 8'sd0)
                                    wheel_up_pulse <= 1'b1;
                                else if ($signed(byte1) < 8'sd0)
                                    wheel_down_pulse <= 1'b1;
                            end

                            PKT_KEYBOARD: begin
                                case (byte1)
                                    8'h77: key_w <= rx_byte[0];
                                    8'h61: key_a <= rx_byte[0];
                                    8'h73: key_s <= rx_byte[0];
                                    8'h64: key_d <= rx_byte[0];
                                    8'h65: key_e <= rx_byte[0];
                                    8'h70: key_p <= rx_byte[0];
                                    8'h72: key_r <= rx_byte[0];
                                    8'h79: key_y <= rx_byte[0];
                                    8'h31: key_1 <= rx_byte[0];
                                    8'h32: key_2 <= rx_byte[0];
                                    8'h33: key_3 <= rx_byte[0];
                                    8'h34: key_4 <= rx_byte[0];
                                    8'h20: key_space <= rx_byte[0];
                                    default: ;
                                endcase
                            end

                            PKT_HEARTBEAT: begin
                                watchdog_counter <= 25'd0;
                                host_alive <= 1'b1;
                            end

                            default: ;
                        endcase
                    end

                    default:
                        parser_state <= WAIT_HEADER;
                endcase
            end
        end
    end

endmodule
