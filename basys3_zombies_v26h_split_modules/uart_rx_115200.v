// ============================================================================
// UART RECEIVER - 115200 BAUD, 8N1
// ============================================================================
module uart_rx_115200 #(
    parameter integer CLOCK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE     = 115_200
)(
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire       RsRx,
    output reg [7:0]  rx_byte,
    output reg        rx_valid,
    output reg        framing_error
);

    localparam integer CLKS_PER_BIT  = CLOCK_FREQ_HZ / BAUD_RATE;
    localparam integer HALF_BIT_CLKS = CLKS_PER_BIT / 2;

    localparam [2:0]
        STATE_IDLE  = 3'd0,
        STATE_START = 3'd1,
        STATE_DATA  = 3'd2,
        STATE_STOP  = 3'd3;

    reg rx_meta;
    reg rx_sync;

    reg [2:0] state;
    reg [9:0] baud_counter;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= RsRx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            state <= STATE_IDLE;
            baud_counter <= 10'd0;
            bit_index <= 3'd0;
            shift_reg <= 8'd0;
            rx_byte <= 8'd0;
            rx_valid <= 1'b0;
            framing_error <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            framing_error <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    baud_counter <= 10'd0;
                    bit_index <= 3'd0;
                    if (!rx_sync)
                        state <= STATE_START;
                end

                STATE_START: begin
                    if (baud_counter == HALF_BIT_CLKS - 1) begin
                        baud_counter <= 10'd0;
                        if (!rx_sync) begin
                            bit_index <= 3'd0;
                            state <= STATE_DATA;
                        end else begin
                            state <= STATE_IDLE;
                        end
                    end else begin
                        baud_counter <= baud_counter + 10'd1;
                    end
                end

                STATE_DATA: begin
                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter <= 10'd0;
                        shift_reg[bit_index] <= rx_sync;

                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            state <= STATE_STOP;
                        end else begin
                            bit_index <= bit_index + 3'd1;
                        end
                    end else begin
                        baud_counter <= baud_counter + 10'd1;
                    end
                end

                STATE_STOP: begin
                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter <= 10'd0;

                        if (rx_sync) begin
                            rx_byte <= shift_reg;
                            rx_valid <= 1'b1;
                        end else begin
                            framing_error <= 1'b1;
                        end

                        state <= STATE_IDLE;
                    end else begin
                        baud_counter <= baud_counter + 10'd1;
                    end
                end

                default:
                    state <= STATE_IDLE;
            endcase
        end
    end

endmodule
