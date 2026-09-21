#!/usr/bin/env python3
"""OmaCRT gamepad-to-keyboard input daemon.

Reads a gamepad's evdev events and emits synthetic keyboard events through a
virtual uinput device, so any keyboard-navigable Quickshell surface (the
stock omarchy.menu, panels, and eventually the OmaCRT launcher) can be driven
from the couch. This is the "Option B" approach from docs/RESEARCH.md #2:
synthetic keys work against any existing surface today; calling the
launcher's own IPC directly (Option C) is a later refinement once that
overlay has real content worth navigating.

Desktop/game handoff: normal keyboard/mouse input naturally stops reaching
the desktop once a game window has focus (ordinary window-manager routing);
a gamepad daemon reading raw evdev bypasses that routing entirely, so it has
to replicate the handoff itself. This daemon watches Hyprland's focused
window and stops emitting synthetic keys the moment that window goes
fullscreen (see HyprlandFocusWatcher) -- the same "controller taken over by
the game" behavior the user asked for -- except the Guide button, which
always works, so there's always a way back to the launcher.

Usage:
    python3 omacrt_input.py [--device /dev/input/eventN] [--layout xbox|playstation|nintendo]

If --device is omitted, the first evdev device that looks like a gamepad
(has BTN_GAMEPAD/BTN_SOUTH and at least one ABS axis) is used.
"""

import argparse
import json
import os
import socket
import subprocess
import sys
import threading
import time

import evdev
from evdev import ecodes, InputDevice, UInput

# --------------------------------------------------------------------------
# Layout: which physical button confirms/cancels. evdev already normalizes
# face-button *position* across pads via BTN_SOUTH/EAST/NORTH/WEST, so Xbox
# and Western-convention PlayStation pads need no remapping at all -- their
# "confirm" button is physically BTN_SOUTH either way. Nintendo is the real
# exception: Nintendo's own software has used bottom-position B as cancel and
# right-position A as confirm since the SNES/N64 era, the opposite of Xbox's
# physical convention. Japanese-region PlayStation (Circle=confirm) is a
# known further exception this v1 does not handle -- flagged, not guessed at.
# --------------------------------------------------------------------------
LAYOUTS = {
    "xbox": {"confirm": ecodes.BTN_SOUTH, "back": ecodes.BTN_EAST},
    "playstation": {"confirm": ecodes.BTN_SOUTH, "back": ecodes.BTN_EAST},
    "nintendo": {"confirm": ecodes.BTN_EAST, "back": ecodes.BTN_SOUTH},
}

# Synthetic keys emitted. KEY_F13/F14 are deliberately otherwise-unused keys,
# bound in ~/.config/hypr/bindings.lua to the shell IPC calls that summon the
# launcher and the controller cheatsheet respectively -- this daemon only
# emits the key; the Hyprland keybind is what actually does something with it.
KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT = (
    ecodes.KEY_UP,
    ecodes.KEY_DOWN,
    ecodes.KEY_LEFT,
    ecodes.KEY_RIGHT,
)
KEY_CONFIRM = ecodes.KEY_ENTER
KEY_BACK = ecodes.KEY_ESC
KEY_TOGGLE_LAUNCHER = ecodes.KEY_F13
KEY_TOGGLE_CHEATSHEET = ecodes.KEY_F14

# Analog-stick-as-D-pad tuning. The device's own reported deadzone (AbsInfo
# "flat") is small (~9% on the SN30 Pro) -- fine for analog aiming, too
# twitchy for menu navigation, so a larger threshold is used here regardless
# of what the hardware reports.
STICK_THRESHOLD = 0.5  # fraction of the axis's max magnitude
REPEAT_DELAY_S = 0.4  # time held before auto-repeat starts
REPEAT_INTERVAL_S = 0.12  # time between repeats while held


