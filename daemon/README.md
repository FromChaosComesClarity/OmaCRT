# omacrt-input

The gamepad-to-keyboard daemon. Reads a gamepad's raw evdev events and emits
synthetic keyboard events (arrow keys, Enter, Escape, plus two dedicated
toggle keys -- Guide for the launcher, Select for the controller cheatsheet)
through a virtual `uinput` keyboard, so any keyboard-navigable Quickshell
surface can be driven from a gamepad today, before the real launcher has its
own IPC to call directly (see `docs/RESEARCH.md` #2 for the fuller
options/decision). The two toggle keys (F13/F14) only do something because
`config/bindings.lua` binds them to the corresponding shell IPC calls -- see
`docs/SETUP.md`.

Also writes `~/.local/state/omacrt/layout` at startup (the active
`--layout`), so `plugins/org.omacrt.cheatsheet` (and any future layout-aware
QML) shows the same layout the daemon is actually using without duplicating
the setting in two places.

Verified working end-to-end on the dev machine (2026-09-20) against a real
8BitDo SN30 Pro over Bluetooth (needed `xpadneo` for the full button set --
see `docs/SETUP.md`): D-pad, left stick with deadzone + auto-repeat, A/B
confirm/back, and synthetic keys correctly reaching the focused window.

## Desktop/game handoff

Normal keyboard/mouse input stops reaching the desktop for free once a game
window has focus -- ordinary window-manager routing. A gamepad daemon
reading the shared evdev stream bypasses that routing entirely, so it has to
replicate the handoff itself, or it keeps firing synthetic Enter/arrow-keys
into whatever a game is doing with the same pad. This daemon watches
Hyprland's active window over its event socket and stops emitting synthetic
keys the instant that window is fullscreen -- treated as "an app took the
controller over" without needing a maintained list of which apps count as
games. The Guide button is the one exception: it always works, so there's
always a way back to the launcher, matching how a console's Home button
behaves.

## Layouts

`--layout xbox|playstation|nintendo` (default `xbox`) decides which physical
button is "confirm" vs. "back". evdev already normalizes face-button
*position* across pad brands (`BTN_SOUTH`/`BTN_EAST`/...), so Xbox and
Western-convention PlayStation pads need no remapping -- their confirm
button is physically `BTN_SOUTH` either way. Nintendo is the real exception:
Nintendo's own software has swapped this since the SNES/N64 era (right/`BTN_EAST`
= confirm, bottom/`BTN_SOUTH` = cancel). Known **not** handled yet:
Japanese-region PlayStation's own Circle-confirms convention. Button glyphs
(showing the right icon per layout in the UI) are a separate, not-yet-built
concern for the launcher itself -- this daemon only handles which physical
press means what.

## Running

```bash
python3 omacrt_input.py                       # auto-detects the pad
python3 omacrt_input.py --layout playstation
python3 omacrt_input.py --device /dev/input/event5   # force a specific device
```

Needs `python-evdev` and `/dev/uinput` + gamepad event-node access -- see
`docs/SETUP.md` for the one-time machine setup (package, udev rule, group).

### As a systemd --user service

`omacrt-input.service` is provided but **not installed automatically** --
review it first (it hardcodes the repo's expected clone path):

```bash
mkdir -p ~/.config/systemd/user
cp daemon/omacrt-input.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now omacrt-input.service
```

It relies on the graphical login session already having the `input` group --
`SupplementaryGroups=` in the unit itself does **not** work for a `--user`
service (needs system/PID1 privileges; declaring it makes the service fail
outright rather than being ignored -- learned by hitting it directly). See
`docs/SETUP.md` for the stale-user-manager failure mode this depends on not
hitting, and its diagnosis.

Also needs `system/omacrt-uinput-fix.service` (a system-level unit, separate
install step, see `docs/SETUP.md`) -- without it, `/dev/uinput` reverts to
`root:root` on every reboot and this service crash-loops until someone
notices.

## Not yet built

- Option C from `docs/RESEARCH.md` #2: calling the launcher's own IPC
  directly once it exists, instead of only synthetic keys.
- Shoulders/triggers/X/Y/Start and the thumbstick clicks are read but
  currently unused -- reserved for launcher-specific gestures once there's a
  launcher UI to gesture at. (Select is used -- toggles the cheatsheet.)
- Right stick, and using the analog trigger values (not just digital) for
  anything.
- A user-facing settings surface for the layout choice (currently a CLI
  flag/systemd-unit edit only) -- also means switching layout needs a daemon
  restart; the cheatsheet reads the layout state file at its own startup, not
  live.
