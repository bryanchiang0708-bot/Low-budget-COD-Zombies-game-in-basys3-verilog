"""
AimLab FPGA Host Input Bridge V8
=============================

Captures:
- Relative mouse movement
- Left/right mouse button state
- Mouse wheel weapon switching
- Keyboard key DOWN / UP state

Sends all data to the Basys 3 over USB-UART using fixed 3-byte packets.

Packet format:
    [HEADER][BYTE1][BYTE2]

Protocol:
    0xC1, dx, dy          Relative mouse motion (signed int8)
    0xD0, state, 0x00     Left mouse button: 1=down, 0=up
    0xD1, state, 0x00     Right mouse button: 1=down, 0=up
    0xD2, delta, 0x00     Mouse wheel: signed int8 (+up / -down)
    0xE0, keycode, state  Keyboard state: ASCII keycode, 1=down, 0=up
    0xF0, 0x00, 0x00      Heartbeat

Designed for:
- Basys 3
- 115200 baud
- 100 MHz FPGA UART receiver
- AimLab-style FPS controls
"""

import sys
import time
import threading
import math
import random
import os
from array import array

import pygame
import serial
from pynput import keyboard


# =============================================================================
# CONFIGURATION
# =============================================================================

COM_PORT = "COM8"
BAUD_RATE = 115200

# Mouse deltas are accumulated and transmitted at this rate.
MOUSE_SEND_RATE_HZ = 120

# Heartbeat lets the FPGA watchdog detect a disconnected/crashed host.
HEARTBEAT_RATE_HZ = 20       # 20 Hz = one heartbeat every 50 ms

# Host-side mouse sensitivity.
# Keep this at 1 initially; camera sensitivity is better tuned on the FPGA.
MOUSE_SENSITIVITY = 1.0

# Small pygame window only exists to capture/grab the mouse.
WINDOW_WIDTH = 400
WINDOW_HEIGHT = 300

# F1 exits the host program.
EXIT_KEY = keyboard.Key.f1

# Background music.
# Put an authorized local copy of the requested track next to this script.
BACKGROUND_MUSIC_FILE = "zombies_background_music.mp3"
BACKGROUND_MUSIC_VOLUME = 0.12



# =============================================================================
# UART PACKET HEADERS
# =============================================================================

PKT_MOUSE_MOVE = 0xC1
PKT_MOUSE_LEFT = 0xD0
PKT_MOUSE_RIGHT = 0xD1
PKT_MOUSE_WHEEL = 0xD2
PKT_KEYBOARD = 0xE0
PKT_HEARTBEAT = 0xF0

# FPGA -> PC event bytes
EVENT_PISTOL_SHOT = 0xA1
EVENT_TARGET_POP = 0xA2
EVENT_TARGET_APPEAR = 0xA3
EVENT_SHOTGUN_SHOT = 0xA4
EVENT_RIFLE_SHOT = 0xA5
EVENT_ROUND_CHANGE = 0xA6

# FPGA-controlled background-music state.
EVENT_MUSIC_START_RESET = 0xA7
EVENT_MUSIC_PAUSE = 0xA8
EVENT_MUSIC_RESUME = 0xA9
EVENT_MUSIC_STOP_RESET = 0xAA


# =============================================================================
# AUDIO EFFECTS
# =============================================================================

AUDIO_SAMPLE_RATE = 44_100


def _make_sound(sample_function, duration_seconds, volume=1.0):
    """Create a stereo 16-bit pygame Sound without needing external WAV files."""
    frame_count = int(AUDIO_SAMPLE_RATE * duration_seconds)
    pcm = array("h")

    for i in range(frame_count):
        t = i / AUDIO_SAMPLE_RATE
        sample = sample_function(t, duration_seconds)

        sample = max(-1.0, min(1.0, sample * volume))
        value = int(sample * 32767)

        # Stereo: duplicate the same sample into L/R.
        pcm.append(value)
        pcm.append(value)

    return pygame.mixer.Sound(buffer=pcm.tobytes())