def find_gamepad():
    for path in evdev.list_devices():
        dev = InputDevice(path)
        caps = dev.capabilities()
        keys = caps.get(ecodes.EV_KEY, [])
        abs_axes = caps.get(ecodes.EV_ABS, [])
        if ecodes.BTN_SOUTH in keys and abs_axes:
            return dev
        dev.close()
    return None


class Repeater:
    """Fires a callback repeatedly while a named direction stays "held", with
    an initial delay then a steady interval -- the same feel as holding down
    a keyboard arrow key."""

    def __init__(self):
        self._held = {}  # name -> press_time
        self._lock = threading.Lock()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._on_repeat = None
        self._running = True

    def start(self, on_repeat):
        self._on_repeat = on_repeat
        self._thread.start()

    def set_held(self, name, held):
        with self._lock:
            if held and name not in self._held:
                self._held[name] = time.monotonic()
            elif not held and name in self._held:
                del self._held[name]

    def stop(self):
        self._running = False

    def _run(self):
        next_fire = {}
        while self._running:
            now = time.monotonic()
            with self._lock:
                held_items = list(self._held.items())
            for name, pressed_at in held_items:
                held_for = now - pressed_at
                if held_for < REPEAT_DELAY_S:
                    continue
                due = next_fire.get(name, pressed_at + REPEAT_DELAY_S)
                if now >= due:
                    self._on_repeat(name)
                    next_fire[name] = now + REPEAT_INTERVAL_S
            for name in list(next_fire):
                if name not in self._held:
                    del next_fire[name]
            time.sleep(0.01)


class HyprlandFocusWatcher:
    """Tracks whether the desktop (vs. a fullscreen app -- a game, an
    emulator, Clarity's TV mode, etc.) currently has focus, the same way
    keyboard/mouse input naturally stops reaching the desktop once a game
    has it: normal apps get that for free from window-manager focus routing,
    but a gamepad daemon reading raw evdev events bypasses that routing
    entirely, so it has to replicate the same handoff itself or it will keep
    firing synthetic Enter/arrow-keys into a game using the same pad.

    Heuristic: "fullscreen" is treated as "an app took the screen over" --
    matches how couch-gaming/HTPC setups conventionally distinguish this,
    and needs no maintained list of "which apps are games". Reads Hyprland's
    own `fullscreen` field on the active window rather than guessing from
    window class/title.
    """

    def __init__(self):
        self.desktop_active = True
        self._lock = threading.Lock()

    def start(self):
        self._refresh()
        threading.Thread(target=self._watch, daemon=True).start()

    def _refresh(self):
        try:
            out = subprocess.run(
                ["hyprctl", "-j", "activewindow"], capture_output=True, text=True, timeout=2
            ).stdout
            win = json.loads(out) if out.strip() else {}
            active = win.get("fullscreen", 0) == 0
        except Exception:
            active = True  # fail open to "desktop navigable" rather than stuck unresponsive
        with self._lock:
            self.desktop_active = active

    def is_desktop_active(self):
        with self._lock:
            return self.desktop_active

    def _socket_path(self):
        runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        if not sig:
            return None
        return f"{runtime}/hypr/{sig}/.socket2.sock"

    def _watch(self):
        path = self._socket_path()
        if not path:
            return  # not running under Hyprland (e.g. dev/test) -- stay desktop_active
        while True:
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
                    sock.connect(path)
                    buf = b""
                    while True:
                        chunk = sock.recv(4096)
                        if not chunk:
                            break
                        buf += chunk
                        while b"\n" in buf:
                            _, buf = buf.split(b"\n", 1)
                            self._refresh()
            except OSError:
                pass
            time.sleep(1)  # Hyprland restarted or the socket hiccuped -- retry


