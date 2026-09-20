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
# (if that no-ops because uinput is built-in rather than a module on some
# kernel config, a reboot forces it instead)

sudo usermod -aG input "$USER"
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
