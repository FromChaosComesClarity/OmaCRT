-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- OmaCRT: the launcher, from a keyboard. M for Menu -- free in a stock
-- Omarchy, and findable without looking on the couch keyboard, which matters
-- more than mnemonics when the machine is across the room. (SUPER + ` was the
-- first choice and was dropped: on this machine's ABNT2 layout the backtick
-- is nowhere near where a US layout puts it.)
o.bind("SUPER + M", "OmaCRT: toggle launcher", "omarchy-shell shell toggle org.omacrt.launcher '{}'")

-- The same two, for the gamepad. F13/F14 are unmapped on any real keyboard:
-- the daemon (daemon/omacrt_input.py) uses them as a synthetic-only control
-- channel -- Start/Guide -> F13, Select -> F14.
--
-- ⚠️ These do nothing unless `omacrt-input` is running, and it is deliberately
-- disabled on this machine: the pad is for games, and the interfaces are
-- driven with a keyboard. Start it again with
-- `systemctl --user enable --now omacrt-input` if that changes.
o.bind("F13", "OmaCRT: toggle launcher", "omarchy-shell shell toggle org.omacrt.launcher '{}'")
o.bind("F14", "OmaCRT: toggle controller cheatsheet", "omarchy-shell shell toggle org.omacrt.cheatsheet '{}'")
