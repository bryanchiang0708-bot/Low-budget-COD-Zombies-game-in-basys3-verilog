# Basys3 Zombies V26H — Split Verilog Modules

This folder was generated from:

`top_zombies_map_v26h_paid_ammo_refill.v`

Each Verilog module is now stored in its own `.v` source file.

## Top module

`top_aimlab.v`

Set `top_aimlab` as the Vivado top module.

## Module files

- `top_aimlab.v`
- `spawn_raised_room_overlay.v`
- `zombies_economy_doors.v`
- `weapon_system_controller.v`
- `money_hud_overlay.v`
- `sound_event_sender.v`
- `uart_tx_115200.v`
- `vga_controller_640x480.v`
- `uart_rx_115200.v`
- `input_packet_parser.v`
- `sensitivity_button_controller.v`
- `game_flow_overlay.v`
- `pause_button_controller.v`
- `pause_word_overlay.v`
- `camera_movement_controller.v`
- `game_controller.v`
- `lightweight_target_controller.v`
- `zombies_round_spawn_controller.v`
- `zombie_player_health.v`
- `zombie_agent_round.v`
- `zombie_aim_hit_selector_seq.v`
- `zombie_projection_bank_smooth.v`
- `zombie_projection_fast.v`
- `zombie_pill_pixel.v`
- `player_hp_hud_overlay.v`
- `powerup_perk_icon_overlay.v`
- `weapon_icon_overlay.v`
- `ammo_reserve_bcd_converter.v`
- `weapon_ammo_hud_overlay.v`
- `reload_timer_overlay.v`
- `shared_station_label_overlay.v`
- `round_hud_overlay.v`
- `single_zombie_timing_safe.v`
- `hp_debug_display.v`
- `target_projection.v`
- `zombies_map_wall_raycaster.v`
- `aimlab_renderer.v`
- `mode_selector_overlay.v`
- `seven_segment_score_display.v`
- `trig_q17.v`

## Count

Total Verilog modules: **40**

## Vivado

Add all `.v` files in this folder as Design Sources.  
The included `filelist.f` lists them in their original source order.

No logic was intentionally changed; this operation only separated the original
combined source into one module per file.
