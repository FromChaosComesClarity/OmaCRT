import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

/*
 * The idle timer, and the reason it is not inside the overlay.
 *
 * ⚠️ omarchy-shell instantiates an `overlay` plugin lazily — the QML is not
 * created until something summons it the first time. That is sensible for a
 * launcher nobody has opened yet, and fatal for a screensaver: an IdleMonitor
 * living inside the overlay does not exist until the overlay has already been
 * shown, so the thing that is supposed to appear on its own never does. It was
 * verified exactly that way here — summoning it by hand once, then leaving the
 * machine alone, made every later idle work.
 *
 * A `service` plugin is loaded when the shell starts, which is what a timer
 * needs. So the split is: this watches, the overlay draws.
 *
 * The summon goes through the shell's own IPC rather than reaching for the
 * overlay object directly, because a service and an overlay are separate plugin
 * instances with no reference to each other — and because `summon`/`hide` are
 * the same verbs a person would type, which makes this testable by hand.
 */
Item {
  id: root

  // How long the machine has to be left alone. Deliberately longer than
  // Omarchy's 150s default: at 150s a screensaver interrupts reading a menu,
  // and the burn-in risk it defends against is measured in hours, not minutes.
  readonly property int idleSeconds: 240

  readonly property string pluginId: "org.omacrt.screensaver"

  function ipc(verb) {
    Quickshell.execDetached(["omarchy-shell", "shell", verb, root.pluginId, "{}"])
  }

  /*
   * ⚠️ "Idle" is not the same question as "nobody is here", and the difference
   * is a screensaver painting over a game you are in the middle of playing.
   *
   * The Wayland idle-notify protocol counts *seat* input: keyboard and mouse.
   * A gamepad speaking to a game through evdev or SDL never touches the seat,
   * so an hour of playing with a controller is indistinguishable from an empty
   * room. respectInhibitors catches the well-behaved cases — a video player, a
   * game that sets an inhibitor — and misses every game that does not bother,
   * which is most of them.
   *
   * So a fullscreen window vetoes the screensaver outright. This is the same
   * heuristic the gamepad daemon uses to decide that a game has taken over
   * (docs/RESEARCH.md §2): it needs no maintained list of which windows count
   * as games, and a fullscreen app is simultaneously the case where burn-in is
   * least likely — the picture is moving — and where covering it is least
   * forgivable.
   */
  property bool fullscreenActive: false

  Process {
    id: activeWindow
    command: ["hyprctl", "-j", "activewindow"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var win = JSON.parse(text || "{}")
          root.fullscreenActive = (win.fullscreen || 0) !== 0
        } catch (e) {
          // ⚠️ Fail *open*. An unreadable answer must not leave the screensaver
          // permanently vetoed, or it silently protects nothing — which is the
          // failure you never notice until the phosphor has.
          root.fullscreenActive = false
        }
      }
    }
  }

  // Re-asked on every Hyprland event rather than polled: focus changes,
  // fullscreen toggles, opens and closes all arrive here, and nothing else can
  // change the answer.
  Connections {
    target: Hyprland
    function onRawEvent(event) { activeWindow.running = true }
  }

  Component.onCompleted: activeWindow.running = true

  IdleMonitor {
    // Disarmed entirely while something is fullscreen, rather than being left
    // to fire into a veto: the timer then starts from zero when the game exits,
    // which is the behaviour you want anyway.
    enabled: !root.fullscreenActive
    timeout: root.idleSeconds
    respectInhibitors: true
    onIsIdleChanged: {
      if (isIdle && root.fullscreenActive) return
      root.ipc(isIdle ? "summon" : "hide")
    }
  }

  // Leaving a game must not find the screensaver already up from before it
  // started. Cheap, and it makes the veto a guarantee rather than a race.
  onFullscreenActiveChanged: if (fullscreenActive) root.ipc("hide")
}
