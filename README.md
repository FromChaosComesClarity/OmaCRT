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

First real milestone done: `plugins/org.omacrt.launcher` is a placeholder
full-screen overlay plugin, proven working end-to-end on this machine — loads,
gets a real layer-shell surface (`hyprctl layers` shows it), reads the active
Omarchy theme's colors/typography live, and draws the broadcast safe-area
margin. See [`docs/PLUGIN_NOTES.md`](docs/PLUGIN_NOTES.md) for the (undocumented
elsewhere) gotchas that took to get there. The stock bar is also curated down
to clock/network/volume on this machine already (`~/.config/omarchy/shell.json`,
not yet captured as a repo file).

Not started: the real launcher UI, the gamepad daemon, the burn-in screensaver.
See [`docs/RESEARCH.md`](docs/RESEARCH.md) for the brainstorm, the options
considered, and the hardware/software facts they're based on.

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
