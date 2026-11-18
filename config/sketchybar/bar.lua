local colors = require("colors")
local ui = require("ui")

-- Items with position q or e line up on either side of the notch. notch_width defaults to 200; the measured value is in ui.lua.
-- topmost must be on. On macOS 27, MenuBarAgent keeps a transparent level-25 window over the top edge even while the menu bar is hidden.
-- Below it, the bar gets neither hover nor clicks, and a click reveals the hidden menu bar. pkgs/sketchybar patches topmost to level 26.
sbar.bar({
	position = "top",
	topmost = "on",
	height = ui.bar_height,
	blur_radius = 0,
	color = colors.transparent,
	notch_width = ui.notch_width,
})
