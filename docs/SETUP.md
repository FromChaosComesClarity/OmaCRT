# Machine setup for OmaCRT development

System-level prerequisites, outside the git repo (udev rules and group
membership are per-machine, not project files). Run once per machine.

## Bar / idle config

`config/shell.json` in this repo is the canonical, working copy of
`~/.config/omarchy/shell.json` on the dev machine — curated bar (menu, clock,
bluetooth, network, audio) plus the OmaCRT launcher plugin entry. To apply it
on a fresh install:

```bash
cp ~/.config/omarchy/shell.json ~/.config/omarchy/shell.json.bak.$(date +%s)  # back up first
cp config/shell.json ~/.config/omarchy/shell.json
omarchy-shell shell reloadConfig
```

This **replaces** the file outright rather than merging — fine for a fresh
Omarchy install with no prior customization of its own; back up first if the
target machine already has one worth keeping (see the omarchy skill's own
guidance on this).

## Display: forcing the CRT's actual resolution

**Confirmed working on the real hardware (2026-09-20).** The HDMI→composite
adapter (identifies as `HJW MACROSILICON` — a common converter chipset) ships
a real EDID, so Hyprland auto-detects it without any manual mode-forcing
needed to see it at all — but its EDID's "preferred" mode is **1280x720**,
not the 720×480 this project targets. `config/monitors.lua` in this repo
has the working override:

```lua
hl.monitor({ output = "HDMI-A-2", mode = "720x480@60", position = "auto", scale = 1 })
```

Apply it: back up `~/.config/hypr/monitors.lua` first (it may have other
machine-specific monitor rules worth keeping), merge this rule in, then
`hyprctl reload && hyprctl configerrors` (must come back clean). The output
name (`HDMI-A-2` here) is specific to which physical port the adapter is
plugged into on this machine — check yours with `hyprctl monitors`.

## Gamepad daemon prerequisites

```bash
# Python bindings for the Linux input subsystem (reading the pad)
sudo pacman -S python-evdev

# Let a non-root process create a virtual input device (emitting synthetic
# key/mouse events) without running as root
echo 'KERNEL=="uinput", GROUP="input", MODE="0660"' | sudo tee /etc/udev/rules.d/60-omacrt-uinput.rules
sudo udevadm control --reload-rules

# /dev/uinput already exists at boot, created before the new rule — a
# running kernel module reload is the reliable way to get udev to
# re-apply permissions to the existing node rather than a fresh one:
sudo modprobe -r uinput && sudo modprobe uinput

sudo usermod -aG input "$USER"
```

**This does not persist across reboots** — confirmed directly: `/dev/uinput`
reverted to `root:root` after a reboot on this machine, breaking the daemon
again from a clean boot. `uinput` gets auto-loaded very early (before
`systemd-udevd` has processed `/etc/udev/rules.d/`, likely via kmod's
static-node mechanism), so our rule never gets a chance to apply to that
first device node — a plain `udevadm trigger` does **not** fix it, only an
actual module unload+reload does. **Permanent fix:**
`system/omacrt-uinput-fix.service` in this repo is a oneshot system service
that does exactly that reload, ordered after `systemd-udevd.service` and
before `graphical.target` — i.e. before any user session (and thus this
daemon) can possibly have the device open already.

```bash
sudo cp system/omacrt-uinput-fix.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable omacrt-uinput-fix.service
# takes effect on next boot; to test without rebooting, stop the daemon
# first so modprobe -r isn't fighting an open file handle:
systemctl --user stop omacrt-input.service
sudo systemctl start omacrt-uinput-fix.service
systemctl --user start omacrt-input.service
```

