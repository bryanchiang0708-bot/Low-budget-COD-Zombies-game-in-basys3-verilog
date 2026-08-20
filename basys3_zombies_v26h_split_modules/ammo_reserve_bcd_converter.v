// ============================================================================
// V23 CURRENT MAGAZINE AMMO HUD
// Two white seven-segment digits above the weapon icon.
// ============================================================================
// ============================================================================
// V26B LOW-LUT RESERVE-AMMO BINARY -> BCD CONVERTER
//
// Converts only when value_in changes. Uses repeated subtraction over several
// 100 MHz clocks instead of a large combinational divider/network.
// Maximum input is 390, so conversion finishes essentially instantly to a
// human-visible 60 Hz HUD.
// ============================================================================
module ammo_reserve_bcd_converter (
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire [8:0] value_in,

    output reg  [3:0] hundreds,
    output reg  [3:0] tens,
    output reg  [3:0] ones
);
    localparam [1:0]
        BCD_IDLE     = 2'd0,
        BCD_HUNDREDS = 2'd1,
        BCD_TENS     = 2'd2;

    reg [1:0] state;
    reg [8:0] last_value;
    reg [8:0] work_value;
    reg [3:0] work_hundreds;
    reg [3:0] work_tens;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            state <= BCD_IDLE;
            last_value <= 9'h1FF;
            work_value <= 9'd0;
            work_hundreds <= 4'd0;
            work_tens <= 4'd0;

            hundreds <= 4'd0;
            tens <= 4'd0;
            ones <= 4'd0;
        end
        else begin
            case (state)
                BCD_IDLE: begin
                    if (value_in != last_value) begin
                        last_value <= value_in;
                        work_value <= value_in;
                        work_hundreds <= 4'd0;
                        work_tens <= 4'd0;
                        state <= BCD_HUNDREDS;
                    end
                end

                BCD_HUNDREDS: begin
                    if (work_value >= 9'd100) begin
                        work_value <= work_value - 9'd100;
                        work_hundreds <= work_hundreds + 4'd1;
                    end
                    else begin
                        state <= BCD_TENS;
                    end
                end

                BCD_TENS: begin
                    if (work_value >= 9'd10) begin
                        work_value <= work_value - 9'd10;
                        work_tens <= work_tens + 4'd1;
                    end
                    else begin
                        hundreds <= work_hundreds;
                        tens <= work_tens;
                        ones <= work_value[3:0];
                        state <= BCD_IDLE;
                    end
                end

                default:
                    state <= BCD_IDLE;
            endcase
        end
    end
endmodule
