local colors = require("colors")
local ui = require("ui")

-- position が q と e の item はノッチの両脇に並ぶ。notch_width の既定は 200 で、実測値は ui.lua にある。
sbar.bar({
	position = "top",
	height = ui.bar_height,
	blur_radius = 0,
	color = colors.transparent,
	notch_width = ui.notch_width,
})