def build_pistol_sound():
    """Short synthetic FPS-style gunshot: crack + low thump + decaying noise."""
    rng = random.Random(0xA1)

    # Pre-generate deterministic noise so playback is cheap.
    count = int(AUDIO_SAMPLE_RATE * 0.105)
    noise = [rng.uniform(-1.0, 1.0) for _ in range(count)]

    def sample(t, duration):
        i = min(len(noise) - 1, int(t * AUDIO_SAMPLE_RATE))

        # Fast crack.
        crack_env = math.exp(-t * 75.0)
        crack = noise[i] * crack_env

        # Lower-frequency body/thump.
        thump_env = math.exp(-t * 27.0)
        thump = math.sin(2.0 * math.pi * 115.0 * t) * thump_env

        # Very brief high-frequency snap.
        snap_env = math.exp(-t * 120.0)
        snap = math.sin(2.0 * math.pi * 1800.0 * t) * snap_env

        return (0.62 * crack) + (0.55 * thump) + (0.25 * snap)

    return _make_sound(sample, 0.105, volume=0.72)



def build_shotgun_sound():
    """Heavier, deeper blast with a longer low-frequency boom."""
    rng = random.Random(0xA4)
    duration = 0.180
    count = int(AUDIO_SAMPLE_RATE * duration)
    noise = [rng.uniform(-1.0, 1.0) for _ in range(count)]

    def sample(t, total):
        i = min(len(noise) - 1, int(t * AUDIO_SAMPLE_RATE))

        blast_env = math.exp(-t * 28.0)
        blast = noise[i] * blast_env

        boom_env = math.exp(-t * 13.0)
        boom = (
            0.80 * math.sin(2.0 * math.pi * 72.0 * t) +
            0.42 * math.sin(2.0 * math.pi * 118.0 * t)
        ) * boom_env

        crack_env = math.exp(-t * 85.0)
        crack = math.sin(2.0 * math.pi * 980.0 * t) * crack_env

        return 0.64 * blast + 0.72 * boom + 0.18 * crack

    return _make_sound(sample, duration, volume=0.78)


def build_rifle_sound():
    """Short, sharp rifle crack designed to remain clear at ~10 shots/s."""
    rng = random.Random(0xA5)
    duration = 0.075
    count = int(AUDIO_SAMPLE_RATE * duration)
    noise = [rng.uniform(-1.0, 1.0) for _ in range(count)]

    def sample(t, total):
        i = min(len(noise) - 1, int(t * AUDIO_SAMPLE_RATE))

        snap_env = math.exp(-t * 92.0)
        snap = noise[i] * snap_env

        body_env = math.exp(-t * 36.0)
        body = math.sin(2.0 * math.pi * 185.0 * t) * body_env

        crack_env = math.exp(-t * 120.0)
        crack = math.sin(2.0 * math.pi * 2250.0 * t) * crack_env

        return 0.58 * snap + 0.42 * body + 0.30 * crack

    return _make_sound(sample, duration, volume=0.64)


def build_round_change_sound():
    """Short synthetic trumpet/fanfare for a new round."""
    duration = 0.78
    notes = (
        (0.00, 0.18, 392.00),
        (0.18, 0.18, 523.25),
        (0.36, 0.42, 659.25),
    )

    def brass(freq, t):
        p = 2.0 * math.pi * freq * t
        return (
            0.68 * math.sin(p)
            + 0.24 * math.sin(2.0 * p)
            + 0.12 * math.sin(3.0 * p)
            + 0.06 * math.sin(4.0 * p)
        )

    def sample(t, total):
        out = 0.0
        for start, length, freq in notes:
            if start <= t < start + length:
                lt = t - start
                attack = min(1.0, lt / 0.018)
                env = attack * math.exp(-lt * 3.6)
                out += brass(freq, lt) * env

        if t >= 0.36:
            lt = t - 0.36
            out += (
                0.14
                * math.sin(2.0 * math.pi * 329.63 * lt)
                * math.exp(-lt * 3.0)
            )
        return out

    return _make_sound(sample, duration, volume=0.55)


def build_pop_sound():
    """Bright target-destroy pop distinct from the gunshot."""
    def sample(t, duration):
        normalized = t / duration
        env = max(0.0, 1.0 - normalized) ** 2

        # Rising chirp.
        f0 = 650.0
        f1 = 1550.0
        instantaneous_phase = (
            2.0 * math.pi *
            (f0 * t + 0.5 * (f1 - f0) * (t * t / duration))
        )

        tone = math.sin(instantaneous_phase)

        # Add a light harmonic for a sharper "pop".
        harmonic = math.sin(instantaneous_phase * 2.0)

        return env * ((0.82 * tone) + (0.18 * harmonic))

    return _make_sound(sample, 0.085, volume=0.60)


