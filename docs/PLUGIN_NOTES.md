# Omarchy plugin gotchas (not in the shell's own README)

Found the hard way getting `plugins/org.omacrt.launcher` to actually render.
None of this is documented in `/usr/share/omarchy/shell/README.md`; reverse-
engineered by reading first-party (`image-picker`) and third-party
(`io.github.fluffet.display`, already installed on this machine) working
overlay plugins side by side.

## An `overlay`-kind plugin needs its own `PanelWindow`

The manifest's `entryPoints.overlay` file's root can be a plain `Item` — the
host `Loader` doesn't wrap it in a window for you. Without a `PanelWindow`
somewhere in the tree, the plugin loads without error and produces literally
nothing on screen: no warning in the log, no layer-shell surface, nothing.
Ground truth for "did this actually render" is `hyprctl layers` — the plugin
should show up as a namespaced layer at `Layer level 3 (overlay)`. Checking
Quickshell/Hyprland logs is not enough; they stay silent on this failure mode.

## `import Quickshell` is required, not just `import Quickshell.Wayland`

Missing the base module import also fails **silently** — no QML error, no
warning, the `PanelWindow` block type-checks and the plugin's Loader reports
no error status, but no compositor surface ever gets created. Both working
examples import `Quickshell` before `Quickshell.Wayland`; matching that fixed
it.

## The `opened` / `open()` / `close()` convention

The host's plugin loader calls `.open(payloadJson)` on your root item when
summoned (see `deliverIfLoaded` in `shell.qml`), if and only if your item
defines an `open` function. The working pattern, copied from
`io.github.fluffet.display`'s `Arrange.qml`:

```qml
property bool opened: false
function open(payloadJson) { root.opened = true }
function close() { root.opened = false }

PanelWindow {
  visible: root.opened
  anchors { top: true; bottom: true; left: true; right: true }
  WlrLayershell.namespace: "<your-plugin-id>"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore
  ...
}
```

A hardcoded `visible: true` on the `PanelWindow` is not equivalent and, in
testing, did not reliably show the surface either — use the `opened` gate.

## Dev-time hot reload can wedge a plugin into a silent dead state

After enough rapid saves during iteration, a plugin can end up `enabled` and
answering `summon` with `"ok"`, yet never produce a layer-shell surface again
— with nothing in `journalctl`, nothing in `quickshell log`. Confirmed this
isn't a real logic bug by testing a known-working plugin
(`io.github.fluffet.display`) in the same wedged session — it worked fine, so
the problem was accumulated hot-reload state for the specific plugin being
edited, not the shell generally.

**Fix: `omarchy restart shell`.** Cheap, clean, and resolved it immediately.
Reach for this early when a plugin that loads without error still shows
nothing, rather than continuing to debug the QML.

## Useful commands for this loop

```bash
omarchy-shell shell rescanPlugins                  # after adding/removing plugin files
omarchy plugin enable <id>                          # hand-installed plugins start disabled
omarchy-shell shell summon <id> '{}'                # open it
omarchy-shell shell hide <id>                       # close it
hyprctl layers                                       # ground truth: did a surface get created?
omarchy capture screenshot fullscreen save           # visual check
quickshell log -i <instance-id> -t 200               # decoded shell log (journalctl also works)
omarchy restart shell                                # clears wedged dev-time state
```
