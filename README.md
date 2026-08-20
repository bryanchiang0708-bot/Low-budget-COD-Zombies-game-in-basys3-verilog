# Low-budget-COD-Zombies-game-in-basys3-verilog
So I'm basically bored and decided to create a COD Zombies in verilog.

Because it's 2AM when I'm typing this so I decide to let ChatGPT to explain what is going on with the code. But I will be sharing my thought's about the project.

Originally I just want to learn some verilog code and logic. So I ask my friend for something he learned in his class for self-learning. And IDK why I got more interest in the VGA output of the board. Then I wondered "Can I make a shooting game in verilog?"(Because I like shooter games). So I began my first experiment, which is creating a 3D environment for the shooter game. I know I can't code from scratch so I started vibecoding with Gemini and the result turned out to be shit. So I turned to ChatGPT and Claude and both have there pro's and con's. Eventually I sticked to throwing hard problems to GPT and easier ones to Gemini, which works pretty well. And when the 3D environment and camera was created. I started thinking about what game I should make. I made an aimlabs-like game for experiment but that's not what I wanted. But before landing my goal on COD zombies(which IDK why appeared in my mind), I implemented a lot of basic functions such as aimming, mouse and keyboard movement and target shooting. After I added some mode like the hard bot and 100 bots mode in Valorant I moved on to the Zombies project, in which I met a lot of difficultities. For example the timing and LUT kept screaming errors so I have to improve the code logic occasionally after adding some functions. It gotten so bad that the wall was roken for a day. But eventually I found a way to fix it by makeing the code run in multiple clock cycle instead of one. And of course the limited LUT made ChatGPT cried for one night. But after one week of adjusting. This is the result.

TBH I think there are some details I wanted to add but due to the hardware limitations (AKA LUT numbers) I decided that this is very close to the limit. I'm happy with the results. But I think I'll need to learn basic verilog again because I've been vibecoding too much. Also maybe just make a game in Unity or Godots or something is better I guess.


# Basys 3 FPGA Zombies FPS

A first-person zombie survival game implemented primarily in **Verilog on a Digilent Basys 3 FPGA**, with a small **Python host program** used for PC mouse/keyboard input and audio output.

The gameplay is inspired by the round-based survival loop of **Call of Duty Zombies**: the player starts in a central room, fights increasingly strong waves of zombies, earns money by shooting them, opens additional rooms, purchases weapons and ammunition, turns on the power, buys perks, and upgrades weapons.

> This is an educational, non-commercial FPGA project inspired by the gameplay style of Call of Duty Zombies. It is not affiliated with or endorsed by Activision or Treyarch.

---

## 1. What the Game Is Like

The game is designed as a compact FPGA interpretation of a COD Zombies-style survival mode.

The player views the game through a **640×480 VGA first-person perspective**. Movement, aiming, collision detection, zombie AI, weapons, economy, round progression, and rendering are all performed on the FPGA.

The Python program does **not** simulate the game world or render the graphics. Its main jobs are to send PC input to the FPGA and play sounds when the FPGA reports gameplay events.

### Core Gameplay Loop

1. Press **Y** to begin the game.
2. Zombies spawn from rooms surrounding the playable map.
3. Use the mouse to aim and **WASD** to move through the map.
4. Shoot zombies to damage them and earn money.
5. Survive until the current round's zombie quota has been defeated.
6. A new round begins after a short grace period.
7. Spend money to:
   - open new rooms,
   - buy the shotgun or rifle,
   - refill ammunition,
   - activate Power,
   - buy up to two Power Up perks,
   - apply an Ultimate upgrade to each gun.
8. Zombies gain additional HP as the rounds increase.
9. If the player's HP reaches zero, the game enters the **YOU DIED** screen. Press **Y** to restart the run.

### Map and Rendering

The world is made from five connected playable rooms plus seven raised zombie spawn rooms.

The main map is rendered using a **2.5D column-based ray-casting system**. For every horizontal VGA screen column, the FPGA finds the closest visible wall and stores its distance. That depth information is then used by the renderer to draw the walls, floor, ceiling, doors, weapon stations, Power machines, and to correctly hide zombies that are behind walls.

