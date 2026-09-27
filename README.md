# OmaCRT

A gamepad-first interface for Omarchy, built to drive a Tube TV.

The target machine is a modest 4 GB RAM / dual-core Haswell Mac Mini, output through
a composite adapter to a CRT — 720×480, genuinely interlaced (480i; composite
can't carry progressive scan). OmaCRT is not a new desktop shell — it is a set
of plugins for `omarchy-shell` (Omarchy's built-in Quickshell instance): a
gamepad-navigable app launcher, a TV-legible status readout, and a burn-in-aware
idle screensaver, all themed off Omarchy's existing theme system. Once the shell
side is working, apps from the rest of this GitHub account get adapted, one at a
time, for the same screen.

Keyboard and mouse keep working throughout — the gamepad is an additional input
path, not a replacement.

## Status

**The launcher is real now, not a placeholder.**
[`plugins/org.omacrt.launcher`](plugins/org.omacrt.launcher) is a
gamepad-navigable, scrollable app list — D-pad/stick moves the highlight,
confirm launches, back closes — reading Quickshell's own `DesktopEntries`
directly and launching the same way Omarchy's built-in menu does
(`gtk-launch` via `uwsm-app`). The list is Clarity and EmuLatte, plus every
executable `*.AppImage` in `~/Applications` (discovered on each open, so
dropping one in is the whole install step), plus anything pinned from the
installed-applications list via **Add app**. **Remove app** unpins those, and
hides or restores a discovered AppImage without touching the file. The pinned
and hidden lists live in `~/.config/omacrt/launcher.json`. Full theme-token
styling, safe-area margin, live-tested with the real controller. See
[`docs/PLUGIN_NOTES.md`](docs/PLUGIN_NOTES.md) for the gotchas that took to
get there, including one unsolved mystery (a documented facade the shell
provides for exactly this didn't work — worked around, not fixed). The stock
bar is curated down to clock/bluetooth/network/volume and captured in
[`config/shell.json`](config/shell.json) — see [`docs/SETUP.md`](docs/SETUP.md)
for how to apply it on a fresh install.

Clarity and EmuLatte are installed at `~/Games/Clarity` and `~/Games/EmuLatte`
(live git checkouts, not AppImages — see `docs/SETUP.md`) and launch cleanly
from the OmaCRT launcher, confirmed on the real CRT.

A gamepad is connected and fully working: an 8BitDo SN30 Pro over Bluetooth,
including Start/Select/Guide/thumbstick-clicks — which needed the `xpadneo`
driver (Xbox-Wireless-protocol-over-Bluetooth pads lose those buttons on
Linux's generic driver otherwise). Full install recipe, including a
first-connection driver-binding gotcha, in `docs/SETUP.md`.

[`daemon/omacrt_input.py`](daemon/omacrt_input.py) — the gamepad-to-keyboard
daemon — is built and verified working end to end against that controller:
D-pad/stick navigation, confirm/back, a Guide-button launcher toggle, and a
Select-button toggle for [`plugins/org.omacrt.cheatsheet`](plugins/org.omacrt.cheatsheet)
(the Meta+K equivalent for the pad), all as synthetic keys any
keyboard-navigable surface can already use. It also hands the controller off
to games/fullscreen apps automatically, the same way keyboard/mouse input
naturally does.

**Running on the actual CRT now (2026-09-20)** — the composite adapter's
EDID auto-detects, but its "preferred" mode is 1280x720, not our 720×480
target, so `config/monitors.lua` forces it. User's verdict on the real tube:
"it looks great." See `docs/SETUP.md` for the forcing recipe.

Not started: the burn-in screensaver, and adapting Clarity/EmuLatte's own UI
for the CRT (they currently run at their normal desktop UI, just launched
from OmaCRT — no CRT-specific adaptation yet). See
[`docs/RESEARCH.md`](docs/RESEARCH.md) for the brainstorm, the options
considered, and the hardware/software facts they're based on.

## Companion apps

Apps built to run *inside* this interface live in their own repos, because the
shell and a media application are different layers — and because nothing that
decodes video can be an Omarchy plugin at all: `omarchy-shell` is one shared
Quickshell process with no video sink to render into.

- **[OmaDVD-Player](https://github.com/FromChaosComesClarity/OmaDVD-Player)** —
  a DVD player for the tube. mpv is both the engine and the interface, so the
  whole player is one process on a 4 GB box. Ships as a self-contained AppImage
  with `libdvdcss` bundled. Drop it in `~/Applications` and the launcher finds
  it.

- **[OmaMedia-Player](https://github.com/FromChaosComesClarity/OmaMedia-Player)** —
  a media player for the same screen. Browses the optical drive, any mounted USB
  volume and your own folders, and plays what it finds, with multi-track audio,
  subtitles and the same picture controls. Hands a Video DVD over to OmaDVD
  rather than reimplementing it — each app does one job.

- **[OmaCD-Player](https://github.com/FromChaosComesClarity/OmaCD-Player)** —
  an audio CD player. The one disc format that can be identified exactly: the
  MusicBrainz DiscID is a hash of the table of contents, so the album, the year
  and every track name come back without guessing. Gamepad-driven, with a
  screensaver that drifts the sleeve across a black screen.

Clarity and EmuLatte keep their hardcoded rows here, since they take a `--crt`
flag the launcher has to know about.

## Hardware profile

| | |
|---|---|
| Model | Mac Mini (`Macmini7,1`, late-2014) |
| CPU | Intel Core i5-4260U (Haswell-ULT, 2C/4T @ 1.4 GHz) |
| RAM | 4 GB (3.7 GiB usable) |
| GPU | Intel HD Graphics 5000 (`i915`) |
| OS | Omarchy 4.0.4 |
| Shell | `omarchy-shell` — a single long-running Quickshell instance, plugin-based |
| Output | HDMI out → composite adapter → CRT TV, 720×480i |

Every design choice here is shaped by the RAM ceiling and the CPU headroom — see
`docs/RESEARCH.md` for what that rules in and out.

## License

GPL-3.0, matching the rest of this account's gamepad/TV projects (Clarity,
EmuLatte).
