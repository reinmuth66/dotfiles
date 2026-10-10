local colors = require("colors")
local ui = require("ui")

-- Items with position q or e line up on either side of the notch. notch_width defaults to 200; the measured value is in ui.lua.
sbar.bar({
	position = "top",
	height = ui.bar_height,
	blur_radius = 0,
	color = colors.transparent,
	notch_width = ui.notch_width,
})