This approach provides a first-person 3D appearance without requiring a full polygon GPU or software renderer.

### Zombie Rounds

- Round 1 starts with **6 zombies**.
- The round population increases through later rounds and eventually caps at **45 zombies per round**.
- Up to **8 zombies can be active at the same time**.
- Dead zombie slots are reused for later spawns.
- Each round begins with approximately a **5 second grace period**.
- Spawn timing uses pseudo-random, Poisson-style inter-arrival delays so zombies do not appear at perfectly fixed intervals.
- Side-room zombie spawns become available when their corresponding doors are opened.
- Zombie HP is approximately:

```text
Zombie HP = 9 + current round
```

For example, a Round 1 zombie has 10 HP.

### Zombie Combat

Zombies independently navigate toward the player. When a direct path is blocked, the navigation system can choose intermediate navigation nodes instead of simply walking through walls.

When a zombie reaches melee range:

- attack wind-up: about **0.5 s**
- damage: **1 HP**
- recovery: about **0.7 s**

The zombie changes to a yellow attack color during the attack state.

The player starts with **3 HP**. After avoiding damage for approximately 5 seconds, HP regenerates. The +1 HP perk increases maximum HP to 4.

### Weapons

| Weapon | Base Damage | Base Magazine | Reserve Ammo | Reload | Purchase / Refill |
| --- | ---: | ---: | ---: | ---: | ---: |
| Pistol | 3 | 20 | Unlimited | 1.2 s | Starting weapon |
| Shotgun | 20 | 10 | 80 | 2.0 s | 500 |
| Rifle | 5 | 30 | 300 | 1.8 s | 1000 |

The pistol and shotgun are semi-automatic. The rifle is full-auto at approximately 10 rounds per second before upgrading.

Returning to an owned weapon's wall station and pressing **E** purchases a full ammunition refill:

- Shotgun MAX AMMO: **500**
- Rifle MAX AMMO: **1000**

### Power System

The **POWER** machine costs **1000**.

Before Power is activated, the POWER UP and ULTIMATE machines remain disabled. Their wall labels display their current `ON` / `OFF` state.

### Power Up Perks

After Power is enabled, stand near the POWER UP machine and press **E** to open the perk menu.

The player may buy a maximum of **two** perks. Each perk costs **1000**.

| Numpad Key | Perk | Effect |
| --- | --- | --- |
| 1 | Move Speed | Increases player movement speed |
| 2 | Zombie Slow | Reduces zombie movement speed by 30% |
| 3 | Extra HP | Raises maximum player HP from 3 to 4 |
| 4 | Fast Reload | Reduces reload time by 30% |

Purchased perks also appear as small icons beside the HP display.

### Ultimate Weapon Upgrade

The ULTIMATE machine costs **1500 per gun** and requires Power to be ON.

The currently equipped gun is upgraded when the player interacts with the machine.

Ultimate upgrades increase magazine capacity and reserve ammunition by approximately 30%, shorten reload time by 30%, and increase weapon damage.

| Weapon | Ultimate Damage | Ultimate Magazine | Ultimate Reserve |
| --- | ---: | ---: | ---: |
| Pistol | 5 | 26 | Unlimited |
| Shotgun | 30 | 13 | 104 |
| Rifle | 8 | 39 | 390 |

The rifle also gains approximately **30% higher fire rate**.

An Ultimate-upgraded equipped weapon is displayed with a **purple weapon icon**.

### Controls

| Control | Action |
| --- | --- |
| Mouse | Look / aim |
| Left Mouse Button | Fire |
| Mouse Wheel | Cycle through owned weapons |
| W / A / S / D | Move |
| Space | Jump |
| R | Reload |
| E | Buy / interact |
| Y | Start / restart |
| Numpad 1–4 | Select Power Up perk while the perk menu is open |
| Basys 3 T18 button | Cycle mouse sensitivity |
| Basys 3 T17 button | Pause / resume |
| P | Debug money input used during development |
| F1 in Python window | Exit host program |

---

## 2. Python Host Program

The Python host program is:

```text
project_mice_v2.py
```

