# OmaCRT — research and options

Written before any code exists. Facts gathered from this machine and from the web
on 2026-09-20; options laid out for a decision, not yet a plan.

## 0. Decisions (resolved 2026-09-20)

Three open questions from §6 got answered; recorded here so the rest of the
doc can be read as "what we're building," not just "what we considered."

1. **Adapter is composite** (single yellow RCA), not component. The real
   target is **480i**, not 480p — composite cannot carry progressive scan at
   all. This is a materially bigger constraint than the rest of the doc
   assumed; see the rewritten §1 and §4 below.
2. **Bar scope:** clock, network status, and volume. Nothing else needs to
   survive the cut to 720px-wide TV scale for the first version.
3. **Gamepad layout:** build a settings option covering **Xbox / PlayStation /
   Nintendo** face-button layouts, each with its own button glyphs shown in
   the UI, **defaulting to Xbox**. Tune the input daemon against an Xbox-layout
   pad first; the other two are a glyph-set + button-index remap on top of the
   same daemon, not a separate input path.

## 1. Platform facts

### The machine
- Intel i5-4260U, 2 cores / 4 threads @ 1.4 GHz, Intel HD Graphics 5000 (`i915`).
- 4 GB RAM total (3.7 GiB usable), ~1.1 GiB free / 1.8 GiB buff-cache at idle
  with the stock shell already running.
- The GPU already advertises a `720x480@60Hz` mode (`hyprctl monitors`) — a
  real, already-negotiated EDID mode. What the CRT actually displays through
  a **composite** adapter is still interlaced (see below): the adapter can
  take that progressive digital frame and re-encode it to NTSC composite,
  but NTSC composite itself is defined as 480 interlaced lines at 60
  fields/sec (30 full frames/sec) — there is no progressive composite. So
  "720×480" is the right frame size to design for, but the *display*, not
  just the signal, is interlaced.

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
status readout is **the stock `omarchy.bar`, curated and rescaled** (§4) —
skip building a `bar` replacement plugin unless testing on the real screen
shows the stock bar genuinely can't be made legible, since replacing it means
losing every first-party widget's polish for free.

### The shell already has a theme-driven design-token system — use it, don't reinvent one
Read in full this session: `Commons/Color.qml` and `Commons/Style.qml`, the
two singletons every first-party bar widget and panel already consumes.

- **`Color`** loads `~/.local/state/omarchy/current/theme/{colors.toml,shell.toml}`
  at startup and on theme-switch IPC, exposing both the foundational palette
  (`Color.foreground`, `.background`, `.accent`, `.urgent`, `.muted`) and
  per-surface roles (`Color.bar.*`, `.popups.*`, `.menu.*`, `.lock.*`, etc.),
  each with a sane fallback to the foundational palette when a theme doesn't
  define that surface. A plugin QML file that imports `Commons` and reads
  `Color.foreground` etc. is automatically correct for whatever theme is
  active and repaints live when the user switches themes — no separate
  "follow Omarchy's theme" work needed beyond using these tokens instead of
  hardcoded colors.
- **`Style`** is the typography/spacing scale: `[font] base-size` in
  `shell.toml` (12 by default) is the rem root, and every `Style.font.<token>`
  (`caption`/`bodySmall`/`body`/`subtitle`/`title`/`heading`/`display`/
  `displayLarge`, plus `icon`/`iconSmall`/`iconLarge`) is a fixed multiplier
  of it. `[spacing] scale` does the same for margins/gaps/padding/control
  sizing. **`[bar] size-horizontal`/`size-vertical` scale with `base-size`
  too** (`scale-with-font = true` by default) — meaning the bar's own height
  already grows when text does, without any per-plugin work.
- There is already a first-class CLI for this: **`omarchy display text size
  [size|reset]`** — "Scale text everywhere: omarchy shell, GTK apps, and
  terminals." It writes `[font] base-size` to `~/.config/omarchy/shell.toml`
  (a machine-level override layered on top of whatever theme is active,
  live-reloaded, survives theme switches).