def build_spawn_slap_sound():
    """
    Short table-slap / wooden thump for Speed Flick and 99 Bots appearance.
    A sharp noisy attack is layered over a low wooden resonance.
    """
    rng = random.Random(0xA3)
    duration = 0.115
    count = int(AUDIO_SAMPLE_RATE * duration)
    noise = [rng.uniform(-1.0, 1.0) for _ in range(count)]

    def sample(t, total):
        i = min(len(noise) - 1, int(t * AUDIO_SAMPLE_RATE))

        # Very fast slap transient.
        slap_env = math.exp(-t * 68.0)
        slap = noise[i] * slap_env

        # Table/body resonance.
        body_env = math.exp(-t * 26.0)
        body = (
            0.72 * math.sin(2.0 * math.pi * 165.0 * t) +
            0.36 * math.sin(2.0 * math.pi * 245.0 * t)
        ) * body_env

        # Brief high wooden knock.
        knock_env = math.exp(-t * 95.0)
        knock = math.sin(2.0 * math.pi * 920.0 * t) * knock_env

        return (0.60 * slap) + (0.58 * body) + (0.22 * knock)

    return _make_sound(sample, duration, volume=0.68)


pistol_sound = None
shotgun_sound = None
rifle_sound = None
round_change_sound = None
pop_sound = None
spawn_slap_sound = None


def initialize_audio():
    """Initialize pygame mixer and synthesize both effects."""
    global pistol_sound, shotgun_sound, rifle_sound
    global round_change_sound, pop_sound, spawn_slap_sound

    if pygame.mixer.get_init() is None:
        pygame.mixer.init(
            frequency=AUDIO_SAMPLE_RATE,
            size=-16,
            channels=2,
            buffer=256,
        )

    pistol_sound = build_pistol_sound()
    shotgun_sound = build_shotgun_sound()
    rifle_sound = build_rifle_sound()
    round_change_sound = build_round_change_sound()
    pop_sound = build_pop_sound()
    spawn_slap_sound = build_spawn_slap_sound()

    print("[AUDIO] Gun, hit, spawn, and round-change effects ready.")



background_music_ready = False


def prepare_background_music():
    """
    Load the configured background track, but DO NOT start it.

    Playback is controlled exclusively by FPGA events:
        A7 = start/restart from 0:00
        A8 = pause
        A9 = resume from the paused position
        AA = stop/reset
    """
    global background_music_ready

    background_music_ready = False

    script_dir = os.path.dirname(os.path.abspath(__file__))
    music_path = os.path.join(script_dir, BACKGROUND_MUSIC_FILE)

    if not os.path.isfile(music_path):
        print(
            f"[MUSIC] {BACKGROUND_MUSIC_FILE!r} not found; "
            "game will run without background music."
        )
        return

    try:
        pygame.mixer.music.load(music_path)
        pygame.mixer.music.set_volume(BACKGROUND_MUSIC_VOLUME)
        background_music_ready = True
        print(f"[MUSIC] Loaded and waiting for FPGA START: {music_path}")
    except pygame.error as exc:
        print(f"[MUSIC] Could not load background music: {exc}")


def music_start_from_beginning():
    """Stop any old state and begin the track from 0:00."""
    if not background_music_ready:
        return

    try:
        pygame.mixer.music.stop()
        pygame.mixer.music.play(-1)
        print("[MUSIC] START / RESTART FROM 0:00")
    except pygame.error as exc:
        print(f"[MUSIC] Start error: {exc}")


def music_pause():
    """Pause while preserving the current playback position."""
    if not background_music_ready:
        return

    try:
        pygame.mixer.music.pause()
        print("[MUSIC] PAUSE")
    except pygame.error as exc:
        print(f"[MUSIC] Pause error: {exc}")


def music_resume():
    """Resume exactly where pygame.mixer.music.pause() stopped."""
    if not background_music_ready:
        return

    try:
        pygame.mixer.music.unpause()
        print("[MUSIC] RESUME")
    except pygame.error as exc:
        print(f"[MUSIC] Resume error: {exc}")