It uses **pygame**, **pynput**, and **pyserial**.

The Python program acts as a bridge between standard PC peripherals and the Basys 3 USB-UART interface.

### What Python Does

The Python code handles four main jobs:

1. **Mouse input**
   - captures relative mouse X/Y movement,
   - captures left/right mouse button state,
   - captures the mouse wheel for weapon switching.

2. **Keyboard input**
   - sends key-down and key-up state,
   - normalizes alphabetic controls to lowercase ASCII,
   - converts Windows Numpad keys into normal ASCII digits so Numpad 1–4 can be used in the Power Up menu,
   - suppresses OS key-repeat packets while a key is held.

3. **Connection heartbeat**
   - sends a heartbeat packet at approximately 20 Hz,
   - allows the FPGA to detect if the host program has stopped or disconnected.

4. **Audio output**
   - listens for event bytes sent from the FPGA,
   - plays pistol, shotgun, rifle, zombie hit, zombie spawn, and round-change sounds,
   - starts, pauses, resumes, and resets optional background music based on FPGA game state.

The gun and event sound effects are synthesized directly in Python. The optional background track is loaded from a local file named:

```text
zombies_background_music.mp3
```

The music file itself should not be included in the repository unless you have permission to redistribute it.

### PC → FPGA UART Protocol

All normal input packets are exactly **3 bytes** long and are transmitted at **115200 baud**.

| Header | Byte 1 | Byte 2 | Meaning |
| --- | --- | --- | --- |
| `0xC1` | `dx` | `dy` | Relative mouse movement, signed 8-bit |
| `0xD0` | state | `0x00` | Left mouse button |
| `0xD1` | state | `0x00` | Right mouse button |
| `0xD2` | wheel delta | `0x00` | Mouse wheel direction |
| `0xE0` | ASCII key | state | Keyboard key-down / key-up |
| `0xF0` | `0x00` | `0x00` | Heartbeat |

Examples:

```text
E0 77 01   -> W key down
E0 77 00   -> W key up
E0 65 01   -> E key down
E0 31 01   -> Numpad/keyboard 1 down
D0 01 00   -> left mouse pressed
C1 05 FD   -> mouse moved +5 X and -3 Y
```

Mouse deltas are accumulated by Python and transmitted at a stable rate of approximately **120 Hz**.

### FPGA → PC Event Protocol

The reverse UART direction is used for lightweight one-byte gameplay events.

| Event | Meaning |
| --- | --- |
| `0xA1` | Pistol shot |
| `0xA2` | Zombie hit |
| `0xA3` | Zombie appearance / spawn sound |
| `0xA4` | Shotgun shot |
| `0xA5` | Rifle shot |
| `0xA6` | New round |
| `0xA7` | Start/restart background music from the beginning |
| `0xA8` | Pause background music |
| `0xA9` | Resume background music |
| `0xAA` | Stop/reset background music |

The FPGA therefore remains the authority for game state. Python only reacts to events generated by the hardware.

---

## 3. How the Verilog Input Decoder Works

The FPGA input path is split into two stages:

```text
PC keyboard / mouse
        ↓
Python host
        ↓  USB-UART @ 115200 baud
uart_rx_115200
        ↓  rx_byte + rx_valid
input_packet_parser
        ↓
key states / mouse deltas / click pulses / wheel pulses
        ↓
Camera, weapon, economy and game-control modules
```

### `uart_rx_115200.v`

This module receives the asynchronous UART signal from the Basys 3 USB-UART interface and converts the serial bit stream into 8-bit bytes.

When a complete valid byte is received it provides:

```text
rx_byte
rx_valid
```

`rx_valid` is a one-clock indication that a new byte is ready.

### `input_packet_parser.v`

The packet parser converts the raw UART bytes into useful game controls.

It uses a small three-state FSM:

```text
WAIT_HEADER
    ↓
WAIT_B1
    ↓
WAIT_B2
    ↓
WAIT_HEADER
```

The first byte identifies the packet type. The following two bytes contain the packet data.

For example:

```text
E0 77 01
```

is decoded as:

