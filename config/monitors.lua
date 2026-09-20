-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = "auto"

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- OmaCRT: force the composite adapter to its target 720x480 rather than the
-- "preferred" 1280x720 its EDID advertises -- see docs/RESEARCH.md. Native
-- res, no scaling (scale=1): this resolution IS the design target, not
-- something to be scaled up/down from.
hl.monitor({ output = "HDMI-A-2", mode = "720x480@60", position = "auto", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })
