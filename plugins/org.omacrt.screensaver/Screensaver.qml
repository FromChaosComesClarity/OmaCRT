import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

/*
 * OmaCRT's screensaver.
 *
 * A CRT's phosphors wear where the beam is brightest and most constant, so the
 * job here is not "blank the screen" — it is "make sure no part of the screen
 * is asked to be bright for long". That gives three rules, and the whole plugin
 * follows from them:
 *
 *   1. Near-black ground. Black is the beam at rest; every lit pixel is wear.
 *   2. Exactly one lit element, dim, and large enough that its strokes survive
 *      interlace (a thin bright glyph is both the worst burn-in shape and the
 *      worst thing to draw on a 480i display).
 *   3. It must keep moving, slowly, and cover the raster rather than tracing
 *      the same path forever.
 *
 * ⚠️ This replaces Omarchy's own screensaver rather than joining it. Omarchy's
 * opens a terminal running ttfx effects, which is a fine screensaver for a
 * panel and close to the opposite of the three rules above: bright, dense with
 * single-pixel detail, and drawn everywhere at once. Disable it with
 *
 *     touch ~/.local/state/omarchy/toggles/screensaver-off
 *
 * or both will fire at the same idle timeout and race for the screen. See
 * docs/SETUP.md.
 *
 * Why this lives inside omarchy-shell rather than being a process of its own:
 * §1 of docs/RESEARCH.md — a second Qt runtime is the most expensive mistake
 * available on a 4 GB machine, and the idle detection it needs is a Wayland
 * protocol Quickshell already exposes here.
 *
 * This file only draws. The idle timer that summons it lives in
 * IdleService.qml, for a reason worth reading before merging the two back
 * together.
 *
 * It can also be summoned by hand, which is how it gets looked at without
 * waiting several minutes:
 *
 *     omarchy-shell shell toggle org.omacrt.screensaver '{}'
 */
