import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

/*
 * OmaCRT's launcher: the TV menu.
 *
 * It opens the right thing and gets out of the way. Searching a library,
 * drawing cover art and launching a game all belong to the apps, and the apps
 * do them well; this is the entry point — safe-area aware, TV-scaled, legible
 * at 480 interlaced lines.
 *
 * ⚠️ It is also where the status bar went, and that is the more interesting
 * half. A bar anchors to the physical edge of the raster, which is exactly the
 * strip a tube crops, and Omarchy's bar config offers position, transparency
 * and layout — no inset — so on this set most of it sits behind the bezel.
 * Rather than replace the bar, its contents moved here, which is better than
 * fixing it would have been: a status bar is bright, static and permanently on
 * screen, the precise recipe for the burn-in this whole project is built to
 * avoid (docs/RESEARCH.md §3). Here the same information and the same controls
 * live inside the title-safe box and are only lit while someone is looking.
 *
 * Nothing about sound, network or Bluetooth is reimplemented. Omarchy already
 * ships the verbs — `omarchy-audio-output-volume`, `omarchy-bluetooth-device`,
 * `omarchy-bluetooth-power` — and using them means the volume OSD, the
 * remembered Bluetooth power state and every other behaviour stay consistent
 * with the rest of the system. Where there is no verb, the answer is the tool
 * that owns the job: `nmtui` for network configuration, in a terminal, which is
 * keyboard-driven and perfectly legible at this resolution.
 *
 * Summon with:
 *   omarchy-shell shell toggle org.omacrt.launcher '{}'
 * or SUPER + M (config/bindings.lua).
 */