```text
Header = keyboard packet
ASCII 0x77 = 'w'
State = pressed
```

and therefore sets:

```text
key_w = 1
```

When the matching key-up packet arrives, `key_w` returns to 0.

The decoder directly recognizes:

```text
W A S D
E
P
R
Y
1 2 3 4
Space
```

It also maintains left/right mouse state and generates one-clock pulses for:

```text
left_click_pulse
wheel_up_pulse
wheel_down_pulse
mouse_move_valid
```

### Host Watchdog

The parser contains a watchdog counter.

Python sends heartbeat packet `F0 00 00` at approximately 20 Hz. Every heartbeat resets the watchdog and marks:

```text
host_alive = 1
```

If packets stop arriving long enough for the watchdog to expire, the FPGA clears the keyboard and mouse states. This prevents a disconnected PC from leaving a movement key or mouse button permanently stuck in the pressed state.

### Reverse UART Path

The opposite communication direction is:

```text
Gameplay event
      ↓
sound_event_sender
      ↓
uart_tx_115200
      ↓
USB-UART
      ↓
Python event listener
      ↓
Sound effect / music control
```

---

## 4. Hardware / Build Notes

Target board:

```text
Digilent Basys 3
Xilinx Artix-7 XC7A35T
100 MHz system clock
640×480 VGA output
115200-baud USB-UART
```

Set the Vivado top module to:

```text
top_aimlab
```

Add all Verilog source files as Design Sources and use the Basys 3 constraints file for VGA, UART, buttons and seven-segment display pins.

The included `filelist.f` lists the split Verilog modules in their original source order.

---

# 5. Verilog Module Breakdown

The following section describes every Verilog module included in the split-source version. The modules are ordered roughly from the first-person camera/ray-casting pipeline through zombie AI, weapons, UI, interactables and system support.

## 5.1 Camera, World Geometry and Ray-Casting

### `camera_movement_controller.v`

The player's first-person camera controller.

It handles mouse yaw/pitch, WASD movement, normalized diagonal movement, jumping/gravity, collision with the five-room map, door-dependent access to side rooms, and the movement-speed perk. It outputs the player's world-space `camera_x`, `camera_y`, `camera_z`, `camera_yaw`, and `camera_pitch` values used by the renderer and AI.

### `trig_q17.v`

A shared fixed-point sine/cosine lookup table using Q1.7-style values where approximately `128 = 1.0`.

It avoids expensive floating-point trigonometry and is used by the camera, wall ray-caster, and projection modules.

### `zombies_map_wall_raycaster.v`

The core first-person wall ray-casting engine.

The map contains axis-aligned wall segments representing the five connected rooms, doors, weapon-buy walls, Power-related machines, and zombie spawn-room geometry. Instead of testing every wall against every VGA pixel combinationally, the module checks wall segments sequentially and caches the closest wall result for each of the 640 screen columns.

It outputs wall depth plus subtype flags such as door, shotgun station, rifle station, Power, Power Up, Ultimate, and Lucky Box wall types.

### `aimlab_renderer.v`

Converts the camera position and cached wall depth into the main 640×480 first-person scene.

It renders the wall height, floor grid, ceiling grid and base world colors. The wall geometry itself comes from `zombies_map_wall_raycaster`.

### `spawn_raised_room_overlay.v`

Display-only renderer for the raised zombie spawn rooms.

It projects the raised blue spawn-room floor/roof/entry geometry into the first-person view while keeping the gameplay geometry independent from the renderer.

### `vga_controller_640x480.v`

Generates the VGA timing signals for a 640×480 display, including pixel coordinates, active-video indication, horizontal sync, vertical sync and frame timing.

### `zombie_projection_bank_smooth.v`

Projects all eight zombie world positions into screen-space coordinates.

To reduce DSP/LUT use and improve timing, the module processes zombies sequentially with shared arithmetic instead of instantiating eight large independent projection units. It outputs each zombie's screen X/Y position, projected size, visibility and depth.

### `zombie_pill_pixel.v`

Draws one projected zombie as a simple pill-shaped screen sprite from its screen position and radius.

Eight copies are instantiated by the top module, one for each active zombie slot.