def music_stop_and_reset():
    """Stop playback. The next START event begins again from 0:00."""
    if not background_music_ready:
        return

    try:
        pygame.mixer.music.stop()
        print("[MUSIC] STOP / RESET")
    except pygame.error as exc:
        print(f"[MUSIC] Stop error: {exc}")

def fpga_event_listener_worker():
    """
    Listen continuously for one-byte events transmitted by the FPGA.

        0xA1 -> pistol shot
        0xA2 -> zombie hit
        0xA3 -> zombie appeared
        0xA4 -> shotgun shot
        0xA5 -> rifle shot
        0xA6 -> round change

        0xA7 -> music start/restart from 0:00
        0xA8 -> music pause
        0xA9 -> music resume
        0xAA -> music stop/reset
    """
    while running.is_set():
        try:
            waiting = ser.in_waiting

            if waiting:
                data = ser.read(waiting)

                for event_byte in data:
                    if event_byte == EVENT_PISTOL_SHOT:
                        if pistol_sound is not None:
                            pistol_sound.play()
                        print("[FPGA] PISTOL")

                    elif event_byte == EVENT_SHOTGUN_SHOT:
                        if shotgun_sound is not None:
                            shotgun_sound.play()
                        print("[FPGA] SHOTGUN")

                    elif event_byte == EVENT_RIFLE_SHOT:
                        if rifle_sound is not None:
                            rifle_sound.play()
                        print("[FPGA] RIFLE")

                    elif event_byte == EVENT_ROUND_CHANGE:
                        if round_change_sound is not None:
                            round_change_sound.play()
                        print("[FPGA] ROUND CHANGE")

                    elif event_byte == EVENT_MUSIC_START_RESET:
                        music_start_from_beginning()

                    elif event_byte == EVENT_MUSIC_PAUSE:
                        music_pause()

                    elif event_byte == EVENT_MUSIC_RESUME:
                        music_resume()

                    elif event_byte == EVENT_MUSIC_STOP_RESET:
                        music_stop_and_reset()

                    elif event_byte == EVENT_TARGET_POP:
                        if pop_sound is not None:
                            pop_sound.play()
                        print("[FPGA] TARGET POP")

                    elif event_byte == EVENT_TARGET_APPEAR:
                        if spawn_slap_sound is not None:
                            spawn_slap_sound.play()
                        print("[FPGA] BOT APPEAR")

            else:
                time.sleep(0.001)

        except (serial.SerialException, OSError) as exc:
            print(f"[UART RX] Event listener error: {exc}")
            running.clear()
            break


# =============================================================================
# GLOBAL PROGRAM STATE
# =============================================================================

running = threading.Event()
running.set()

serial_lock = threading.Lock()
mouse_lock = threading.Lock()
key_lock = threading.Lock()

mouse_dx_accum = 0.0
mouse_dy_accum = 0.0

# Stores keycodes currently considered DOWN.
# This suppresses OS keyboard auto-repeat packets.
pressed_keys = set()

# Track mouse buttons so we can release them on shutdown.
left_mouse_down = False
right_mouse_down = False


# =============================================================================
# SERIAL CONNECTION
# =============================================================================

def open_serial():
    """Open the USB-UART connection to the FPGA."""
    try:
        port = serial.Serial(
            port=COM_PORT,
            baudrate=BAUD_RATE,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0,
            write_timeout=1,
        )

        # Give the serial interface a moment to settle.
        time.sleep(0.10)

        # Discard stale input if any exists.
        port.reset_input_buffer()
        port.reset_output_buffer()

        print(f"[UART] Connected to {COM_PORT} at {BAUD_RATE} baud.")
        return port

    except serial.SerialException as exc:
        print(f"[UART] Failed to open {COM_PORT}: {exc}")
        sys.exit(1)


ser = open_serial()


# =============================================================================
# UART TRANSMISSION
# =============================================================================

def send_packet(header: int, byte1: int = 0, byte2: int = 0) -> bool:
    """
    Send exactly one 3-byte packet.

    Returns True on success.
    Returns False if the serial link fails.
    """
    if not running.is_set():
        return False

    packet = bytes((
        header & 0xFF,
        byte1 & 0xFF,
        byte2 & 0xFF,
    ))

    try:
        with serial_lock:
            ser.write(packet)
        return True

    except (serial.SerialException, serial.SerialTimeoutException, OSError) as exc:
        print(f"[UART] Transmission error: {exc}")
        running.clear()
        return False


