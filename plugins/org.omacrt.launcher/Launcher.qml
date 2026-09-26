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

  // ── The app list: discovered, pinned, hidden ────────────────────
  //
  // Three sources feed the app rows, and they are deliberately different kinds
  // of thing:
  //
  //   1. Clarity and EmuLatte, above — this machine's own apps, hardcoded,
  //      because they are the reason the TV is on.
  //   2. ~/Applications/*.AppImage — discovered, never stored. The folder *is*
  //      the configuration: drop an AppImage in and it is a menu row the next
  //      time the menu opens, with no edit here and no shell restart. Nothing
  //      in this group can be deleted from the menu, only hidden, and hiding is
  //      a reversible line in `hidden` below.
  //   3. Pinned desktop entries — anything installed, chosen once in "Add app"
  //      and stored by desktop id.
  //
  // State lives in ~/.config/omacrt/launcher.json:
  //
  //   { "version": 1,
  //     "pinned": [ { "id": "org.kde.krita", "label": "Krita" } ],
  //     "hidden": [ "/home/jose/Applications/Something.AppImage" ] }
  //
  // ~/.config rather than ~/.local/state because every line of it is a choice
  // the user made on purpose — it is configuration worth backing up, not
  // reconstructible cache.
  readonly property string homeDir:   Quickshell.env("HOME")
  readonly property string appsDir:   root.homeDir + "/Applications"
  readonly property string stateDir:  root.homeDir + "/.config/omacrt"
  readonly property string statePath: root.stateDir + "/launcher.json"

  property var appImages: []    // discovered: [{ path, label }]
  property var pinnedApps: []   // persisted:  [{ id, label }]
  property var hiddenPaths: []  // persisted:  absolute AppImage paths

  /*
   * ⚠️ `find` rather than a QML FolderListModel, for one reason: the test that
   * decides whether a row should exist is `-executable`, and Qt's directory
   * models cannot ask it. An AppImage that lost its +x bit is not an app, it is
   * a 120 MB file that will fail silently when selected.
   *
   * `*_old.AppImage` is this project's convention for a version kept back
   * during an upgrade, so it is excluded by name rather than shown as a second,
   * near-identical row.
   */
  Process {
    id: appImageScan
    command: ["sh", "-c",
      'd="$1"; [ -d "$d" ] || exit 0; ' +
      'find -L "$d" -maxdepth 1 -type f -name "*.AppImage" ' +
        '! -name "*_old.AppImage" -executable -print 2>/dev/null | LC_ALL=C sort -f',
      "sh", root.appsDir]
    stdout: StdioCollector {
      onStreamFinished: {
        var found = []
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var path = lines[i].trim()
          if (!path) continue
          var base = path.split("/").pop()
          found.push({ path: path, label: base.replace(/\.AppImage$/, "") })
        }
        root.appImages = found
        root.rebuild()
      }
    }
  }

  function scanAppImages() {
    if (!appImageScan.running) appImageScan.running = true
  }

  Process { id: ensureStateDir; command: ["mkdir", "-p", root.stateDir] }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    // ⚠️ First run: the file does not exist. Without this branch the load never
    // completes, and a hand-edited or missing file would leave the menu with no
    // pinned apps and no way to notice why.
    onLoadFailed: root.loadState("")
  }

  // A corrupt file is worth a warning and nothing more. The menu still works
  // without its saved list; refusing to open would be the worse failure.
  function loadState(raw) {
    var pinned = []
    var hidden = []
    var body = String(raw || "").trim()
    if (body) {
      try {
        var parsed = JSON.parse(body)
        var p = parsed ? parsed.pinned : null
        if (p && p.length !== undefined) {
          for (var i = 0; i < p.length; i++) {
            var id = root.normalizeDesktopId(p[i] ? p[i].id : "")
            if (id) pinned.push({ id: id, label: String((p[i] && p[i].label) || id) })
          }
        }
        var h = parsed ? parsed.hidden : null
        if (h && h.length !== undefined) {
          for (var j = 0; j < h.length; j++) {
            var path = String(h[j] || "").trim()
            if (path) hidden.push(path)
          }
        }
      } catch (e) {
        console.warn("omacrt-launcher: ignoring unreadable " + root.statePath + ":", e)
      }
    }
    root.pinnedApps = pinned
    root.hiddenPaths = hidden
    root.rebuild()
  }

  // ⚠️ mkdir is a separate process, so the write cannot follow it in the same
  // tick — the first ever save would land in a directory that does not exist
  // yet and be dropped without a word. The timer buys mkdir its tick, and
  // coalesces a burst of toggles into one write for free.
  function saveState() {
    ensureStateDir.running = true
    saveTimer.restart()
  }

  Timer {
    id: saveTimer
    interval: 150
    repeat: false
    onTriggered: stateFile.setText(JSON.stringify({
      version: 1,
      pinned: root.pinnedApps,
      hidden: root.hiddenPaths
    }, null, 2) + "\n")
  }

  function normalizeDesktopId(id) {
    var value = String(id || "").trim()
    if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
    return value
  }

  /*
   * Installed applications, straight from Quickshell.
   *
   * ⚠️ Not through `shell.appLibrary`. Omarchy's `"menu"` plugin kind is meant
   * to inject exactly this service and it hands back null on this machine, with
   * no warning anywhere — see docs/PLUGIN_NOTES.md before spending an evening
   * on it. `DesktopEntries` is what that service is built on anyway, so this
   * loses nothing.
   */
  function desktopEntries() {
    var values = []
    try { values = DesktopEntries.applications.values || [] } catch (e) { return [] }
    var out = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay === true) continue
      var id = root.normalizeDesktopId(entry.id)
      if (!id) continue
      out.push({ id: id, label: String(entry.name || id) })
    }
    out.sort(function(a, b) {
      var x = a.label.toLowerCase(), y = b.label.toLowerCase()
      return x < y ? -1 : x > y ? 1 : 0
    })
    return out
  }

  function isHidden(path) { return root.hiddenPaths.indexOf(path) >= 0 }

  function isPinned(id) {
    for (var i = 0; i < root.pinnedApps.length; i++) if (root.pinnedApps[i].id === id) return true
    return false
  }

  function pinApp(entry) {
    if (!entry || !entry.id || root.isPinned(entry.id)) return
    var next = root.pinnedApps.slice()
    next.push({ id: entry.id, label: entry.label })
    root.pinnedApps = next
    root.saveState()
    root.rebuild()
  }

  function unpinApp(id) {
    var next = []
    for (var i = 0; i < root.pinnedApps.length; i++) {
      if (root.pinnedApps[i].id !== id) next.push(root.pinnedApps[i])
    }
    root.pinnedApps = next
    root.saveState()
    root.rebuild()
  }

  function toggleHidden(path) {
    var next = root.hiddenPaths.slice()
    var at = next.indexOf(path)
    if (at >= 0) next.splice(at, 1)
    else next.push(path)
    root.hiddenPaths = next
    root.saveState()
    root.rebuild()
  }

  // An AppImage is just an executable. execArgv keeps the path in a positional
  // parameter, so a space or a quote in a filename stays literal.
  function launchPath(path) { Util.execArgv([path]) }

  // The exact command Omarchy's own AppLibrary.launch() runs, so a pinned app
  // starts in the same systemd scope as one started from the system menu, and
  // ids with dots in them (org.telegram.desktop) still resolve.
  function launchDesktop(id) {
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
  }

  // ── Menus ──────────────────────────────────────────────────────────────────

  function rootRows() {
    var list = [
      { label: "Clarity",       glyph: "◉", detail: "CRT",  run: function() { root.launchApp(root.clarityPaths, ["--crt"]); root.close() } },
      { label: "EmuLatte",      glyph: "⌸", detail: "CRT",  run: function() { root.launchApp(root.emulattePaths, ["--crt"]); root.close() } },
    ]

    // Discovered AppImages before pinned system apps: ~/Applications is where
    // this machine's own builds land, and they are what someone turning the TV
    // on is reaching for.
    for (var i = 0; i < root.appImages.length; i++) {
      (function(app) {
        if (root.isHidden(app.path)) return
        list.push({ label: app.label, glyph: "▣", detail: "",
          run: function() { root.launchPath(app.path); root.close() } })
      })(root.appImages[i])
    }

    for (var j = 0; j < root.pinnedApps.length; j++) {
      (function(app) {
        list.push({ label: app.label, glyph: "◈", detail: "",
          run: function() { root.launchDesktop(app.id); root.close() } })
      })(root.pinnedApps[j])
    }

    list.push({ label: "Play something", glyph: "⌕", detail: "",    run: function() { root.run(["omarchy-shell", "shell", "toggle", "io.github.fromchaoscomesclarity.clarity"]); root.close() } })
    list.push({ label: "Sound",     glyph: "◀", detail: root.volText, submenu: "sound" })
    list.push({ label: "Network",   glyph: "≋", detail: root.netText, submenu: "network" })
    list.push({ label: "Bluetooth", glyph: "✳", detail: root.btText || (root.btPowered ? "ON" : "OFF"), submenu: "bluetooth" })
    // Last, and in this order: the two rows that change the menu itself belong
    // below the rows that use it.
    list.push({ label: "Add app",    glyph: "+", detail: "", submenu: "addapp" })
    list.push({ label: "Remove app", glyph: "−", detail: "", submenu: "removeapp" })
    return list
  }

  /*
   * Every installed application, in one flat list, driven by a d-pad. Nothing
   * clever: already-pinned entries are dropped rather than greyed out, because
   * the list is long enough without rows that cannot be chosen, and a letter
   * key jumps through it (see jumpToLetter).
   */
  function addAppRows() {
    var entries = root.desktopEntries()
    var list = []
    for (var i = 0; i < entries.length; i++) {
      (function(entry) {
        if (root.isPinned(entry.id)) return
        list.push({ label: entry.label, glyph: "+", detail: "",
          // Back to the root menu, landing *on* the app that was just pinned
          // rather than back on "Add app" — the confirmation is the row itself,
          // highlighted, where it will be from now on.
          run: function() { root.pinApp(entry); root.goBack(); root.selectRowByLabel(entry.label) } })
      })(entries[i])
    }
    if (!list.length) list.push({ label: "No applications found", glyph: "·", detail: "", disabled: true })
    return list
  }

  /*
   * Removal, and the reason this is one menu rather than two.
   *
   * A pinned entry is a line in a JSON file, so removing it removes it. A
   * discovered AppImage is a 120 MB file the user put in a folder, and a menu
   * that appeared to delete it would be lying about which one it did. So those
   * rows toggle shown/hidden instead, hidden ones stay listed, and getting one
   * back is the same single press that hid it — which is what makes hiding
   * safe to offer at all.
   */
  function removeAppRows() {
    var list = []
    for (var i = 0; i < root.pinnedApps.length; i++) {
      (function(app) {
        list.push({ label: app.label, glyph: "−", detail: "REMOVE", keep: true,
          run: function() { root.unpinApp(app.id) } })
      })(root.pinnedApps[i])
    }
    for (var j = 0; j < root.appImages.length; j++) {
      (function(app) {
        var hidden = root.isHidden(app.path)
        list.push({
          label: app.label,
          glyph: hidden ? "○" : "●",
          detail: hidden ? "HIDDEN" : "SHOWN",
          keep: true,
          run: function() { root.toggleHidden(app.path) }
        })
      })(root.appImages[j])
    }
    if (!list.length) list.push({ label: "Nothing to remove", glyph: "·", detail: "", disabled: true })
    return list
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
    if (id === "addapp")    return addAppRows()
    if (id === "removeapp") return removeAppRows()
    return rootRows()
  }

  readonly property var menuTitles: ({
    "root":      "OmaCRT",
    "sound":     "OmaCRT › Sound",
    "network":   "OmaCRT › Network",
    "bluetooth": "OmaCRT › Bluetooth",
    "addapp":    "OmaCRT › Add app",
    "removeapp": "OmaCRT › Remove app"
  })

  function rebuild() {
    root.rows = buildRows(root.menuId)
    // ⚠️ A menu can get shorter under the cursor — unpinning the last app in
    // "Remove app" does exactly that. Without the clamp the selection points
    // past the end and the next keypress acts on nothing.
    if (root.currentIndex >= root.rows.length) root.currentIndex = Math.max(0, root.rows.length - 1)
    root.syncView()
  }

  /*
   * Put the viewport back where the selection is.
   *
   * ⚠️ The ListView's own onCurrentIndexChanged is not enough, twice over.
   * Replacing the model does not change currentIndex, so a menu that comes back
   * with its selection already below the fold (pin an app, land back on it nine
   * rows down) draws from the top with nothing highlighted. And a jump to a
   * row whose delegate does not exist yet — pressing "z" in a list of 250
   * applications — asks the view to scroll somewhere it has not laid out, and
   * it quietly does nothing: hence forceLayout() first.
   *
   * The one-shot timer rather than Qt.callLater because restart() collapses a
   * burst (open a menu, then immediately jump) into the single last request,
   * instead of letting the menu's own scroll-to-top land after the jump.
   */
  function syncView() { viewSyncTimer.restart() }

  Timer {
    id: viewSyncTimer
    interval: 1
    repeat: false
    onTriggered: {
      actionList.forceLayout()
      actionList.positionViewAtIndex(root.currentIndex, ListView.Contain)
    }
  }

  function selectRowByLabel(label) {
    for (var i = 0; i < root.rows.length; i++) {
      if (root.rows[i].label === label) { root.currentIndex = i; root.syncView(); return }
    }
  }

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
    root.syncView()
  }

  // A d-pad through every installed application is a long way down. Typing a
  // letter jumps to the next row starting with it: free on the keyboard half of
  // "gamepad or keyboard", and it costs the gamepad half nothing, because no
  // gamepad button produces a letter.
  function jumpToLetter(ch) {
    var c = String(ch || "").toLowerCase()
    if (!c || !root.rows.length) return
    for (var n = 1; n <= root.rows.length; n++) {
      var i = (root.currentIndex + n) % root.rows.length
      var row = root.rows[i]
      if (row && !row.disabled && String(row.label || "").toLowerCase().charAt(0) === c) {
        root.currentIndex = i
        root.syncView()
        return
      }
    }
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
    // The folder is the configuration, so it is re-read every single open. A
    // newly dropped AppImage is a row on the next SUPER+M — no restart, no
    // edit here. It costs one `find` over one directory.
    root.scanAppImages()
    root.rebuild()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }

  Component.onCompleted: {
    ensureStateDir.running = true
    root.scanAppImages()
    root.rebuild()
    // After mkdir has had a tick: FileView cannot load from a directory that
    // does not exist, and on a first run this is that directory.
    Qt.callLater(function() { stateFile.reload() })
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
        } else if (event.key === Qt.Key_PageDown) {
          root.moveSelection(5); event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
          root.moveSelection(-5); event.accepted = true
        } else if (event.text && /^[A-Za-z0-9]$/.test(event.text)) {
          root.jumpToLetter(event.text); event.accepted = true
        }
      }

      /*
       * The safe area. Not decoration — it is where the tube stops showing the
       * signal (docs/RESEARCH.md §4).
       *
       * ⚠️ Asymmetric, and deeper at the top than the 5% broadcast standard,
       * because this set is: at 5% the title and the clock were still behind
       * the bezel on the real screen while everything below them was fine.
       * Broadcast-safe is a floor for an unknown set, not a measurement of
       * yours. 10% top is what this tube actually needs.
       */
      Item {
        anchors.fill: parent
        anchors.leftMargin: Math.round(parent.width * 0.05)
        anchors.rightMargin: Math.round(parent.width * 0.05)
        anchors.topMargin: Math.round(parent.height * 0.10)
        anchors.bottomMargin: Math.round(parent.height * 0.06)

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
              text: root.menuTitles[root.menuId] || "OmaCRT"
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
