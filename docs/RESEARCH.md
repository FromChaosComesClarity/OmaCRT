# OmaCRT — research and options

Written before any code exists. Facts gathered from this machine and from the web
on 2026-09-20; options laid out for a decision, not yet a plan.

## 1. Platform facts

### The machine
- Intel i5-4260U, 2 cores / 4 threads @ 1.4 GHz, Intel HD Graphics 5000 (`i915`).
- 4 GB RAM total (3.7 GiB usable), ~1.1 GiB free / 1.8 GiB buff-cache at idle
  with the stock shell already running.
- The GPU already advertises a `720x480@60Hz` mode (`hyprctl monitors`), so the
  480p target is a real, already-negotiated EDID mode, not something to force.

### Omarchy 4.0.4 does not use waybar
`omarchy-shell` (`/usr/share/omarchy/bin`, config at `/usr/share/omarchy/shell`)
is a single long-running Quickshell process that hosts the bar, panels, overlays,
and the background switcher as **plugins** inside one process. This matters a lot
for a 4 GB machine: a second Qt/QML process (a standalone Quickshell instance, or
worse, an Electron app) costs tens of MB of duplicated Qt runtime plus its own
compositor surface. A plugin living inside the existing process costs only its
own QML tree.

Plugin kinds available (`docs/README.md` in that shell, read in full this
session): `bar-widget`, `panel`, `overlay`, `menu`, `service`, and `bar` (a full
bar replacement — only one active at a time, built-in `omarchy.bar` is the
fallback if none is set). Plugins are git repos with a `manifest.json`, cloned
into `~/.config/omarchy/plugins/<id>/`, hot-reloaded on save, controlled over a
documented IPC target (`summon`, `hide`, `toggle`, `call`, `listPlugins`, etc.).
Layout and per-widget settings persist in `~/.config/omarchy/shell.json`.

**Conclusion: OmaCRT should ship as Omarchy plugins, not a standalone shell.**
A full-screen gamepad launcher is an `overlay` plugin; burn-in protection is
another `overlay` (or a `service` that drives DPMS/dimming) wired to the
existing `idle.screensaver` / `idle.lock` timers already in `shell.json`; the
status readout is either a curated `bar-widget` set or, if the existing bar
can't be made legible at 720px wide, a `bar` replacement plugin.