Item {
  id: root

  property bool opened: false

  // ⚠️ Cutting the beam entirely is the strongest protection there is, and it
  // is off by default anyway: waking a CRT through an HDMI→composite converter
  // depends on the adapter re-syncing, and this project's adapter has not been
  // proven to do that reliably. Set a value in seconds (from when the
  // screensaver starts) only after testing that the picture actually comes
  // back on your own hardware. 0 disables it.
  readonly property int blankAfterSeconds: 0

  // The drift stays inside the action-safe box. Reaching the corners would
  // spread the wear marginally more evenly, but a CRT crops them, so the clock
  // would spend that time half-visible for no benefit — the protection comes
  // from moving, not from touching the edges.
  readonly property real safeInset: 0.07

  function open(payloadJson) { root.show() }
  function close() { root.hide() }

  function show() {
    if (root.opened) return
    root.opened = true
    Quickshell.execDetached(["hyprctl", "keyword", "cursor:invisible", "true"])
    if (root.blankAfterSeconds > 0) blankTimer.restart()
    root.startDrift()
  }

  /*
   * ⚠️ Place the element before animating it — and do not believe the window's
   * size until the box it implies makes sense.
   *
   * A layer surface is sized by the compositor, not by us, and on the way there
   * it reports whatever it currently is: measured here, 100x100, then 0x0, then
   * 500x500, all within the same frame as `opened` flipping. A placement
   * computed from any of those produces a negative range and silently does
   * nothing, which is exactly what the first version did: every session started
   * at 0,0 and drifted inward from the corner. That is both the one spot a CRT
   * is guaranteed to crop and, far worse, the one spot the screensaver would
   * light every single time. A screensaver with a favourite corner is a
   * burn-in mark waiting to happen.
   *
   * So the trigger is the drift box becoming valid, not the window becoming
   * visible. drift.boxValid re-evaluates on every size change, so whichever
   * size arrives last is the one that places the clock.
   */
  function startDrift() {
    if (!root.opened || !drift.boxValid) return
    drift.placeRandom()
    drift.retarget()
  }

  function hide() {
    if (!root.opened) return
    root.opened = false
    blankTimer.stop()
    Quickshell.execDetached(["hyprctl", "keyword", "cursor:invisible", "false"])
    // Whatever woke the machine also has to undo a blanked output, or the user
    // is left pressing keys at a dark tube wondering what broke.
    if (root.blanked) {
      root.blanked = false
      Quickshell.execDetached(["hyprctl", "dispatch", "dpms", "on"])
    }
  }

  property bool blanked: false

  Timer {
    id: blankTimer
    interval: Math.max(1, root.blankAfterSeconds) * 1000
    repeat: false
    onTriggered: {
      if (!root.opened) return
      root.blanked = true
      Quickshell.execDetached(["hyprctl", "dispatch", "dpms", "off"])
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "black"
    WlrLayershell.namespace: "omacrt-screensaver"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive focus so the keystroke that dismisses this is swallowed here
    // rather than landing in whatever was underneath. Pressing a button to wake
    // a screensaver should not also press that button in the app behind it.
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // The surface being shown is the earliest point at which its size is known,
    // which is what the placement needs.
    onVisibleChanged: if (visible) root.startDrift()

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      // Any key at all. IdleMonitor will report activity a moment later anyway;
      // dismissing here as well is what makes the wake feel immediate.
      Keys.onPressed: function(event) { root.hide(); event.accepted = true }
    }

    /*
     * The one lit thing.
     *
     * A clock, because on a machine wired to a TV the screensaver is what is on
     * screen most of the day, and a dim clock is the most useful thing a dark
     * screen can be. Drawn large and heavy: at 480 interlaced lines a light
     * weight at a small size is a field-strobing mess, and thin bright strokes
     * are exactly the shape that burns in.
     */
    Item {
      id: drift
      width: stack.implicitWidth
      height: stack.implicitHeight

      readonly property real minX: panel.width * root.safeInset
      readonly property real maxX: panel.width * (1 - root.safeInset) - width
      readonly property real minY: panel.height * root.safeInset
      readonly property real maxY: panel.height * (1 - root.safeInset) - height

      // A box the clock actually fits inside. False for every size the surface
      // reports on its way to the real one.
      readonly property bool boxValid: maxX > minX && maxY > minY
      onBoxValidChanged: if (boxValid) root.startDrift()

      // ~14 px/s. Slow enough to read as drifting rather than bouncing, fast
      // enough that it is somewhere else every time you look up.
      readonly property real speed: 14

      function placeRandom() {
        if (!boxValid) return
        move.stop()
        x = minX + Math.random() * (maxX - minX)
        y = minY + Math.random() * (maxY - minY)
      }

      function retarget() {
        if (!boxValid) return
        var tx = minX + Math.random() * (maxX - minX)
        var ty = minY + Math.random() * (maxY - minY)
        var dist = Math.sqrt(Math.pow(tx - x, 2) + Math.pow(ty - y, 2))
        var ms = Math.max(8000, (dist / speed) * 1000)
        moveX.to = tx; moveX.duration = ms
        moveY.to = ty; moveY.duration = ms
        move.restart()
      }

      ParallelAnimation {
        id: move
        // Easing rather than linear: a constant-velocity element that stops
        // dead and sets off again draws the eye to the turn. This one never
        // appears to have a destination.
        NumberAnimation { id: moveX; target: drift; property: "x"; easing.type: Easing.InOutSine }
        NumberAnimation { id: moveY; target: drift; property: "y"; easing.type: Easing.InOutSine }
        onFinished: if (root.opened) drift.retarget()
      }

      Column {
        id: stack
        spacing: 10

        Text {
          id: clock
          text: Qt.formatDateTime(clockSource.now, "HH:mm")
          // Dim on purpose. This is the brightest thing on screen for hours at
          // a time, so it sits just above "visible in a dark room" — roughly a
          // third of the theme's foreground luminance.
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.34)
          font.family: Style.font.family
          font.pixelSize: 112
          font.weight: Font.Bold
        }

        Text {
          text: Qt.formatDateTime(clockSource.now, "dddd d MMMM").toUpperCase()
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.22)
          font.family: Style.font.family
          font.pixelSize: 22
          font.weight: Font.DemiBold
          font.letterSpacing: 3
        }
      }
    }

    // One tick a minute: the clock shows minutes, and a per-second timer on a
    // screen nobody is looking at is a second of CPU every minute for nothing.
    QtObject {
      id: clockSource
      property var now: new Date()
    }
    Timer {
      running: root.opened
      interval: 60000
      repeat: true
      triggeredOnStart: true
      onTriggered: clockSource.now = new Date()
    }
  }
}
