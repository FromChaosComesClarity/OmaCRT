import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// OmaCRT's Meta+K equivalent: shows what each gamepad button currently does,
// using the active controller layout's glyphs. Summon with:
//   omarchy-shell shell toggle org.omacrt.cheatsheet '{}'
// or the Select button on the pad (daemon/omacrt_input.py -> F14 -> the
// Hyprland keybind in ~/.config/hypr/bindings.lua).
Item {
  id: root

  property bool opened: false
  property string layout: "xbox" // updated by layoutFile below

  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  // Written by daemon/omacrt_input.py at startup -- see docs/RESEARCH.md #2.
  // Not watched for live updates yet: the daemon doesn't support switching
  // layout without a restart, so there's nothing to watch for yet either.
  property FileView layoutFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omacrt/layout"
    watchChanges: false
    printErrors: false
    onLoaded: {
      var v = text().trim()
      if (v === "xbox" || v === "playstation" || v === "nintendo") root.layout = v
    }
  }

  // confirm/back glyphs per layout -- see daemon/README.md for why these
  // specific mappings (evdev normalizes physical position across brands;
  // Nintendo's own convention swaps confirm/back relative to Xbox).
  readonly property var glyphs: ({
    "xbox": { confirm: "A", back: "B" },
    "playstation": { confirm: "✕", back: "○" }, // ✕ ○
    "nintendo": { confirm: "A", back: "B" },
  })

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omacrt-cheatsheet"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: Math.min(parent.width * 0.9, 640)
      // ~5% action-safe margin top/bottom too, per docs/RESEARCH.md #4.
      height: Math.min(parent.height * 0.9, layoutCol.implicitHeight + Style.space(64))
      radius: Style.cornerRadius
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: Math.max(2, Style.normalBorderWidth)

      ColumnLayout {
        id: layoutCol
        anchors.centerIn: parent
        width: parent.width - Style.space(64)
        spacing: Style.space(20)

        Text {
          text: "Controller"
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Repeater {
          model: [
            { glyph: "↕↔", label: "Navigate", key: "" },
            { glyph: root.glyphs[root.layout].confirm, label: "Select", key: "" },
            { glyph: root.glyphs[root.layout].back, label: "Back", key: "" },
            // Both, and in this order: Start is the one that can be relied on,
            // Guide is the one people reach for. Listing only Guide was true
            // right up until the pad stopped sending it.
            { glyph: "≡", label: "Launcher — Start (works anytime, even mid-game)", key: "" },
            { glyph: "⌂", label: "Launcher — Guide, where the pad sends it", key: "" },
          ]

          delegate: RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(16)

            Rectangle {
              width: Style.font.displayLarge * 1.6
              height: width
              radius: width / 2
              color: index === 1 ? Color.accent : (index === 2 ? Color.urgent : Color.menu.background)
              border.color: Color.menu.text
              border.width: Math.max(2, Style.normalBorderWidth)

              Text {
                anchors.centerIn: parent
                text: modelData.glyph
                color: index === 1 || index === 2 ? Color.background : Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
              }
            }

            Text {
              Layout.fillWidth: true
              text: modelData.label
              color: Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }
}
