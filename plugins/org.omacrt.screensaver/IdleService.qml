import QtQuick
import Quickshell
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
   * IdleMonitor is the Wayland idle-notify protocol, which is seat-wide: it
   * sees the keyboard, the mouse, and — because the gamepad daemon emits real
   * uinput events — the controller too, with nothing extra wired up.
   *
   * respectInhibitors matters more than it looks: a game or a video player
   * holds an idle inhibitor while it runs, so this cannot paint over something
   * the user is watching without touching the pad.
   */
  IdleMonitor {
    enabled: true
    timeout: root.idleSeconds
    respectInhibitors: true
    onIsIdleChanged: root.ipc(isIdle ? "summon" : "hide")
  }
}
