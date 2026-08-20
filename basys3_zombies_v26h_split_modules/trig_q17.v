// ============================================================================
// TRIG LUT - Q1.7
// 128 = +1.0
// ============================================================================
module trig_q17 (
    input  wire [7:0]        angle,
    output reg signed [8:0]  sin_value,
    output reg signed [8:0]  cos_value
);

    function signed [8:0] sin_quarter;
        input [6:0] qidx;
        begin
            case (qidx)
                7'd0: sin_quarter = 9'sd0;
                7'd1: sin_quarter = 9'sd3;
                7'd2: sin_quarter = 9'sd6;
                7'd3: sin_quarter = 9'sd9;
                7'd4: sin_quarter = 9'sd13;
                7'd5: sin_quarter = 9'sd16;
                7'd6: sin_quarter = 9'sd19;
                7'd7: sin_quarter = 9'sd22;
                7'd8: sin_quarter = 9'sd25;
                7'd9: sin_quarter = 9'sd28;
                7'd10: sin_quarter = 9'sd31;
                7'd11: sin_quarter = 9'sd34;
                7'd12: sin_quarter = 9'sd37;
                7'd13: sin_quarter = 9'sd40;
                7'd14: sin_quarter = 9'sd43;
                7'd15: sin_quarter = 9'sd46;
                7'd16: sin_quarter = 9'sd49;
                7'd17: sin_quarter = 9'sd52;
                7'd18: sin_quarter = 9'sd55;
                7'd19: sin_quarter = 9'sd58;
                7'd20: sin_quarter = 9'sd60;
                7'd21: sin_quarter = 9'sd63;
                7'd22: sin_quarter = 9'sd66;
                7'd23: sin_quarter = 9'sd68;
                7'd24: sin_quarter = 9'sd71;
                7'd25: sin_quarter = 9'sd74;
                7'd26: sin_quarter = 9'sd76;
                7'd27: sin_quarter = 9'sd79;
                7'd28: sin_quarter = 9'sd81;
                7'd29: sin_quarter = 9'sd84;
                7'd30: sin_quarter = 9'sd86;
                7'd31: sin_quarter = 9'sd88;
                7'd32: sin_quarter = 9'sd91;
                7'd33: sin_quarter = 9'sd93;
                7'd34: sin_quarter = 9'sd95;
                7'd35: sin_quarter = 9'sd97;
                7'd36: sin_quarter = 9'sd99;
                7'd37: sin_quarter = 9'sd101;
                7'd38: sin_quarter = 9'sd103;
                7'd39: sin_quarter = 9'sd105;
                7'd40: sin_quarter = 9'sd106;
                7'd41: sin_quarter = 9'sd108;
                7'd42: sin_quarter = 9'sd110;
                7'd43: sin_quarter = 9'sd111;
                7'd44: sin_quarter = 9'sd113;
                7'd45: sin_quarter = 9'sd114;
                7'd46: sin_quarter = 9'sd116;
                7'd47: sin_quarter = 9'sd117;
                7'd48: sin_quarter = 9'sd118;
                7'd49: sin_quarter = 9'sd119;
                7'd50: sin_quarter = 9'sd121;
                7'd51: sin_quarter = 9'sd122;
                7'd52: sin_quarter = 9'sd122;
                7'd53: sin_quarter = 9'sd123;
                7'd54: sin_quarter = 9'sd124;
                7'd55: sin_quarter = 9'sd125;
                7'd56: sin_quarter = 9'sd126;
                7'd57: sin_quarter = 9'sd126;
                7'd58: sin_quarter = 9'sd127;
                7'd59: sin_quarter = 9'sd127;
                7'd60: sin_quarter = 9'sd127;
                7'd61: sin_quarter = 9'sd128;
                7'd62: sin_quarter = 9'sd128;
                7'd63: sin_quarter = 9'sd128;
                7'd64: sin_quarter = 9'sd128;
                default: sin_quarter = 9'sd0;
            endcase
        end
    endfunction

    function signed [8:0] sin_full;
        input [7:0] a;
        reg [5:0] idx;
        reg [6:0] reflected_idx;
        begin
            idx = a[5:0];
            reflected_idx = 7'd0;

            case (a[7:6])
                2'b00:
                    sin_full = sin_quarter({1'b0, idx});

                2'b01: begin
                    reflected_idx = 7'd64 - {1'b0, idx};
                    sin_full = sin_quarter(reflected_idx);
                end

                2'b10:
                    sin_full = -sin_quarter({1'b0, idx});

                2'b11: begin
                    reflected_idx = 7'd64 - {1'b0, idx};
                    sin_full = -sin_quarter(reflected_idx);
                end
            endcase
        end
    endfunction

    always @(*) begin
        sin_value = sin_full(angle);
        cos_value = sin_full(angle + 8'd64);
    end

endmodule