Item {
  id: root

  property bool opened: false
  property int currentIndex: 0

  // Which menu is on screen, and how to get back. Rows are rebuilt from a
  // builder rather than stored, so a menu showing live state (Bluetooth
  // devices, volume) redraws correctly the moment that state arrives.
  property string menuId: "root"
  property var menuStack: []
  property var rows: []

  readonly property string terminal: "foot"

  // ── Launching apps ─────────────────────────────────────────────────────────
  //
  // There is no package-manager entry to ask and no fixed path to hardcode: an
  // AppImage lives wherever the user put it. So each candidate is tried in turn
  // — an executable file first, then the same name on PATH — and the first that
  // exists is exec'd. Shell rather than QML because this is what a shell is
  // for, and the alternative is a chain of FileView probes to answer what `-x`
  // answers in one character.
  //
  // ⚠️ The paths are candidates, not configuration. An install somewhere else
  // adds its path here or drops a launcher on PATH; a missing candidate is not
  // an error, the next one is tried.
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

  function run(argv)      { Quickshell.execDetached(argv) }
  // A TUI needs a terminal, and this one should own the screen while it runs.
  function runInTerminal(command) {
    Quickshell.execDetached([root.terminal, "--title", "OmaCRT", "sh", "-c", command])
  }

  // ── Menus ──────────────────────────────────────────────────────────────────

  function rootRows() {
    return [
      { label: "Clarity",       glyph: "◉", detail: "CRT",  run: function() { root.launchApp(root.clarityPaths, ["--crt"]); root.close() } },
      { label: "EmuLatte",      glyph: "⌸", detail: "CRT",  run: function() { root.launchApp(root.emulattePaths, ["--crt"]); root.close() } },
      { label: "Play something", glyph: "⌕", detail: "",    run: function() { root.run(["omarchy-shell", "shell", "toggle", "io.github.fromchaoscomesclarity.clarity"]); root.close() } },
      { label: "Sound",     glyph: "◀", detail: root.volText, submenu: "sound" },
      { label: "Network",   glyph: "≋", detail: root.netText, submenu: "network" },
      { label: "Bluetooth", glyph: "✳", detail: root.btText || (root.btPowered ? "ON" : "OFF"), submenu: "bluetooth" },
    ]
  }

  // Volume goes through Omarchy's own helper rather than wpctl directly, so a
  // change made here shows the same OSD as one made anywhere else.
  function soundRows() {
    return [
      { label: "Volume up",     glyph: "+", detail: root.volText, keep: true,
        run: function() { root.run(["omarchy-audio-output-volume", "+5"]); root.refreshLater() } },
      { label: "Volume down",   glyph: "−", detail: "",            keep: true,
        run: function() { root.run(["omarchy-audio-output-volume", "-5"]); root.refreshLater() } },
      { label: "Mute",          glyph: "∅", detail: "",            keep: true,
        run: function() { root.run(["omarchy-audio-output-volume", "mute-toggle"]); root.refreshLater() } },
      { label: "Switch output", glyph: "⇄", detail: "",            keep: true,
        run: function() { root.run(["omarchy-audio-output-switch"]); root.refreshLater() } },
    ]
  }

  function networkRows() {
    return [
      { label: "Wi-Fi settings", glyph: "≋", detail: root.netText,
        // nmtui is the right answer here: choosing a network and typing a
        // password needs a keyboard and a text field, which a menu of rows is
        // the wrong shape for. It is keyboard-driven and legible at 480 lines.
        run: function() { root.runInTerminal("nmtui"); root.close() } },
      { label: "Restart Wi-Fi",  glyph: "⟳", detail: "", keep: true,
        run: function() { root.run(["omarchy-restart-wifi"]); root.refreshLater() } },
      { label: "Connection info", glyph: "ℹ", detail: "", keep: true,
        run: function() { root.runInTerminal("omarchy-network-status; echo; echo 'Press enter to close'; read x"); root.close() } },
    ]
  }

  // The one question this menu is asked most is whether the controller is
  // connected, so paired devices are listed with their state and toggling one
  // is a single press.
  function bluetoothRows() {
    var list = [
      { label: root.btPowered ? "Bluetooth is on" : "Bluetooth is off",
        glyph: "✳", detail: root.btPowered ? "ON" : "OFF", keep: true,
        run: function() { root.run(["omarchy-bluetooth-power", "toggle"]); root.refreshLater() } },
    ]
    for (var i = 0; i < root.btDevices.length; i++) {
      (function(dev) {
        list.push({
          label: dev.name,
          glyph: dev.connected ? "●" : "○",
          detail: dev.connected ? "CONNECTED" : "",
          keep: true,
          run: function() {
            root.run(["omarchy-bluetooth-device", dev.connected ? "disconnect" : "connect", dev.address])
            root.refreshLater()
          }
        })
      })(root.btDevices[i])
    }
    if (!root.btDevices.length) {
      list.push({ label: "No paired devices", glyph: "·", detail: "", disabled: true })
    }
    list.push({ label: "Pair a new device", glyph: "+", detail: "",
      run: function() { root.runInTerminal("bluetoothctl"); root.close() } })
    return list
  }

  function buildRows(id) {
    if (id === "sound")     return soundRows()
    if (id === "network")   return networkRows()
    if (id === "bluetooth") return bluetoothRows()
    return rootRows()
  }

  function rebuild() { root.rows = buildRows(root.menuId) }

  function showMenu(id) {
    var stack = root.menuStack.slice()
    stack.push({ id: root.menuId, index: root.currentIndex })
    root.menuStack = stack
    root.menuId = id
    root.currentIndex = 0
    root.refreshStatus()
    root.rebuild()
  }

  function goBack() {
    if (!root.menuStack.length) { root.close(); return }
    var stack = root.menuStack.slice()
    var prev = stack.pop()
    root.menuStack = stack
    root.menuId = prev.id
    root.currentIndex = prev.index
    root.rebuild()
  }

  function activate() {
    var row = root.rows[root.currentIndex]
    if (!row || row.disabled) return
    if (row.submenu) { root.showMenu(row.submenu); return }
    if (typeof row.run === "function") row.run()
  }

  function moveSelection(delta) {
    if (!root.rows.length) return
    var i = root.currentIndex
    for (var n = 0; n < root.rows.length; n++) {
      i = (i + delta + root.rows.length) % root.rows.length
      if (!root.rows[i].disabled) break
    }
    root.currentIndex = i
  }

  // ── Status ─────────────────────────────────────────────────────────────────
  // Read by asking whatever owns the answer, when the menu opens rather than on
  // a timer: this is on screen for seconds at a time, and a poll running all
  // day to service it would be pure cost on a 4 GB machine. Each reader is
  // independent, so a machine with no Bluetooth simply shows none.

  property string clockText: ""
  property string dateText: ""
  property string netText: ""
  property string volText: ""
  property string btText: ""
  property bool   btPowered: false
  property var    btDevices: []

  function refreshStatus() {
    var now = new Date()
    root.clockText = Qt.formatDateTime(now, "HH:mm")
    root.dateText = Qt.formatDateTime(now, "ddd d MMM").toUpperCase()
    netProc.running = true
    volProc.running = true
    btPowerProc.running = true
    btProc.running = true
  }

  // ⚠️ After an action, not during it. Every one of these helpers is
  // fire-and-forget — the volume is set, the device connects — and asking
  // immediately reads the state from before the change. A short delay is the
  // difference between a menu that updates and one that lies.
  function refreshLater() { settleTimer.restart() }
  Timer {
    id: settleTimer
    interval: 700
    repeat: false
    onTriggered: { root.refreshStatus(); root.rebuild() }
  }

  // NetworkManager's own view. First connected device wins; parsed here rather
  // than in awk, because quoting a shell pipeline inside QML to extract one
  // field is three levels of escaping for no gain.
  Process {
    id: netProc
    command: ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = ""
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var f = lines[i].split(":")
          if (f.length >= 3 && f[1] === "connected" && f[0] !== "loopback") {
            out = (f[0] === "wifi" ? "" : f[0].toUpperCase() + " ") + f[2]
            break
          }
        }
        root.netText = out ? out.toUpperCase() : "OFFLINE"
        root.rebuild()
      }
    }
  }

  // wpctl is what knows, PipeWire being the mixer. Output is "Volume: 0.42",
  // with " [MUTED]" appended when muted.
  Process {
    id: volProc
    command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
    stdout: StdioCollector {
      onStreamFinished: {
        var t = String(text || "")
        if (/MUTED/i.test(t)) { root.volText = "MUTED"; root.rebuild(); return }
        var m = t.match(/([0-9]*\.?[0-9]+)/)
        root.volText = m ? Math.round(parseFloat(m[1]) * 100) + "%" : ""
        root.rebuild()
      }
    }
  }

  // ⚠️ `omarchy-bluetooth-power is-on` answers with its *exit status* and prints
  // nothing at all, so reading its stdout reported "off" for a radio that was
  // plainly on. Turned into a word here rather than reaching for exit codes,
  // because one shell idiom is easier to read than two QML signal handlers.
  Process {
    id: btPowerProc
    command: ["sh", "-c", "omarchy-bluetooth-power is-on && echo on || echo off"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.btPowered = String(text || "").trim() === "on"
        root.rebuild()
      }
    }
  }

  // Paired devices, and which of them are connected. Two lists rather than
  // one, because `devices Paired` does not say and `devices Connected` does
  // not list the rest.
  Process {
    id: btProc
    command: ["sh", "-c", "bluetoothctl devices Paired; echo ---; bluetoothctl devices Connected"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parts = String(text || "").split("---")
        var parse = function(block) {
          var out = []
          var lines = String(block || "").split("\n")
          for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(/^Device\s+(\S+)\s+(.+)$/)
            if (m) out.push({ address: m[1], name: m[2].trim() })
          }
          return out
        }
        var paired = parse(parts[0])
        var connected = parse(parts[1])
        var isConnected = function(addr) {
          for (var i = 0; i < connected.length; i++) if (connected[i].address === addr) return true
          return false
        }
        var devices = []
        for (var i = 0; i < paired.length; i++) {
          devices.push({ address: paired[i].address, name: paired[i].name, connected: isConnected(paired[i].address) })
        }
        root.btDevices = devices
        root.btText = connected.length ? connected[0].name.toUpperCase() : ""
        root.rebuild()
      }
    }
  }

  // The clock would otherwise be wrong by however long the menu has been open.
  Timer {
    running: root.opened
    interval: 10000
    repeat: true
    onTriggered: root.refreshStatus()
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  function open(payloadJson) {
    root.opened = true
    root.menuId = "root"
    root.menuStack = []
    root.currentIndex = 0
    root.refreshStatus()
    root.rebuild()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }

  Component.onCompleted: root.rebuild()

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
        if (event.key === Qt.Key_Up) {
          root.moveSelection(-1); event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.moveSelection(1); event.accepted = true
        } else if (event.key === Qt.Key_Right) {
          var row = root.rows[root.currentIndex]
          if (row && row.submenu) root.showMenu(row.submenu)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activate(); event.accepted = true
        } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Left || event.key === Qt.Key_Backspace) {
          root.goBack(); event.accepted = true
        }
      }

      // Action-safe area: ~5% a side, per docs/RESEARCH.md §4. Not decoration —
      // it is where the tube stops showing the signal.
      Item {
        anchors.fill: parent
        anchors.margins: Math.round(Math.min(parent.width, parent.height) * 0.05)

        ColumnLayout {
          anchors.fill: parent
          spacing: 10

          // Title and clock share the top line: the clock is the one piece of
          // status worth reading at a glance, so it gets a corner rather than a
          // place in the queue at the bottom.
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(16)

            Text {
              text: root.menuId === "root" ? "OmaCRT"
                  : root.menuId === "sound" ? "OmaCRT › Sound"
                  : root.menuId === "network" ? "OmaCRT › Network"
                  : "OmaCRT › Bluetooth"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Item { Layout.fillWidth: true }

            Text {
              text: root.clockText
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
            }
          }

          ListView {
            id: actionList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.rows
            currentIndex: root.currentIndex
            interactive: false // navigation is keys-driven, not touch/drag
            highlightRangeMode: ListView.ApplyRange
            preferredHighlightBegin: 0
            preferredHighlightEnd: height
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
              id: rowRect
              required property var modelData
              required property int index
              width: actionList.width
              // ⚠️ Sized from the list, not from the font. The shell's font
              // scale is tuned for legibility across the room, which made rows
              // tall enough that half the menu fell below the fold — and a menu
              // item you cannot see is one that does not exist. Six rows fit by
              // construction, whatever the font is set to.
              height: Math.max(36, Math.floor(actionList.height / 6) - actionList.spacing)
              radius: Style.cornerRadius
              color: index === root.currentIndex ? Color.accent
                   : modelData.disabled ? "transparent" : Color.menu.background
              border.color: modelData.disabled ? "transparent" : Color.menu.border
              border.width: modelData.disabled ? 0 : Math.max(2, Style.normalBorderWidth)

              RowLayout {
                anchors.fill: parent
                // ⚠️ Plain pixels, not Style.space(): the spacing scale is tied
                // to the shell's font size, which is tuned large for a TV, so
                // Style.space(10) is ~25px here. Against a ~50px row that left
                // the contents zero height and everything drew on top of
                // everything else.
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 4
                anchors.bottomMargin: 4
                spacing: 12

                Text {
                  text: modelData.glyph
                  color: index === root.currentIndex ? Color.background : Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Math.round(rowRect.height * 0.42)
                  Layout.preferredWidth: Math.round(rowRect.height * 0.55)
                  horizontalAlignment: Text.AlignHCenter
                }

                Text {
                  Layout.fillWidth: true
                  text: modelData.label
                  elide: Text.ElideRight
                  color: index === root.currentIndex ? Color.background
                       : modelData.disabled ? Color.muted : Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Math.round(rowRect.height * 0.42)
                  font.bold: index === root.currentIndex
                }

                // The row's own state, where a bar would have put an icon:
                // volume percentage, the connected network, CONNECTED.
                Text {
                  visible: !!modelData.detail
                  text: modelData.detail || ""
                  color: index === root.currentIndex ? Color.background : Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Math.round(rowRect.height * 0.30)
                  font.bold: true
                }
              }
            }
          }

          // Everything the bar used to say, on one line, inside the safe box.
          Text {
            Layout.fillWidth: true
            visible: root.menuId === "root"
            text: [root.dateText, root.netText, root.volText ? "VOL " + root.volText : "", root.btText]
                    .filter(function(s) { return !!s }).join("   ·   ")
            color: Color.muted
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }
      }
    }
  }
}
