module weapon_icon_overlay (
    input  wire [9:0] pixel_x,
    input  wire [9:0] pixel_y,
    input  wire [1:0] equipped_weapon,
    output reg        weapon_pixel
);
    localparam [1:0]
        WEAPON_PISTOL  = 2'd0,
        WEAPON_SHOTGUN = 2'd1,
        WEAPON_RIFLE   = 2'd2;

    always @(*) begin
        weapon_pixel = 1'b0;

        case (equipped_weapon)
            // ------------------------------------------------------------
            // SHOTGUN icon
            // ------------------------------------------------------------
            WEAPON_SHOTGUN: begin
                // Long barrel.
                if ((pixel_x >= 10'd557) && (pixel_x <= 10'd627) &&
                    (pixel_y >= 10'd416) && (pixel_y <= 10'd421))
                    weapon_pixel = 1'b1;

                // Receiver.
                if ((pixel_x >= 10'd580) && (pixel_x <= 10'd608) &&
                    (pixel_y >= 10'd422) && (pixel_y <= 10'd430))
                    weapon_pixel = 1'b1;

                // Pump.
                if ((pixel_x >= 10'd611) && (pixel_x <= 10'd623) &&
                    (pixel_y >= 10'd423) && (pixel_y <= 10'd428))
                    weapon_pixel = 1'b1;

                // Stock.
                if ((pixel_x >= 10'd556) && (pixel_x <= 10'd579) &&
                    (pixel_y >= 10'd422) && (pixel_y <= 10'd431))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd548) && (pixel_x <= 10'd560) &&
                    (pixel_y >= 10'd426) && (pixel_y <= 10'd435))
                    weapon_pixel = 1'b1;

                // Grip.
                if ((pixel_x >= 10'd590) && (pixel_x <= 10'd598) &&
                    (pixel_y >= 10'd431) && (pixel_y <= 10'd446))
                    weapon_pixel = 1'b1;
            end

            // ------------------------------------------------------------
            // RIFLE icon
            // ------------------------------------------------------------
            WEAPON_RIFLE: begin
                // Barrel.
                if ((pixel_x >= 10'd575) && (pixel_x <= 10'd627) &&
                    (pixel_y >= 10'd414) && (pixel_y <= 10'd419))
                    weapon_pixel = 1'b1;

                // Receiver/body.
                if ((pixel_x >= 10'd566) && (pixel_x <= 10'd608) &&
                    (pixel_y >= 10'd420) && (pixel_y <= 10'd429))
                    weapon_pixel = 1'b1;

                // Stock.
                if ((pixel_x >= 10'd548) && (pixel_x <= 10'd566) &&
                    (pixel_y >= 10'd417) && (pixel_y <= 10'd431))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd541) && (pixel_x <= 10'd551) &&
                    (pixel_y >= 10'd421) && (pixel_y <= 10'd434))
                    weapon_pixel = 1'b1;

                // Magazine.
                if ((pixel_x >= 10'd584) && (pixel_x <= 10'd596) &&
                    (pixel_y >= 10'd430) && (pixel_y <= 10'd440))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd587) && (pixel_x <= 10'd599) &&
                    (pixel_y >= 10'd441) && (pixel_y <= 10'd449))
                    weapon_pixel = 1'b1;

                // Grip.
                if ((pixel_x >= 10'd602) && (pixel_x <= 10'd609) &&
                    (pixel_y >= 10'd430) && (pixel_y <= 10'd444))
                    weapon_pixel = 1'b1;
            end

            // ------------------------------------------------------------
            // PISTOL icon
            // ------------------------------------------------------------
            default: begin
                if ((pixel_x >= 10'd566) && (pixel_x <= 10'd618) &&
                    (pixel_y >= 10'd414) && (pixel_y <= 10'd423))
                    weapon_pixel = 1'b1;

                if ((pixel_x >= 10'd618) && (pixel_x <= 10'd627) &&
                    (pixel_y >= 10'd416) && (pixel_y <= 10'd421))
                    weapon_pixel = 1'b1;

                if ((pixel_x >= 10'd576) && (pixel_x <= 10'd611) &&
                    (pixel_y >= 10'd424) && (pixel_y <= 10'd431))
                    weapon_pixel = 1'b1;

                if ((pixel_x >= 10'd586) && (pixel_x <= 10'd606) &&
                    (pixel_y >= 10'd432) && (pixel_y <= 10'd433))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd586) && (pixel_x <= 10'd588) &&
                    (pixel_y >= 10'd432) && (pixel_y <= 10'd441))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd604) && (pixel_x <= 10'd606) &&
                    (pixel_y >= 10'd432) && (pixel_y <= 10'd441))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd589) && (pixel_x <= 10'd603) &&
                    (pixel_y >= 10'd440) && (pixel_y <= 10'd442))
                    weapon_pixel = 1'b1;

                if ((pixel_x >= 10'd603) && (pixel_x <= 10'd613) &&
                    (pixel_y >= 10'd430) && (pixel_y <= 10'd437))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd601) && (pixel_x <= 10'd612) &&
                    (pixel_y >= 10'd438) && (pixel_y <= 10'd445))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd599) && (pixel_x <= 10'd610) &&
                    (pixel_y >= 10'd446) && (pixel_y <= 10'd453))
                    weapon_pixel = 1'b1;
                if ((pixel_x >= 10'd597) && (pixel_x <= 10'd608) &&
                    (pixel_y >= 10'd454) && (pixel_y <= 10'd461))
                    weapon_pixel = 1'b1;

                if ((pixel_x >= 10'd572) && (pixel_x <= 10'd576) &&
                    (pixel_y >= 10'd411) && (pixel_y <= 10'd413))
                    weapon_pixel = 1'b1;
            end
        endcase
    end
endmodule