---

## 5.2 Zombie AI, Navigation and Round Logic

### `zombies_round_spawn_controller.v`

Controls round progression and zombie spawning.

It calculates the zombie quota for each round, provides the approximately five-second round grace period, chooses available zombie slots, selects spawn locations, enables side-room spawns according to opened doors, and uses an LFSR-driven Poisson-style delay table to vary the time between spawns.

It also supplies a safe spawn-exit destination so newly created zombies first move out of their spawn room before normal navigation begins.

### `zombie_agent_round.v`

The main per-zombie AI module. The top-level design instantiates **eight independent copies**.

Each agent stores its own position, HP, alive/dead state, attack state and navigation state. Major responsibilities include:

- spawn initialization,
- forced movement toward a safe spawn-room exit,
- line-of-sight sampling toward the player,
- fallback navigation-node selection when direct LOS is blocked,
- collision-valid movement proposals,
- chase movement,
- 0.5-second melee wind-up,
- melee hit attempt,
- 0.7-second recovery,
- receiving weapon damage,
- death detection and death pulse generation.

The navigation and movement operations are intentionally staged across clock cycles to avoid creating a very long combinational timing path.

### `zombie_player_health.v`

Maintains the shared player HP state.

It combines melee attempts from all eight zombies, implements post-hit invulnerability, delayed HP regeneration, death at zero HP, and the +1 HP Power Up perk.

### `zombie_aim_hit_selector_seq.v`

Determines which zombie is hit when the player fires at the crosshair.

The module sequentially checks all eight already-projected zombies, verifies that the crosshair overlaps the same pill-shaped silhouette used for rendering, rejects zombies hidden behind the wall-depth buffer, and selects the nearest valid target.

The result is a one-hot hit signal for exactly one zombie slot. This staged design prevents the display projection from creating a large combinational feedback path directly into zombie HP state.

---

## 5.3 Weapons and Combat

### `weapon_system_controller.v`

Implements the complete pistol, shotgun and rifle weapon state.

It manages:

- equipped weapon behavior,
- magazine ammunition,
- reserve ammunition,
- semi-auto and full-auto firing,
- fire-rate cooldowns,
- manual and automatic reloads,
- reload countdown values,
- wall MAX AMMO refills,
- fast-reload perk,
- Ultimate magazine/reserve/reload/fire-rate upgrades,
- Ultimate damage values,
- weapon-specific fire pulses used by the sound system and hit logic.

### `sound_event_sender.v`

Collects gameplay events such as weapon fire, zombie hits, zombie spawns, round changes and music-state transitions.

It queues these events and sends compact one-byte event codes back to the Python host.

### `uart_tx_115200.v`

Serializes FPGA event bytes into a standard 115200-baud UART transmit stream for the PC.

It is used by `sound_event_sender` for the FPGA → Python audio/event channel.

---

## 5.4 HUD and On-Screen UI

### `money_hud_overlay.v`

Draws the player's four-digit money counter in the upper-left portion of the VGA display.

### `player_hp_hud_overlay.v`

Draws the player's current HP value beside the money display, including support for 4 HP after purchasing the extra-HP perk.

### `powerup_perk_icon_overlay.v`

Draws two related UI elements:

1. persistent perk icons beside the HP display, and
2. the POWER UP purchase menu.

The menu contains numbered choices 1–4, the corresponding perk icon, the 1000-point price, and a marker for already purchased perks. The implementation uses compact shared icon and digit ROMs to reduce LUT consumption.

### `weapon_icon_overlay.v`

Draws the currently equipped pistol, shotgun or rifle icon in the lower-right HUD area.

When the equipped weapon has received the Ultimate upgrade, the top-level RGB mux displays the icon in purple.

### `ammo_reserve_bcd_converter.v`

Converts the binary reserve-ammunition count into hundreds/tens/ones decimal digits for the ammo HUD.

The conversion is performed sequentially using repeated subtraction instead of a large combinational divider, reducing LUT cost.

### `weapon_ammo_hud_overlay.v`

Displays the current magazine count and reserve ammunition in the lower-right HUD.