**This changes §4's recommendation below:** the "TV scale" OmaCRT needs isn't
a bespoke thing to build — it's tuning `base-size` (via `omarchy display text
size`, or an OmaCRT settings affordance that just calls the same mechanism)
for the couch/CRT viewing distance, and writing every OmaCRT widget against
`Style.font.*`/`Color.*` tokens instead of literal `px`/hex values so it
inherits that scale automatically. The one caveat: this setting is global and
machine-wide, not per-output — fine if this box lives permanently on the TV,
awkward if the same machine is ever also used with a normal monitor for
editing OmaCRT's own QML.

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

### No existing gamepad/controller convention to align with
Grepped the whole shell source and Omarchy's `bin`/`config` trees for
"gamepad", "joystick", "controller" — the only hits were the `PanelController`
QML class name and a 🎮 emoji entry, both unrelated. OmaCRT's gamepad daemon
is genuinely new territory here, not a second implementation of something
Omarchy already half-does.

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

**Multi-layout decision (§0.3):** the daemon reads a controller-layout setting
(Xbox default, PlayStation, Nintendo) that does two things — remaps which
physical button index means "confirm"/"back" (Nintendo swaps A/B and X/Y
position *and* color relative to Xbox; PlayStation's face buttons are
shapes, not letters, and its confirm/back convention is also swapped from
Xbox's), and picks which glyph set the QML side renders for on-screen button
hints. Glyphs: don't hand-draw three icon sets from scratch — Xelu's
"Controller Prompts" pack (free, CC0-style with attribution, widely used in
indie/open-source projects for exactly this) covers all three layouts and is
worth checking against its license terms before vendoring assets into a
public GPL-3.0 repo.

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

## 4. Screen density / readability at 720×480 (really 480i — §0.1) — options

**Superseded by the §1 finding on `Color`/`Style`: don't build a bespoke
scale mechanism.** Every OmaCRT widget should be written against
`Style.font.*` (caption/body/title/heading/display/…) and `Color.*` tokens
from Commons, exactly like first-party widgets are, so it inherits whatever
`[font] base-size` is set to. The only OmaCRT-specific work here is (a)
figuring out, once, what `base-size` reads well from a couch on this specific
TV, and (b) not hardcoding pixel sizes or hex colors anywhere that would
bypass that inheritance.

Facts that still apply regardless of the token mechanism (10-foot UI
convention + broadcast safe-area standard + interlace):
- Viewing distance for a TV is assumed ~10 ft — minimum body text ~24sp
  equivalent, oversized focus indicators, low density, generous spacing. This
  is what tuning `base-size` up is *for*.
- Broadcast **safe-area** standard: keep all interactive content inside the
  **93%** "action-safe" rectangle, keep text inside the **90%** "title-safe"
  rectangle — i.e. at minimum a ~5% margin on every edge before anything
  important is placed, because overscan on real CRTs isn't consistent set to
  set. At 720×480 that's roughly 36px/24px of margin — not optional
  whitespace, it's where a real TV crops the picture. This is a layout margin
  OmaCRT's overlay/launcher needs to apply itself; nothing in the shell's
  token system does it automatically.
- **Confirmed composite → real 480i** (§0.1) makes the interlace-flicker
  guidance load-bearing, not just a nice-to-have: the CRT's own interlaced
  scan (odd lines one pass, even lines the next, 60 fields/sec) means any
  single-scanline-thin horizontal detail is only re-lit 30 times/sec instead
  of 60, which reads as visible twitter — this happens from the *display's*
  scanning method itself, independent of how cleanly the source frame was
  rendered. Practical floor: no border, divider, or icon stroke thinner than
  ~2 scanlines (≈4px at 480 lines); avoid fine repeating horizontal patterns
  entirely; prefer bold/flat fills over hairline outlines.
- Avoid strongly saturated red (or red/cyan adjacency) in text on the analog
  path — composite chroma bleeds most on red, which is exactly the "avoid
  thin red text on black" problem CRT/retro UI designers flag. Worth checking
  each Omarchy theme's `red`/`urgent` token against this before using it for
  small text on OmaCRT surfaces (fine for large fills, risky for a thin
  glyph).

**Remaining open decision:** whether `base-size` gets tuned once by eye and
left alone, or exposed as an OmaCRT setting that calls `omarchy display text
size` under the hood so it's adjustable from the couch without a keyboard.
Leaning toward the latter, same reasoning as before — this needs tuning
against the real screen, and "adjustable from the couch" is itself a
gamepad-UX nicety worth having once the launcher exists to host the setting.

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

All three original questions are resolved — see §0. What's left, smaller and
not blocking:

1. **`base-size` as a setting vs. a one-time tune** (§4) — worth a real
   decision once there's a launcher UI to host the setting in, not before.
2. **Xelu's Controller Prompts license terms** (§2) — confirm before vendoring
   the glyph assets into a public GPL-3.0 repo; if the terms don't fit, the
   fallback is drawing a minimal bold glyph set by hand for the three
   layouts, which is more work but zero licensing risk.
