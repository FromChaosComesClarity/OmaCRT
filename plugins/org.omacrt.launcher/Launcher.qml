import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Placeholder for the real gamepad-navigable launcher overlay. Exists only to
// prove: the plugin loads, it gets an actual layer-shell surface, it can read
// the active theme's Color/Style tokens (so it already follows whatever
// Omarchy theme is active), and it respects the broadcast safe-area margin
// from the start rather than bolting it on later. Summon with:
//   omarchy-shell shell toggle org.omacrt.launcher '{}'
Item {
  id: root

  property bool opened: false

  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omacrt-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.background
    }

    // Action-safe area: ~5% margin on every edge, per broadcast safe-area
    // convention (docs/RESEARCH.md §4 in the OmaCRT repo). Drawn here so
    // it's visible while tuning against the real screen, not just implied.
    Rectangle {
      anchors.fill: parent
      anchors.margins: Math.round(Math.min(parent.width, parent.height) * 0.05)
      color: "transparent"
      border.color: Color.accent
      border.width: 4 // never thinner than ~2 scanlines at 480 lines (§4)

      Text {
        anchors.centerIn: parent
        text: "OmaCRT"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.displayLarge
        font.bold: true
      }
    }
  }
}
