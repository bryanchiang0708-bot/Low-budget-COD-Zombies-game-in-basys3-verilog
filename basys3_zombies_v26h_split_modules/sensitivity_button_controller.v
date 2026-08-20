// ============================================================================
// SENSITIVITY BUTTON CONTROLLER
// Basys 3 T18 pushbutton, active high.
//
// Debounce: ~20 ms @ 100 MHz.
// Each clean button press cycles:
//     1 -> 2 -> 3 -> 4 -> 1
// ============================================================================
module sensitivity_button_controller (
    input  wire       clk_100mhz,
    input  wire       reset,
    input  wire       button_in,
    output reg [2:0]  sensitivity_level
);

    localparam [20:0] DEBOUNCE_COUNT_MAX = 21'd1_999_999;

    reg button_meta;
    reg button_sync;
    reg button_stable;
    reg button_stable_d;
    reg [20:0] debounce_counter;

    wire button_pressed =
        button_stable && !button_stable_d;

    // Synchronize asynchronous mechanical pushbutton.
    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            button_meta <= 1'b0;
            button_sync <= 1'b0;
        end else begin
            button_meta <= button_in;
            button_sync <= button_meta;
        end
    end

    // Debounce.
    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            button_stable    <= 1'b0;
            debounce_counter <= 21'd0;
        end else begin
            if (button_sync == button_stable) begin
                debounce_counter <= 21'd0;
            end else begin
                if (debounce_counter == DEBOUNCE_COUNT_MAX) begin
                    button_stable    <= button_sync;
                    debounce_counter <= 21'd0;
                end else begin
                    debounce_counter <= debounce_counter + 21'd1;
                end
            end
        end
    end

    // Rising-edge history.
    always @(posedge clk_100mhz or posedge reset) begin
        if (reset)
            button_stable_d <= 1'b0;
        else
            button_stable_d <= button_stable;
    end

    // 1x -> 2x -> 3x -> 4x -> 1x
    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            sensitivity_level <= 3'd1;
        end else if (button_pressed) begin
            if (sensitivity_level >= 3'd4)
                sensitivity_level <= 3'd1;
            else
                sensitivity_level <= sensitivity_level + 3'd1;
        end
    end

endmodule