### Prior art
[`tv-shell`](https://github.com/jedwards1230/tv-shell) (jedwards1230) is close
to the same stack for a different purpose — Quickshell + Hyprland for a Moonlight
streaming box. Its input core is instructive even though the goal differs: a
separate Rust daemon (`tv-shell-input`) takes an exclusive `EVIOCGRAB` on the
gamepad, emits synthetic keyboard/mouse through `uinput`, and talks to the QML
shell over IPC — the pad never touches the compositor as a raw joystick device.
That's the shape worth copying (daemon-owns-the-device, shell-consumes-synthetic-input),
not the project itself (it's built for game streaming, has no CRT/burn-in
concerns, and is a much bigger codebase than this needs).

### The adapter question — needs an answer before the density work
480p **requires a component connection** (the 5-cable Y/Pb/Pr + L/R kind).
Composite (single yellow RCA) tops out at 480i — interlaced, not progressive —
and interlace flicker on thin UI elements is worse than anything the progressive
density work below assumes.

**Open question for you:** is the adapter HDMI→component, or HDMI→composite?
If it's composite, the target is really 480i and the "avoid thin hairlines"
guidance in §4 gets stricter, not optional.

## 2. Gamepad input — options

Quickshell/QML has no first-party gamepad module (`QtGamepad` was a Qt5-only
module, unmaintained, SDL2 or evdev backed; no official Qt6 equivalent). Three
ways to get a pad into a Quickshell overlay:

| Option | What it is | Pros | Cons |
|---|---|---|---|
| **A. AntiMicroX** | Existing GUI app, maps pad → synthetic key/mouse via `uinput`, Wayland-capable | Zero code, works today, GUI profile editor | Extra always-running app outside our control; generic remapping, not tuned to launcher navigation (repeat rate, analog deadzone/curve, "hold to go back" etc.); can't call Quickshell IPC directly, only synthetic input |
| **B. Custom minimal daemon** (Python `evdev` + `uinput` to start) | A small script we own: reads the pad's event node, emits synthetic arrow-keys/Enter/Esc via a virtual `uinput` keyboard, tuned deadzone + repeat for our launcher | Exactly the nav feel we want; trivial to extend (long-press Guide → toggle launcher, chorded shortcuts); Python means near-zero idle CPU (blocking read, no polling loop) and a five-minute edit-reload cycle | We own the bug surface; needs a systemd `--user` unit; Python's baseline RSS (~15–25 MB) is real on a 4 GB box but is a one-time cost, not per-widget |
| **C. Same daemon, but call Quickshell IPC instead of synthetic keys** | Daemon calls `quickshell ipc ... call shell <method>` directly for launcher-specific gestures, and only falls back to synthetic keys for "anything already keyboard-navigable" (system menus, etc.) | Tightest integration; analog stick can drive smooth scroll instead of discrete key repeats; no risk of the synthetic keyboard leaking into whatever app currently has focus | More plumbing: IPC methods have to exist on our overlay's IPC target before this works, so it's a second iteration, not a first one |

**Recommendation:** start with B (synthetic keys via `uinput`), because it works
against *any* Quickshell surface immediately, including the stock
`omarchy.menu`/settings panels we are not rewriting. Layer C in later for the
launcher specifically, once its overlay has its own IPC target worth calling
into directly. Skip A — it solves a slightly different problem (arbitrary-app
remapping) than "one launcher with a specific nav feel," and it's one more
background process on a 4 GB box for something 100 lines of Python covers.

Either B or C needs `uinput` device access — a udev rule (`KERNEL=="uinput",
GROUP="input", MODE="0660"` + user in `input` group) rather than running the
daemon as root.

## 3. CRT burn-in — options

CRT phosphor burn-in is real but slower than plasma; the standard countermeasures
still apply, and Omarchy already gives us one lever for free: `shell.json` has
`idle.screensaver` (default 150s) and `idle.lock` (300s) as top-level timings
the shell already tracks.

| Technique | What it does | Fits here? |
|---|---|---|
| **Dark theme by default** | Lower average beam intensity = slower phosphor wear | Free — Omarchy's default themes are already dark; just don't fight that in OmaCRT's palette choices |
| **Idle → near-black drifting screensaver** (`overlay` plugin, wired to `idle.screensaver`) | A low-luminance element slowly drifting across the screen after idle, instead of a static one | Recommended primary defense — safer than DPMS-off over an analog adapter chain (component/composite wake-from-DPMS over a converter box is flaky in practice), and directly reuses the idle timer that already exists |
| **Whole-UI pixel shift** | Translate the root item by ±1–2 px on a slow timer (minutes, both axes) while the bar/launcher chrome is visible | Cheap to add to any persistent chrome (the bar, any fixed dock); do this for whatever ends up on-screen for hours at a stretch |
| **Bar auto-hide on idle** | Don't leave the status bar's bright pixels static for long unattended stretches | Combine with the idle screensaver rather than instead of it |
| **DPMS-off on long idle** | Cuts the beam entirely | Keep as a *second*, longer-timeout fallback behind the screensaver (e.g. 30+ min), not the first response — given the adapter-chain wake risk above |

**Recommendation:** treat `idle.screensaver` as "start the drifting low-luminance
overlay," `idle.lock` as today, and add a much longer third timeout for DPMS-off
as a belt-and-suspenders measure, not the primary one. Apply pixel-shift to
whatever chrome stays on screen during active use (the bar, if it's persistent).

## 4. Screen density / readability at 720×480 — options

This is a distinct scale from the desktop's `GDK_SCALE=2` on the current 1080p
panel — 720×480 needs its own "TV scale," not a bigger desktop scale.

Facts driving this (10-foot UI convention + broadcast safe-area standard):
- Viewing distance for a TV is assumed ~10 ft — minimum body text ~24sp
  equivalent, oversized focus indicators, low density, generous spacing.
- Broadcast **safe-area** standard: keep all interactive content inside the
  **93%** "action-safe" rectangle, keep text inside the **90%** "title-safe"
  rectangle — i.e. at minimum a ~5% margin on every edge before anything
  important is placed, because overscan on real CRTs isn't consistent set to
  set. At 720×480 that's roughly 36px/24px of margin — not optional whitespace,
  it's where a real TV crops the picture.
- Thin 1px hairlines and fine serif/thin-weight text shimmer on an analog
  signal (worse still if the adapter turns out to be composite/480i, per §1)
  — use ≥2–3px borders, bold/flat iconography, avoid fine detail.
- Avoid strongly saturated red (or red/cyan adjacency) in text on an analog
  path — composite/component chroma channels bleed most on red, which is
  exactly the "avoid thin red text on black" problem CRT/retro UI designers
  flag.

**Options for how far to take it:**

1. **One fixed "TV scale" profile** — a single hardcoded font/icon/spacing
   scale used by every OmaCRT plugin, tuned once by eye against the real
   hardware. Simple, no settings surface, but "tuned once" only holds if the
   adapter and TV don't change.
2. **A scale token exposed as a setting** (like the bar widgets' existing
   `schema` mechanism in Omarchy's plugin manifests) — same idea, but a slider
   in Setup so it can be nudged without editing QML. More work, but this is
   exactly the kind of thing that's annoying to get right on the first try
   without the TV in front of you.

**Recommendation:** 2, using the manifest `schema` mechanism Omarchy plugins
already support for per-widget settings — cheap to add once, and this project
will almost certainly need to tune it live against the actual screen.

## 5. RAM/CPU budget — constraints to hold to

Baseline right now: `quickshell -p /usr/share/omarchy/shell` alone is ~240 MB
RSS with ~1.1 GiB free. Rules of thumb for everything we add:

- Prefer plugins inside the existing shell process over any new process
  (§1). A second Qt/QML process is the single most expensive mistake
  available here.
- No video-based screensaver content — a drifting vector/shape element, not a
  decoded video loop.
- Vector or a handful of small raster icons, not a large icon-pack asset
  bundle, for the launcher grid.
- The gamepad daemon (§2) should be the one new persistent process; keep it
  Python-simple rather than reaching for a heavier runtime, at least until
  its resident cost is actually measured and found to matter.

## 6. Open questions for you

1. **Adapter type** — component (true 480p) or composite (480i in practice)?
   Changes how strict §4's hairline/flicker guidance needs to be.
2. **Status bar scope** — the current bar has room for a lot of widgets at
   1920px wide; 720px wide at TV scale will not fit all of it. What actually
   needs to stay visible on the TV (clock? network? volume? all three?), so
   the bar work is "curate + rescale the existing bar" rather than "guess and
   redo"?
3. **Gamepad model** — which pad(s) should the nav be tuned against first? Button
   mapping conventions differ (Xbox-layout vs. PlayStation-layout face buttons).
