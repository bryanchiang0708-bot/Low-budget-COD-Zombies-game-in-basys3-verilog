// ============================================================================
// UART TRANSMITTER - 115200 BAUD, 8N1
// ============================================================================
module uart_tx_115200 #(
    parameter integer CLOCK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE     = 115_200
)(
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire [7:0] tx_data,
    input  wire       tx_start,

    output reg        RsTx,
    output reg        tx_busy
);

    localparam integer CLKS_PER_BIT = CLOCK_FREQ_HZ / BAUD_RATE;

    localparam [1:0]
        TX_IDLE  = 2'd0,
        TX_START = 2'd1,
        TX_DATA  = 2'd2,
        TX_STOP  = 2'd3;

    reg [1:0] state;
    reg [9:0] baud_counter;
    reg [2:0] bit_index;
    reg [7:0] tx_shift;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            state        <= TX_IDLE;
            baud_counter <= 10'd0;
            bit_index    <= 3'd0;
            tx_shift     <= 8'd0;
            RsTx         <= 1'b1;
            tx_busy      <= 1'b0;
        end else begin
            case (state)

                TX_IDLE: begin
                    RsTx         <= 1'b1;
                    tx_busy      <= 1'b0;
                    baud_counter <= 10'd0;
                    bit_index    <= 3'd0;

                    if (tx_start) begin
                        tx_shift <= tx_data;
                        tx_busy  <= 1'b1;
                        RsTx     <= 1'b0; // start bit
                        state    <= TX_START;
                    end
                end

                TX_START: begin
                    tx_busy <= 1'b1;
                    RsTx    <= 1'b0;

                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter <= 10'd0;
                        RsTx         <= tx_shift[0];
                        state        <= TX_DATA;
                    end else begin
                        baud_counter <= baud_counter + 10'd1;
                    end
                end

                TX_DATA: begin
                    tx_busy <= 1'b1;
                    RsTx    <= tx_shift[bit_index];

                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter <= 10'd0;

                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            RsTx      <= 1'b1;
                            state     <= TX_STOP;
                        end else begin
                            bit_index <= bit_index + 3'd1;
                            RsTx      <= tx_shift[bit_index + 3'd1];
                        end
                    end else begin
                        baud_counter <= baud_counter + 10'd1;
                    end
                end

                TX_STOP: begin
                    tx_busy <= 1'b1;
                    RsTx    <= 1'b1;

                    if (baud_counter == CLKS_PER_BIT - 1) begin
                        baud_counter <= 10'd0;
                        tx_busy      <= 1'b0;
                        state        <= TX_IDLE;
                    end else begin
                        baud_counter <= baud_counter + 10'd1;
                    end
                end

                default: begin
                    state   <= TX_IDLE;
                    RsTx    <= 1'b1;
                    tx_busy <= 1'b0;
                end

            endcase
        end
    end

endmodule
