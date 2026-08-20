// ============================================================================
// PAUSE BUTTON CONTROLLER
// Basys 3 T17 / BTNR, active high.
//
// Debounce: ~20 ms @ 100 MHz.
// Each clean rising edge toggles pause_active.
// ============================================================================
module pause_button_controller (
    input  wire clk_100mhz,
    input  wire reset,
    input  wire frame_tick,
    input  wire button_in,
    output reg  pause_active
);
    // LUT-optimized T17 pause input:
    // synchronize at 100 MHz, then sample once per VGA frame (~60 Hz).
    // A press toggles once; release re-arms the next press.
    reg button_meta;
    reg button_sync;
    reg button_held;

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            button_meta <= 1'b0;
            button_sync <= 1'b0;
        end
        else begin
            button_meta <= button_in;
            button_sync <= button_meta;
        end
    end

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            button_held <= 1'b0;
            pause_active <= 1'b0;
        end
        else if (frame_tick) begin
            if (button_sync) begin
                if (!button_held) begin
                    pause_active <= ~pause_active;
                    button_held <= 1'b1;
                end
            end
            else begin
                button_held <= 1'b0;
            end
        end
    end
endmodule