class OmaCRTInput:
    def __init__(self, device, layout_name, debug=False):
        self.device = device
        self.layout = LAYOUTS[layout_name]
        self.debug = debug
        self.ui = UInput(
            {ecodes.EV_KEY: [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_CONFIRM, KEY_BACK, KEY_TOGGLE_LAUNCHER, KEY_TOGGLE_CHEATSHEET]},
            name="omacrt-virtual-keyboard",
        )
        self.repeater = Repeater()
        self.repeater.start(self._fire_direction)
        self.focus = HyprlandFocusWatcher()
        self.focus.start()

    def _fire_direction(self, name):
        if not self.focus.is_desktop_active():
            return
        key = {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT}[name]
        self.ui.write(ecodes.EV_KEY, key, 1)
        self.ui.write(ecodes.EV_KEY, key, 0)
        self.ui.syn()

    def _tap(self, key, gate=True):
        # `gate=False` is for the Guide/toggle-launcher button specifically:
        # like a console's Home button, it should always work, fullscreen
        # game or not, so there's always a way back to the launcher.
        if gate and not self.focus.is_desktop_active():
            return
        self.ui.write(ecodes.EV_KEY, key, 1)
        self.ui.syn()
        self.ui.write(ecodes.EV_KEY, key, 0)
        self.ui.syn()

    def _handle_hat(self, code, value):
        # ABS_HAT0X/Y are already digital: -1, 0, 1.
        if code == ecodes.ABS_HAT0X:
            self.repeater.set_held("left", value < 0)
            self.repeater.set_held("right", value > 0)
            if value != 0:
                self._fire_direction("left" if value < 0 else "right")
        elif code == ecodes.ABS_HAT0Y:
            self.repeater.set_held("up", value < 0)
            self.repeater.set_held("down", value > 0)
            if value != 0:
                self._fire_direction("up" if value < 0 else "down")

    def _handle_stick_axis(self, code, value, absinfo):
        span = max(abs(absinfo.min), abs(absinfo.max)) or 1
        centered = value - (absinfo.max + absinfo.min) / 2
        frac = centered / span
        if code == ecodes.ABS_X:
            self.repeater.set_held("left", frac < -STICK_THRESHOLD)
            self.repeater.set_held("right", frac > STICK_THRESHOLD)
        elif code == ecodes.ABS_Y:
            self.repeater.set_held("up", frac < -STICK_THRESHOLD)
            self.repeater.set_held("down", frac > STICK_THRESHOLD)

    def _handle_key(self, code, value):
        # value: 1 = press, 0 = release, 2 = autorepeat (from the device
        # itself -- ignored, our own Repeater handles direction repeat).
        if value != 1:
            return
        if self.debug:
            # The device's own name for the button, so the log says BTN_MODE
            # rather than 316 and can be compared against what this file maps.
            names = ecodes.bytype[ecodes.EV_KEY].get(code, code)
            if isinstance(names, (list, tuple)):
                names = "/".join(names)
            print(f"button: {names} ({code})", flush=True)
        if code == self.layout["confirm"]:
            self._tap(KEY_CONFIRM)
        elif code == self.layout["back"]:
            self._tap(KEY_BACK)
        elif code in (ecodes.BTN_MODE, ecodes.BTN_START):
            # ⚠️ Two buttons for one job, deliberately.
            #
            # Guide is the right button for this: it is the Home button on
            # every console ever made, and it is what this daemon has always
            # emitted for. It is also the one button that cannot be relied on.
            # It gets claimed below evdev by other software (Steam is the usual
            # culprit), and on this pad it stopped producing a BTN_MODE event
            # at all, despite xpadneo advertising the capability. A launcher
            # you cannot open is not a launcher.
            #
            # So Start opens it too. Start is otherwise unused here, it is
            # where a TV menu has lived since before consoles had a Home
            # button, and it takes the same ungated path — so there is always a
            # way back, mid-game and with Guide missing.
            self._tap(KEY_TOGGLE_LAUNCHER, gate=False)
        elif code == ecodes.BTN_SELECT:
            # Gated normally (unlike Guide) -- this is a help overlay, not
            # an escape hatch, so it's fine for it to be blocked mid-game.
            self._tap(KEY_TOGGLE_CHEATSHEET)

    def run(self):
        absinfo_cache = {
            ecodes.ABS_X: self.device.absinfo(ecodes.ABS_X),
            ecodes.ABS_Y: self.device.absinfo(ecodes.ABS_Y),
        }
        for event in self.device.read_loop():
            if event.type == ecodes.EV_KEY:
                self._handle_key(event.code, event.value)
            elif event.type == ecodes.EV_ABS:
                if event.code in (ecodes.ABS_HAT0X, ecodes.ABS_HAT0Y):
                    self._handle_hat(event.code, event.value)
                elif event.code in (ecodes.ABS_X, ecodes.ABS_Y):
                    self._handle_stick_axis(event.code, event.value, absinfo_cache[event.code])