**The group membership needs a fresh login (or reboot) to take effect** —
`id "$USER"` shows the new group immediately, but a shell/session that was
already open when `usermod` ran keeps its old group list (`groups` in that
session won't show `input`) until it's replaced. Confirmed by testing both
commands back to back on 2026-09-20 on the dev machine: `/dev/uinput` was
`crw-rw---- root input` right after the module reload, but a Claude Code
Bash session open since before the `usermod` call still reported only
`jose wheel` from `groups`, not `input`.

## Verify

```bash
python3 -c "import evdev"        # no output = ok
ls -l /dev/uinput                 # expect: crw-rw---- root input
groups                            # expect "input" listed (after a fresh login)
```

## Hyprland keybinds (F13/F14 -> shell IPC)

`config/bindings.lua` in this repo is the canonical copy of
`~/.config/hypr/bindings.lua` — includes the two OmaCRT-specific binds. The
daemon only *emits* F13 (Guide) / F14 (Select) as synthetic keys; these
binds are what actually make them summon the launcher / cheatsheet:

```bash
cp ~/.config/hypr/bindings.lua ~/.config/hypr/bindings.lua.bak.$(date +%s)  # back up first
cp config/bindings.lua ~/.config/hypr/bindings.lua
hyprctl reload && hyprctl configerrors   # must come back clean
```

## Gamepad daemon as a systemd --user service

```bash
mkdir -p ~/.config/systemd/user
cp daemon/omacrt-input.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now omacrt-input.service
```

**`SupplementaryGroups=` does not work in a `--user` unit** — that's a
system/PID1-only feature; declaring it makes the service fail outright
(`systemd exit 216/GROUP`) rather than being ignored. Confirmed by hitting it
directly — see the comment in `daemon/omacrt-input.service`. The service
instead depends on the graphical login session itself already having the
`input` group (the section above).

**A stale systemd `--user` manager is a real failure mode, not just a
theoretical one.** Systemd reuses one user-manager instance per UID across
logins unless every session for that UID fully ends — confirmed directly on
this machine: after `usermod -aG input`, an ordinary desktop logout/login did
**not** replace the manager (something kept another session alive through
it), so the manager kept stale credentials and every `--user` service it
spawned lacked the `input` group, even though a fresh `newgrp input` in a
plain shell worked fine. Diagnose with:

```bash
UPID=$(pgrep -u "$USER" -f "^/usr/lib/systemd/systemd --user$" | head -1)
grep -i groups /proc/$UPID/status   # must include "input"
```

If it's missing, the only fix that reliably worked was a full reboot —
**always ask the user to run that themselves**, never issue a
reboot/shutdown command directly: it can leave the tool call hanging if the
machine powers off mid-command, and resuming the session can then retry that
same pending command, causing an unwanted second reboot (hit exactly this
once — see the project's `feedback-no-direct-reboot-commands` note if
you're an assistant reading this).

## Controller driver: xpadneo (for Xbox-Wireless-protocol pads over Bluetooth)

Needed for any pad that identifies as an Xbox controller over Bluetooth (ours,
an 8BitDo SN30 Pro in its Xinput mode, `Vendor=045e Product=02e0`) — the
in-kernel generic HID driver for these (`hid_microsoft`) doesn't expose
Start/Select/Guide/thumbstick-click (L3/R3) at all. Confirmed by enumerating
every `/dev/input/eventN` on the machine, not just an evdev read gap. Skip
this section for a pad that isn't affected (check with `docs/PLUGIN_NOTES.md`-
style verification: dump `evdev.InputDevice(...).capabilities(verbose=True)`
and look for `BTN_START`/`BTN_SELECT`/`BTN_MODE`/`BTN_THUMBL`/`BTN_THUMBR`).

```bash
# AUR only — needs an AUR-capable install path (this agent had no interactive
# terminal for the sudo prompt inside the build; the user ran this themselves
# with the `!` prefix in Claude Code)
omarchy pkg aur add xpadneo-dkms
```

Requires `linux-headers` for the running kernel to build (on Omarchy:
`linux-omarchy-headers`, already present here) — DKMS fails without it.

**The module doesn't bind automatically on first install.** The package ships
a udev rule (`/usr/lib/udev/rules.d/60-xpadneo.rules`) that's supposed to force
a rebind from whatever in-kernel driver claims the device first, but in
testing here it did not reliably fire on a live reconnect even after
`udevadm control --reload-rules`. xpadneo's own `TROUBLESHOOTING.md` (shipped
at `/usr/share/doc/xpadneo/TROUBLESHOOTING.md`) confirms this is a known
first-connection race and gives the actual fix — load the module early at
boot, before Bluetooth reconnects any paired controller:

```bash
echo "hid_xpadneo" | sudo tee /etc/modules-load.d/xpadneo.conf
```

This only takes effect on the *next* boot. To fix the *current* session
without rebooting, force the rebind manually:

```bash
# Find the device id (varies — check `readlink -f /sys/bus/hid/devices/*/driver`
# for one pointing at .../drivers/microsoft, or grep 8BitDo/your pad's name out
# of `for d in /sys/bus/hid/devices/*; do grep -l "8BitDo" "$d/uevent"; done`)
DEVID="0005:045E:02E0.000A"   # example — yours will differ each reconnect
sudo bash -c "echo '$DEVID' > /sys/bus/hid/drivers/microsoft/unbind; sleep 1; echo '$DEVID' > /sys/bus/hid/drivers/xpadneo/bind"
```

A `write error: No such device` from the first `echo` in that one-liner is
normal/harmless in testing here — the unbind briefly removes the sysfs node
the shell's `echo` was still targeting; the bind on the next line still lands.
Verify by checking the driver symlink, not the shell's own exit code:

```bash
for d in /sys/bus/hid/devices/*; do
  grep -qi "8BitDo" "$d/uevent" 2>/dev/null && readlink -f "$d/driver"
done
# expect: .../drivers/xpadneo
```

### Verify full button set

```bash
python3 -c "
import evdev
d = evdev.InputDevice('/dev/input/event5')  # find yours: check by name first
print(sorted(n for n,_ in d.capabilities(verbose=True).get(('EV_KEY',1), [])))
"
# expect BTN_A/B/NORTH/WEST/TL/TR/SELECT/START/MODE/THUMBL/THUMBR all present
```
