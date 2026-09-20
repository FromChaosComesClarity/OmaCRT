# OmaCRT

A gamepad-first interface for Omarchy, built to drive a Tube TV.

The target machine is a modest 4 GB RAM / dual-core Haswell laptop, output through
an adapter to a CRT running at 480p. OmaCRT is not a new desktop shell — it is a set
of plugins for `omarchy-shell` (Omarchy's built-in Quickshell instance): a
gamepad-navigable app launcher, a TV-legible status readout, and a burn-in-aware
idle screensaver, all themed off Omarchy's existing theme system. Once the shell
side is working, apps from the rest of this GitHub account get adapted, one at a
time, for the same screen.

Keyboard and mouse keep working throughout — the gamepad is an additional input
path, not a replacement.

## Status

Pre-implementation. See [`docs/RESEARCH.md`](docs/RESEARCH.md) for the brainstorm,
the options considered, and the hardware/software facts they're based on.

## Hardware profile

| | |
|---|---|
| CPU | Intel Core i5-4260U (Haswell-ULT, 2C/4T @ 1.4 GHz) |
| RAM | 4 GB (3.7 GiB usable) |
| GPU | Intel HD Graphics 5000 (`i915`) |
| OS | Omarchy 4.0.4 |
| Shell | `omarchy-shell` — a single long-running Quickshell instance, plugin-based |
| Output | HDMI out → adapter → CRT TV, target 480p |

Every design choice here is shaped by the RAM ceiling and the CPU headroom — see
`docs/RESEARCH.md` for what that rules in and out.

## License

GPL-3.0, matching the rest of this account's gamepad/TV projects (Clarity,
EmuLatte).