The pistol reserve is displayed as unlimited, while shotgun and rifle reserve values are shown numerically.

### `reload_timer_overlay.v`

Displays the active reload countdown near the crosshair using the reload time reported by the weapon controller.

### `round_hud_overlay.v`

Displays the current zombie round number in the HUD.

### `shared_station_label_overlay.v`

Renders text labels over the pink wall stations, including shotgun, rifle, Power, Power Up, Ultimate and Lucky Box labels.

Power-related labels can dynamically show `ON` or `OFF`. The label-position tracking is intentionally optimized so renderer-heavy pixel logic does not feed long synchronous timing paths.

### `game_flow_overlay.v`

Draws the start/death screen messages:

```text
PRESS Y TO START
YOU DIED
PRESS Y TO RESTART
```

### `pause_word_overlay.v`

Draws the center-screen `PAUSE` text while gameplay is frozen.

### `hp_debug_display.v`

Drives the Basys 3 four-digit seven-segment display as a small debug monitor for zombie/player HP values.

---

## 5.5 Economy, Doors, Power and Other Interactables

### `zombies_economy_doors.v`

The central economy and interaction controller.

It manages:

- money up to 9999,
- hit rewards,
- four purchasable side-room doors,
- shotgun ownership and purchase,
- rifle ownership and purchase,
- weapon selection through the mouse wheel,
- paid shotgun/rifle MAX AMMO refills,
- Power activation,
- the POWER UP menu state,
- maximum-two-perk purchase logic,
- Ultimate upgrades for each individual gun,
- machine proximity/interaction regions,
- the special max-money purchase handling used when the balance is exactly 9999.

### `sensitivity_button_controller.v`

Reads the Basys 3 T18 pushbutton and cycles through mouse-sensitivity levels used by the camera controller.

### `pause_button_controller.v`

Reads the Basys 3 T17 pause button and toggles the gameplay pause state using frame-based button sampling.

---

## 5.6 UART Input, System Control and Top-Level Integration

### `uart_rx_115200.v`

Receives the PC → FPGA serial stream and converts UART bits into bytes for the packet decoder.

### `input_packet_parser.v`

Decodes the Python host's fixed three-byte input protocol into persistent keyboard/mouse states and one-clock event pulses. It also contains the host heartbeat watchdog.

### `top_aimlab.v`

The main integration module and Vivado top-level design.

It connects the VGA timing, UART input/output, camera, map ray-caster, economy, weapons, rounds, eight zombie agents, player health, zombie projection, hit selection, HUD overlays, station labels, start/death/pause state, music events and final RGB priority mux.

This is the module that should be selected as the Vivado **Top Module**.

---

## 5.7 Earlier / Legacy Development Modules

The following modules are included because they were part of earlier AimLab and zombie-development stages. They are useful references, but they are **not instantiated by the current `top_aimlab` gameplay build**.

### `game_controller.v`

Earlier AimLab-style target-game controller supporting Free, Speed, 99 Bots and Moving Target modes. It predates the final zombie round/economy architecture.

### `lightweight_target_controller.v`

A reduced target respawn controller created during the transition from the original AimLab target game toward the Zombies design. It uses an LFSR to generate simple target positions.

### `target_projection.v`

Earlier full world-to-camera target projection module with crosshair-hit calculation. It was replaced in the Zombies path by the smoother shared zombie projection bank plus the sequential aimed-hit selector.

### `zombie_projection_fast.v`

An earlier low-cost display-only zombie projector using coarse power-of-two depth buckets. It was replaced by `zombie_projection_bank_smooth` to remove visible perspective stepping.

### `single_zombie_timing_safe.v`

Earlier single-zombie prototype used to develop timing-safe navigation, melee, HP and regeneration before scaling the design to eight independent `zombie_agent_round` instances.

### `mode_selector_overlay.v`

Earlier AimLab mode-selection overlay used to render the Speed / 99 Bots / Moving Target selectors.

### `seven_segment_score_display.v`

Earlier generic four-digit Basys 3 score display used by the AimLab-style modes. The current Zombies build instead uses `hp_debug_display` for the board's seven-segment output.
