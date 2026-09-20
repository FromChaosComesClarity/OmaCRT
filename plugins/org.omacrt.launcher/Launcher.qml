import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons

// OmaCRT's real launcher: a curated, gamepad-navigable app list. Uses
// Quickshell's own DesktopEntries singleton and Quickshell.iconPath()/
// Util.execDetached() directly -- the same primitives Omarchy's own
// AppLibrary.qml is built on -- rather than the shell's third-party
// appLibrary facade (gated behind declaring kind "menu"): that facade's
// appLibrary came back null for this plugin for reasons not fully root
// caused (manifest.kinds confirmed correct via debug logging; likely a
// caching/profile quirk in the host's createScopedPluginShell -- see
// docs/PLUGIN_NOTES.md). Going straight to the plain Quickshell APIs
// sidesteps that entirely and is just as correct. Summon with:
//   omarchy-shell shell toggle org.omacrt.launcher '{}'
// or the Guide button on the pad (daemon/omacrt_input.py -> F13 -> the
// Hyprland keybind in config/bindings.lua).
Item {
  id: root

  property bool opened: false
  property int currentIndex: 0

  // The curated set this launcher shows, in display order -- not every
  // installed app, just this account's own apps as they get adapted for the
  // CRT (see docs/RESEARCH.md's project goal). Matches the desktop-entry ids
  // in ~/.local/share/applications/*.desktop.
  readonly property var curatedAppIds: ["clarity-couch", "clarity", "emulatte"]

  readonly property var menuEntries: {
    var all = DesktopEntries.applications.values || []
    var byId = ({})
    for (var i = 0; i < all.length; i++) byId[all[i].id] = all[i]
    var out = []
    for (var j = 0; j < curatedAppIds.length; j++) {
      var e = byId[curatedAppIds[j]]
      if (e) out.push(e)
    }
    return out
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    if (themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  function open(payloadJson) {
    root.opened = true
    if (root.currentIndex >= root.menuEntries.length) root.currentIndex = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function moveSelection(delta) {
    if (root.menuEntries.length === 0) return
    root.currentIndex = (root.currentIndex + delta + root.menuEntries.length) % root.menuEntries.length
  }

  function launchSelected() {
    if (root.currentIndex < 0 || root.currentIndex >= root.menuEntries.length) return
    var entry = root.menuEntries[root.currentIndex]
    // Same launch command Omarchy's own AppLibrary.qml uses: gtk-launch
    // resolves the desktop id (handles ids with spaces / dots correctly),
    // uwsm-app scopes it outside the shell's own systemd unit.
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(entry.id + ".desktop"))
    root.close()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omacrt-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.background
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
          root.moveSelection(-1); event.accepted = true
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
          root.moveSelection(1); event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.launchSelected(); event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.close(); event.accepted = true
        }
      }

      // Action-safe area: ~5% margin, per docs/RESEARCH.md #4.
      Item {
        anchors.fill: parent
        anchors.margins: Math.round(Math.min(parent.width, parent.height) * 0.05)

        ColumnLayout {
          anchors.fill: parent
          spacing: Style.space(20)

          Text {
            text: "OmaCRT"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Text {
            visible: root.menuEntries.length === 0
            text: "No apps configured yet."
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          ListView {
            id: appList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Style.space(8)
            model: root.menuEntries
            currentIndex: root.currentIndex
            interactive: false // navigation is D-pad/keys-driven, not touch/drag
            highlightRangeMode: ListView.ApplyRange
            preferredHighlightBegin: 0
            preferredHighlightEnd: height
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
              required property var modelData
              required property int index
              width: appList.width
              height: Math.round(Style.font.displayLarge * 1.3)
              radius: Style.cornerRadius
              color: index === root.currentIndex ? Color.accent : Color.menu.background
              border.color: Color.menu.border
              border.width: Math.max(2, Style.normalBorderWidth)

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(16)

                Image {
                  source: root.iconSource(modelData.icon)
                  Layout.preferredWidth: Style.font.title
                  Layout.preferredHeight: Style.font.title
                  fillMode: Image.PreserveAspectFit
                }

                Text {
                  Layout.fillWidth: true
                  text: modelData.name || modelData.id
                  color: index === root.currentIndex ? Color.background : Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: index === root.currentIndex
                }
              }
            }
          }
        }
      }
    }
  }
}