def signed8_to_byte(value: int) -> int:
    """Convert Python signed integer -128..127 to an unsigned UART byte."""
    return value & 0xFF


# =============================================================================
# KEYBOARD ENCODING
# =============================================================================

SPECIAL_KEY_CODES = {
    keyboard.Key.space: 0x20,
    keyboard.Key.enter: 0x0D,
    keyboard.Key.tab: 0x09,
    keyboard.Key.backspace: 0x08,
    keyboard.Key.esc: 0x1B,
}


def key_to_code(key):
    """
    Convert a pynput key into one 8-bit code for the FPGA.

    Alphabetic keys are always normalized to lowercase, so:
        W, w, Shift+W, CapsLock+W -> ASCII 'w' (0x77)

    This is useful for game controls because movement should not depend on
    Caps Lock or Shift state.
    """
    if key in SPECIAL_KEY_CODES:
        return SPECIAL_KEY_CODES[key]

    char = getattr(key, "char", None)

    if char:
        # Normalize alphabetic controls to lowercase.
        if char.isalpha():
            char = char.lower()

        # Only transmit characters that fit into one byte.
        code = ord(char)
        if 0 <= code <= 0xFF:
            return code

    # Windows numpad keys may arrive primarily through VK codes.
    vk = getattr(key, "vk", None)

    numpad_vk_to_ascii = {
        96: ord("0"),
        97: ord("1"),
        98: ord("2"),
        99: ord("3"),
        100: ord("4"),
        101: ord("5"),
        102: ord("6"),
        103: ord("7"),
        104: ord("8"),
        105: ord("9"),
        106: ord("*"),
        107: ord("+"),
        109: ord("-"),
        110: ord("."),
        111: ord("/"),
    }

    if vk in numpad_vk_to_ascii:
        return numpad_vk_to_ascii[vk]

    return None


# =============================================================================
# KEYBOARD CALLBACKS
# =============================================================================

def on_key_press(key):
    """Send a key-DOWN packet exactly once when a key becomes pressed."""
    if key == EXIT_KEY:
        print("[HOST] F1 pressed -> exiting.")
        running.clear()
        return False

    keycode = key_to_code(key)

    if keycode is None:
        return

    with key_lock:
        # Suppress Windows key-repeat while a key is held.
        if keycode in pressed_keys:
            return

        pressed_keys.add(keycode)

    send_packet(PKT_KEYBOARD, keycode, 0x01)
    print(f"[KEY] DOWN 0x{keycode:02X} ({display_keycode(keycode)})")


def on_key_release(key):
    """Send a key-UP packet when a key is released."""
    keycode = key_to_code(key)

    if keycode is None:
        return

    should_send = False

    with key_lock:
        if keycode in pressed_keys:
            pressed_keys.remove(keycode)
            should_send = True

    if should_send:
        send_packet(PKT_KEYBOARD, keycode, 0x00)
        print(f"[KEY] UP   0x{keycode:02X} ({display_keycode(keycode)})")


def display_keycode(keycode: int) -> str:
    """Human-readable key label for debug output."""
    names = {
        0x20: "SPACE",
        0x0D: "ENTER",
        0x09: "TAB",
        0x08: "BACKSPACE",
        0x1B: "ESC",
    }

    if keycode in names:
        return names[keycode]

    if 32 <= keycode <= 126:
        return repr(chr(keycode))

    return "SPECIAL"


# =============================================================================
# MOUSE DELTA ACCUMULATION
# =============================================================================

def accumulate_mouse_delta(dx: float, dy: float):
    """Accumulate relative movement until the UART sender flushes it."""
    global mouse_dx_accum, mouse_dy_accum

    with mouse_lock:
        mouse_dx_accum += dx
        mouse_dy_accum += dy


