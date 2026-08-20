// ============================================================================
// FPGA -> PC SOUND EVENT SENDER
//
// Event bytes:
//   0xA1 = gun shot
//   0xA2 = target hit / destroyed
//   0xA3 = Speed Flick / 99 Bots target appeared
//
// Priority when several events happen together:
//   shot -> hit -> appearance.
// ============================================================================
module sound_event_sender (
    input  wire clk_100mhz,
    input  wire reset,

    input  wire pistol_shot_pulse,
    input  wire shotgun_shot_pulse,
    input  wire rifle_shot_pulse,

    input  wire hit_pulse,
    input  wire appear_pulse,
    input  wire round_change_pulse,

    input  wire       music_cmd_valid,
    input  wire [2:0] music_cmd_code,

    output wire RsTx
);

    // PC-side host script V5:
    //   A1 = pistol
    //   A4 = shotgun
    //   A5 = rifle
    //   A2 = zombie hit
    //   A3 = zombie appearance
    localparam [7:0] EVENT_PISTOL  = 8'hA1;
    localparam [7:0] EVENT_HIT     = 8'hA2;
    localparam [7:0] EVENT_APPEAR  = 8'hA3;
    localparam [7:0] EVENT_SHOTGUN = 8'hA4;
    localparam [7:0] EVENT_RIFLE   = 8'hA5;
    localparam [7:0] EVENT_ROUND   = 8'hA6;

    // V24C music-control bytes.
    localparam [7:0] EVENT_MUSIC_START_RESET = 8'hA7;
    localparam [7:0] EVENT_MUSIC_PAUSE       = 8'hA8;
    localparam [7:0] EVENT_MUSIC_RESUME      = 8'hA9;
    localparam [7:0] EVENT_MUSIC_STOP_RESET  = 8'hAA;

    reg pending_pistol;
    reg pending_shotgun;
    reg pending_rifle;
    reg pending_hit;
    reg pending_appear;
    reg pending_round;

    // Only one music transition can be outstanding at a time.
    reg       pending_music_valid;
    reg [2:0] pending_music_code;

    reg [7:0] tx_data;
    reg       tx_start;
    wire      tx_busy;

    uart_tx_115200 uart_tx_inst (
        .clk_100mhz(clk_100mhz),
        .reset(reset),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .RsTx(RsTx),
        .tx_busy(tx_busy)
    );

    always @(posedge clk_100mhz or posedge reset) begin
        if (reset) begin
            pending_pistol  <= 1'b0;
            pending_shotgun <= 1'b0;
            pending_rifle   <= 1'b0;
            pending_hit     <= 1'b0;
            pending_appear  <= 1'b0;
            pending_round   <= 1'b0;
            pending_music_valid <= 1'b0;
            pending_music_code  <= 3'd0;
            tx_data         <= 8'h00;
            tx_start        <= 1'b0;
        end
        else begin
            tx_start <= 1'b0;

            if (pistol_shot_pulse)
                pending_pistol <= 1'b1;
            if (shotgun_shot_pulse)
                pending_shotgun <= 1'b1;
            if (rifle_shot_pulse)
                pending_rifle <= 1'b1;
            if (hit_pulse)
                pending_hit <= 1'b1;
            if (appear_pulse)
                pending_appear <= 1'b1;
            if (round_change_pulse)
                pending_round <= 1'b1;

            if (music_cmd_valid) begin
                pending_music_valid <= 1'b1;
                pending_music_code  <= music_cmd_code;
            end

            if (!tx_busy && !tx_start) begin
                if (pending_music_valid) begin
                    case (pending_music_code)
                        3'd1: tx_data <= EVENT_MUSIC_START_RESET;
                        3'd2: tx_data <= EVENT_MUSIC_PAUSE;
                        3'd3: tx_data <= EVENT_MUSIC_RESUME;
                        3'd4: tx_data <= EVENT_MUSIC_STOP_RESET;
                        default: tx_data <= EVENT_MUSIC_STOP_RESET;
                    endcase

                    tx_start <= 1'b1;
                    pending_music_valid <= 1'b0;
                end
                else if (pending_pistol) begin
                    tx_data <= EVENT_PISTOL;
                    tx_start <= 1'b1;
                    pending_pistol <= 1'b0;
                end
                else if (pending_shotgun) begin
                    tx_data <= EVENT_SHOTGUN;
                    tx_start <= 1'b1;
                    pending_shotgun <= 1'b0;
                end
                else if (pending_rifle) begin
                    tx_data <= EVENT_RIFLE;
                    tx_start <= 1'b1;
                    pending_rifle <= 1'b0;
                end
                else if (pending_hit) begin
                    tx_data <= EVENT_HIT;
                    tx_start <= 1'b1;
                    pending_hit <= 1'b0;
                end
                else if (pending_round) begin
                    tx_data <= EVENT_ROUND;
                    tx_start <= 1'b1;
                    pending_round <= 1'b0;
                end
                else if (pending_appear) begin
                    tx_data <= EVENT_APPEAR;
                    tx_start <= 1'b1;
                    pending_appear <= 1'b0;
                end
            end
        end
    end

endmodule