def write_layout_state(layout_name):
    # Read by plugins/org.omacrt.cheatsheet's Cheatsheet.qml (and any future
    # layout-aware QML) so they show the same layout the daemon is actually
    # using, without duplicating --layout in two places. Not watched for
    # live updates on the QML side yet since the daemon doesn't support
    # switching layout without a restart either.
    state_dir = os.path.join(os.path.expanduser("~"), ".local", "state", "omacrt")
    os.makedirs(state_dir, exist_ok=True)
    with open(os.path.join(state_dir, "layout"), "w") as f:
        f.write(layout_name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", help="evdev device path, e.g. /dev/input/event5")
    parser.add_argument("--layout", choices=sorted(LAYOUTS), default="xbox")
    # ⚠️ Worth the eight lines it costs. "Button X does nothing" is this
    # daemon's characteristic bug report, and it has three completely different
    # causes: the pad never sent it, this daemon does not map it, or the
    # Hyprland keybind on the other end is missing. Without this, telling them
    # apart means attaching a separate evdev reader while someone presses the
    # button — which was done twice before the flag existed.
    parser.add_argument(
        "--debug", action="store_true",
        help="log every button press received, including ones this daemon does not map",
    )
    args = parser.parse_args()
    write_layout_state(args.layout)

    # A gamepad not being connected right now (asleep, off, not paired yet)
    # is normal, ongoing operating condition for a persistent daemon, not a
    # startup error -- wait for one rather than exiting. (Learned the hard
    # way: exiting here made systemd's Restart=on-failure crash-loop the
    # service every couple of seconds, 100+ times, whenever the pad was
    # simply idle-disconnected.) --device is different: an explicit,
    # user-given path that doesn't exist is a real misconfiguration worth
    # failing on immediately.
    last_logged = 0
    while True:
        try:
            dev = InputDevice(args.device) if args.device else find_gamepad()
        except FileNotFoundError:
            if args.device:
                print(f"Device {args.device} not found.", file=sys.stderr)
                sys.exit(1)
            dev = None
        if dev is not None:
            break
        now = time.monotonic()
        if now - last_logged > 30:
            print("No gamepad connected -- waiting...", flush=True)
            last_logged = now
        time.sleep(2)

    print(f"Using device: {dev.name} ({dev.path}), layout={args.layout}", flush=True)
    while True:
        daemon = OmaCRTInput(dev, args.layout, debug=args.debug)
        try:
            daemon.run()
            break  # read_loop() ended cleanly -- shouldn't normally happen
        except KeyboardInterrupt:
            break
        except OSError:
            # The pad disconnected mid-run. Go back to waiting for one
            # rather than exiting (same reasoning as above).
            print("Gamepad disconnected -- waiting for reconnect...", flush=True)
            while True:
                dev = InputDevice(args.device) if args.device else find_gamepad()
                if dev is not None:
                    break
                time.sleep(2)
            print(f"Reconnected: {dev.name} ({dev.path})", flush=True)


if __name__ == "__main__":
    main()