def consume_mouse_delta():
    """
    Remove at most one signed-int8 delta packet from the accumulators.

    Large movements are not discarded. If accumulated motion exceeds
    +/-127, the remainder stays queued for following packets.
    """
    global mouse_dx_accum, mouse_dy_accum

    with mouse_lock:
        dx = int(mouse_dx_accum)
        dy = int(mouse_dy_accum)

        dx = max(-128, min(127, dx))
        dy = max(-128, min(127, dy))

        mouse_dx_accum -= dx
        mouse_dy_accum -= dy

    return dx, dy


# =============================================================================
# BACKGROUND UART WORKERS
# =============================================================================

def mouse_sender_worker():
    """Transmit accumulated mouse deltas at a stable fixed rate."""
    interval = 1.0 / MOUSE_SEND_RATE_HZ
    next_send = time.perf_counter()

    while running.is_set():
        next_send += interval

        dx, dy = consume_mouse_delta()

        if dx != 0 or dy != 0:
            send_packet(
                PKT_MOUSE_MOVE,
                signed8_to_byte(dx),
                signed8_to_byte(dy),
            )

        sleep_time = next_send - time.perf_counter()

        if sleep_time > 0:
            time.sleep(sleep_time)
        else:
            # If the thread falls behind, restart timing instead of
            # repeatedly trying to catch up.
            next_send = time.perf_counter()


def heartbeat_worker():
    """Continuously prove to the FPGA watchdog that the host is alive."""
    interval = 1.0 / HEARTBEAT_RATE_HZ
    next_send = time.perf_counter()

    while running.is_set():
        send_packet(PKT_HEARTBEAT, 0x00, 0x00)

        next_send += interval
        sleep_time = next_send - time.perf_counter()

        if sleep_time > 0:
            time.sleep(sleep_time)
        else:
            next_send = time.perf_counter()


# =============================================================================
# MOUSE BUTTON PACKETS
# =============================================================================

def set_left_mouse(state: bool):
    global left_mouse_down

    state = bool(state)

    if left_mouse_down == state:
        return

    left_mouse_down = state
    send_packet(PKT_MOUSE_LEFT, 0x01 if state else 0x00, 0x00)

    print(f"[MOUSE] LEFT  {'DOWN' if state else 'UP'}")


def set_right_mouse(state: bool):
    global right_mouse_down

    state = bool(state)

    if right_mouse_down == state:
        return

    right_mouse_down = state
    send_packet(PKT_MOUSE_RIGHT, 0x01 if state else 0x00, 0x00)

    print(f"[MOUSE] RIGHT {'DOWN' if state else 'UP'}")


def send_mouse_wheel(delta: int):
    """Send signed mouse-wheel notches to the FPGA."""
    delta = int(delta)

    if delta == 0:
        return

    direction = 1 if delta > 0 else -1
    count = min(abs(delta), 16)

    for _ in range(count):
        send_packet(
            PKT_MOUSE_WHEEL,
            signed8_to_byte(direction),
            0x00,
        )

    print(f"[MOUSE] WHEEL {'UP' if direction > 0 else 'DOWN'} x{count}")


# =============================================================================
# CLEAN SHUTDOWN
# =============================================================================

def release_all_inputs():
    """
    Tell the FPGA that every held input has been released.

    This is extra protection in addition to the FPGA-side watchdog.
    """
    global left_mouse_down, right_mouse_down

    # Send key-up packets for every key we still believe is pressed.
    with key_lock:
        keys_to_release = list(pressed_keys)
        pressed_keys.clear()

    for keycode in keys_to_release:
        try:
            packet = bytes((PKT_KEYBOARD, keycode & 0xFF, 0x00))
            with serial_lock:
                ser.write(packet)
        except Exception:
            break

    # Release mouse buttons.
    try:
        with serial_lock:
            ser.write(bytes((PKT_MOUSE_LEFT, 0x00, 0x00)))
            ser.write(bytes((PKT_MOUSE_RIGHT, 0x00, 0x00)))
    except Exception:
        pass

    left_mouse_down = False
    right_mouse_down = False


# =============================================================================
# MAIN APPLICATION
# =============================================================================

