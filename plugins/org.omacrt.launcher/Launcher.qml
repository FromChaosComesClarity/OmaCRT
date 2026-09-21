import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons

// OmaCRT's launcher: a slim, gamepad-navigable TV menu that opens the right
// thing and then gets out of the way. It reimplements nothing -- searching a
// library, drawing cover art and launching a game all belong to the apps, and
// the apps already do them well. This plugin is only the gamepad-first entry
// point: safe-area aware, TV-scaled, and first on screen when the Guide button
// is pressed.
//
// Two kinds of destination, which is why there are two mechanisms below:
// IPC into an already-loaded sibling plugin (instant, no process start), and
// starting an app in one of its faces (necessarily a process).
//
// Deliberately NOT a DesktopEntries-derived app grid (an earlier version was
// -- see docs/RESEARCH.md/PLUGIN_NOTES.md for why that approach was dropped
// once these sibling plugins were found).
//
// Summon with:
//   omarchy-shell shell toggle org.omacrt.launcher '{}'
// or the Guide button on the pad (daemon/omacrt_input.py -> F13 -> the
// Hyprland keybind in config/bindings.lua).
Item {
  id: root

  property bool opened: false
  property int currentIndex: 0

  // Finding an app that is installed as an AppImage.
  //
  // There is no package manager entry to ask and no fixed path to hardcode:
  // an AppImage lives wherever the user put it. So each candidate is tried in
  // turn -- an executable file first, then the same name on PATH -- and the
  // first one that exists is exec'd. Shell rather than QML because this is
  // exactly what a shell is for, and because the alternative is a chain of
  // FileView probes to answer a question `-x` answers in one character.
  //
  // ⚠️ The paths are candidates, not configuration. Anyone whose install is
  // somewhere else adds theirs here or drops a launcher on PATH; nothing
  // breaks if a candidate is missing, the next one is tried.
  function launchApp(candidates, args) {
    var list = candidates.map(function(c) { return '"' + c + '"' }).join(' ')
    var argv = args.map(function(a) { return '"' + a + '"' }).join(' ')
    Quickshell.execDetached(["sh", "-c",
      'for c in ' + list + '; do ' +
        'if [ -x "$c" ]; then exec "$c" ' + argv + '; fi; ' +
        'if command -v "$c" >/dev/null 2>&1; then exec "$c" ' + argv + '; fi; ' +
      'done'])
  }

  readonly property var clarityPaths:  ["$HOME/Games/Clarity/Clarity.AppImage", "clarity"]
  readonly property var emulattePaths: ["$HOME/Games/Clarity/EmuLatte.AppImage", "emulatte"]

  /*
   * The menu.
   *
   * CRT Mode leads for both apps, because on this machine it is not a mode, it
   * is how they are used: a menu built for 480 interlaced lines and a D-pad,
   * which is what is plugged in. Couch Mode stays below it for the day the
   * machine is on a panel instead, and "Play something" is Clarity's fuzzy
   * launcher, which already merges EmuLatte's ROMs into one searchable list.
   */
  readonly property var menuActions: [
    {
      id: "clarity-crt", label: "Clarity — CRT Mode", glyph: "◉",
      run: function() { root.launchApp(root.clarityPaths, ["--crt"]) }
    },
    {
      id: "emulatte-crt", label: "EmuLatte — CRT Mode", glyph: "⌸",
      run: function() { root.launchApp(root.emulattePaths, ["--crt"]) }
    },
    {
      id: "clarity-search", label: "Play something", glyph: "◉",
      run: function() { Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "io.github.fromchaoscomesclarity.clarity"]) }
    },
    {
      id: "clarity-couch", label: "Clarity — Couch Mode", glyph: "◉",
      run: function() { root.launchApp(root.clarityPaths, ["--couch"]) }
    },
    {
      id: "emulatte-couch", label: "EmuLatte — Couch Mode", glyph: "⌸",
      run: function() { root.launchApp(root.emulattePaths, ["--couch"]) }
    },
  ]

  function open(payloadJson) {
    root.opened = true
    if (root.currentIndex >= root.menuActions.length) root.currentIndex = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function moveSelection(delta) {
    if (root.menuActions.length === 0) return
    root.currentIndex = (root.currentIndex + delta + root.menuActions.length) % root.menuActions.length
  }

  function runSelected() {
    if (root.currentIndex < 0 || root.currentIndex >= root.menuActions.length) return
    root.menuActions[root.currentIndex].run()
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
          root.runSelected(); event.accepted = true
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

          ListView {
            id: actionList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Style.space(8)
            model: root.menuActions
            currentIndex: root.currentIndex
            interactive: false // navigation is D-pad/keys-driven, not touch/drag
            highlightRangeMode: ListView.ApplyRange
            preferredHighlightBegin: 0
            preferredHighlightEnd: height
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
              required property var modelData
              required property int index
              width: actionList.width
              height: Math.round(Style.font.displayLarge * 1.3)
              radius: Style.cornerRadius
              color: index === root.currentIndex ? Color.accent : Color.menu.background
              border.color: Color.menu.border
              border.width: Math.max(2, Style.normalBorderWidth)

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(16)

                Text {
                  text: modelData.glyph
                  color: index === root.currentIndex ? Color.background : Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  Layout.preferredWidth: Style.font.title
                  horizontalAlignment: Text.AlignHCenter
                }

                Text {
                  Layout.fillWidth: true
                  text: modelData.label
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