def main():
    # Request low-latency stereo audio before pygame initializes its mixer.
    pygame.mixer.pre_init(
        frequency=AUDIO_SAMPLE_RATE,
        size=-16,
        channels=2,
        buffer=256,
    )
    pygame.init()
    initialize_audio()
    prepare_background_music()

    screen = pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT))
    pygame.display.set_caption("FPGA AimLab Input Capture")

    # FPS-style relative mouse capture.
    pygame.mouse.set_visible(False)
    pygame.event.set_grab(True)

    # Clear any initial relative movement generated while opening the window.
    pygame.mouse.get_rel()

    keyboard_listener = keyboard.Listener(
        on_press=on_key_press,
        on_release=on_key_release,
    )
    keyboard_listener.start()

    mouse_thread = threading.Thread(
        target=mouse_sender_worker,
        name="MouseUARTSender",
        daemon=True,
    )

    heartbeat_thread = threading.Thread(
        target=heartbeat_worker,
        name="UARTHeartbeat",
        daemon=True,
    )

    fpga_event_thread = threading.Thread(
        target=fpga_event_listener_worker,
        name="FPGAEventListener",
        daemon=True,
    )

    mouse_thread.start()
    heartbeat_thread.start()
    fpga_event_thread.start()

    print()
    print("============================================================")
    print(" FPGA AIMLAB INPUT HOST")
    print("============================================================")
    print(f" UART       : {COM_PORT} @ {BAUD_RATE}")
    print(f" Mouse TX   : {MOUSE_SEND_RATE_HZ} Hz")
    print(f" Heartbeat  : {HEARTBEAT_RATE_HZ} Hz")
    print(" FPGA audio : A1 pistol / A4 shotgun / A5 rifle / A6 round / A7-A9-AA music")
    print(" Mouse      : locked + hidden; wheel cycles owned weapons")
    print(" Exit       : F1 or close the window")
    print("============================================================")
    print()

    clock = pygame.time.Clock()

    try:
        while running.is_set():
            for event in pygame.event.get():

                if event.type == pygame.QUIT:
                    running.clear()
                    break

                # -------------------------------------------------------------
                # Relative mouse movement
                # -------------------------------------------------------------
                if event.type == pygame.MOUSEMOTION:
                    rel_x, rel_y = event.rel

                    dx = rel_x * MOUSE_SENSITIVITY
                    dy = rel_y * MOUSE_SENSITIVITY

                    accumulate_mouse_delta(dx, dy)

                # -------------------------------------------------------------
                # Mouse wheel -> weapon switch packet.
                # -------------------------------------------------------------
                elif event.type == pygame.MOUSEWHEEL:
                    if event.y != 0:
                        send_mouse_wheel(event.y)

                # -------------------------------------------------------------
                # Mouse button down
                # -------------------------------------------------------------
                elif event.type == pygame.MOUSEBUTTONDOWN:
                    if event.button == 1:
                        set_left_mouse(True)

                    elif event.button == 3:
                        set_right_mouse(True)

                # -------------------------------------------------------------
                # Mouse button up
                # -------------------------------------------------------------
                elif event.type == pygame.MOUSEBUTTONUP:
                    if event.button == 1:
                        set_left_mouse(False)

                    elif event.button == 3:
                        set_right_mouse(False)

            # Minimal visual indicator that the capture program is alive.
            screen.fill((20, 20, 20))

            # Tiny center crosshair in the host window.
            cx = WINDOW_WIDTH // 2
            cy = WINDOW_HEIGHT // 2
            pygame.draw.line(screen, (200, 200, 200), (cx - 8, cy), (cx + 8, cy), 1)
            pygame.draw.line(screen, (200, 200, 200), (cx, cy - 8), (cx, cy + 8), 1)

            pygame.display.flip()

            # This only controls how often pygame processes the Windows queue.
            # UART mouse transmission remains independently fixed at 120 Hz.
            clock.tick(240)

    except KeyboardInterrupt:
        print("\n[HOST] Ctrl+C -> exiting.")
        running.clear()

    finally:
        print("[HOST] Releasing input states...")

        # Stop keyboard callbacks first.
        keyboard_listener.stop()

        # Attempt explicit release packets before closing UART.
        release_all_inputs()

        pygame.event.set_grab(False)
        pygame.mouse.set_visible(True)
        pygame.quit()

        try:
            ser.flush()
        except Exception:
            pass

        try:
            ser.close()
        except Exception:
            pass

        print("[UART] Serial port closed.")
        print("[HOST] Shutdown complete.")


if __name__ == "__main__":
    main()
